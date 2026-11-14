# RESCÉNE account API

Go 1.26.5+, Fiber v3 and **FalkorDB**. All accounts are `User` nodes in a FalkorDB graph; there is no SQL database. The official Go client submits parameterized Cypher queries. An exact-match index supports account lookup, and an atomic `MERGE` on the lowercase username prevents duplicate registrations across API processes.

## Run locally

From this directory:

```bash
docker compose up -d --wait
./run.sh
```

The API listens on `http://127.0.0.1:8080`. `GET /healthz` checks its database connection. `run.sh` loads the ignored server `.env`, builds the binary, and starts it. Start the Godot project normally: **splash → login/register → lobby**. Registration signs in immediately. The profile button shows the user's server-managed wallet, copy/refresh controls and **Log Out**.

FalkorDB is pinned to an image digest, bound only to the local host on port 6379, with append-only persistence in the `rescene-rhythm_accounts` Docker volume. `docker compose down` retains accounts; removing that volume deletes them. The database browser is not exposed. For an existing FalkorDB instance, skip Compose and set `FALKORDB_URL` (supports `redis://`, `rediss://`, `falkor://`, `falkors://`, including authenticated URLs).

Optional settings are in `.env.example`. `./run.sh` loads `.env` automatically. When using `go run .` directly, export the variables first:

```bash
cp .env.example .env
set -a
source .env
set +a
go run .
```

| Variable | Default | Purpose |
| --- | --- | --- |
| `APP_ENV` | `development` | Any other value requires an explicit JWT secret. |
| `ADDR` | `127.0.0.1:8080` | API listener. |
| `FALKORDB_URL` | `redis://127.0.0.1:6379` | Server-only database connection. |
| `FALKORDB_GRAPH` | `rescene` | Account graph. |
| `JWT_SECRET` | generated in development | At least 32 random bytes; generate with `openssl rand -hex 32`. |
| `JWT_TTL` | `1h` | Access JWT lifetime, between `1m` and `24h`; the independent refresh session lasts 30 days. |
| `DATA_DIR` | `./data` | Development signing-key directory, separate from database persistence. |
| `ENGINE_BASE_URL` | `https://engine.fluentxverse.com` | Server-to-server Engine API origin; HTTPS required. |
| `ENGINE_API_KEY` | unset | Enables automatic server-managed player wallets; needs `wallets:write`. Keep server-only. |
| `ENGINE_PROJECT_ID` | unset | Required when Engine is enabled; pins accepted responses to the expected project. |

Development persists an auto-generated signing key in `data/jwt.key` with mode 0600. Keep the same explicitly configured secret across production restarts/instances. The database URL and signing key belong only on the server. `backend/.gdignore` and the export exclusions keep the backend out of the game package.

## API

| Method | Path | Request / response |
| --- | --- | --- |
| POST | `/api/v1/auth/register` | JSON `username`, `password`, `accept_policies`, `terms_version`, `privacy_version`; returns 201 and a session. |
| POST | `/api/v1/auth/login` | Same JSON; returns 200 and a session. |
| POST | `/api/v1/auth/refresh` | JSON `refresh_token`, `request_id` (32 lowercase hex characters); rotates the session and returns new credentials. |
| POST | `/api/v1/auth/logout` | JSON `refresh_token`; revokes that device session, including an in-flight rotation. |
| POST | `/api/v1/auth/session` | Bearer-authenticated upgrade for legacy JWT-only clients; returns a new 30-day refresh session. |
| GET | `/api/v1/auth/me` | `Authorization: Bearer <access_token>`; returns the current `user`. |
| GET | `/healthz` | 200 when the database is reachable; otherwise 503. |

A session response contains `user: {id, username, created_at}`, `access_token`, `token_type: "Bearer"`, `expires_in` in seconds, `refresh_token`, `refresh_expires_in` in seconds, and `refresh_expires_at` as Unix seconds. Errors use `{ "error": { "code": "…", "message": "…" } }`. Invalid input returns 400, incorrect credentials or an invalid token 401, duplicate usernames 409, and throttled attempts 429 with `Retry-After`.

Usernames are 3–24 ASCII letters, numbers or underscores. Matching is case-insensitive; display casing is retained. Passwords require at least 8 characters and at most 72 UTF-8 bytes, and are never trimmed. Password hashes use bcrypt cost 12. No plaintext passwords or hashes are returned. Login errors do not reveal whether an account exists. JWT validation requires HS256, the expected issuer/audience, expiry, and a real account subject.

Persistent login uses **30-day rolling refresh sessions** in both debug and release builds. Registration/password login creates fresh random refresh credentials. The game refreshes on startup, one minute before access expiry, and once after an unexpected protected-request 401; concurrent requests wait for the renewal. A successful refresh rotates the token and renews its 30-day expiry. After 30 days without successful renewal, a password login is required. The access JWT remains short-lived (one hour by default); it is not the lifetime of persistent login.

Each account has `HAS_LOGIN_SESSION` relationships to `LoginSession` nodes. The graph stores token digests, expiry and the last rotation request ID, never raw refresh tokens. Rotation atomically matches an unexpired current digest. The client saves a cryptographically random 128-bit `request_id` before sending. Retrying that exact request can recover the same successor token after a lost response or process/API restart; the server derives it with HMAC and its stable signing key. A different request using an already-rotated token is rejected. Once the successor rotates again, the older retry is invalid. Independent devices retain separate sessions. Refresh/logout are limited to 60 requests/minute/IP; legacy upgrades to 15.

The game atomically saves versioned JSON text containing access/refresh credentials and pending rotation ID in `user://auth_token_<API-hash>.txt`, with owner-only permissions on Linux/Android. Files remain separate per API address, and no password is saved. `RESCENE_AUTH_FILE` can override the file in debug test runs. The login screen verifies saved credentials through the backend before entering the lobby. Transient failures preserve credentials and pending rotation intent; invalid/expired refresh credentials and logout clear them. Logout attempts to revoke that refresh session on the server, including the successor of a concurrent refresh. If offline, local logout still completes; any server credential cannot be revoked until it is reachable. Already-issued access JWTs remain valid until their short expiry. A valid old JWT-only text file upgrades through `/auth/session`; an expired legacy JWT cannot be renewed without a password. Account recovery/password changes are outside this flow.

Run `python3 tools/test_auth_refresh.py --godot /path/to/godot` for isolated real-game process tests: registration, repeated login, automatic renewal, simultaneous protected calls, expired-access startup, refresh recovery after response loss, API/game restarts, transient outages, legacy file migration, true refresh expiry and logout revocation. No production users or Engine wallets are touched.

Personal-best files remain local and separate per account ID. Online clear summaries update progression and validated cloud bests in FalkorDB. Public song/difficulty leaderboards and player profiles are available; input replay verification is implemented for new online runs. Existing unauthenticated scores are retained separately and are not silently attached to a new account.

## Progression API

All routes require the same bearer JWT:

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/api/v1/progression` | Level, total/current-level XP, Starlight, mission status, unlocked/equipped cosmetics, UTC reset date. |
| POST | `/api/v1/daily-login/claim` | `{date: "YYYY-MM-DD", day: 1}` claims the expected calendar day (1–7); date must match the snapshot's server UTC date. Returns a reward receipt and updated progression. |
| POST | `/api/v1/runs` | `{request_id, song_id, difficulty, revision, replay_version: 4}` atomically spends 1 energy and creates one active server-timed run; its ID is returned in `reward.id`. A new ticket replaces an abandoned attempt. |
| POST | `/api/v1/runs/:id/complete` | `{score, max_combo, counts: {PERFECT, GREAT, GOOD, MISS}, trace, replay}` validates the clear and returns a reward receipt. |
| POST | `/api/v1/missions/:id/claim` | `{day: "YYYY-MM-DD"}` claims a completed mission. Daily claims require the current server UTC day; career claims ignore the day. |
| POST | `/api/v1/progression/equip` | `{id}` equips an unlocked profile title or frame. |

The progression snapshot also includes persisted player-profile totals: `clears`, `max_combo`, `full_combos`, `charts_cleared` (distinct song/difficulty clears), and `best_accuracy` in hundredths of a percent (10000 = 100.00%). These are read from the existing progression record and require no data migration.

`daily_login` contains `date`, `completed` (claimed days in the displayed cycle), `next_day`, `claimed_today`, and seven `rewards` with `day`, `xp`, `starlight`. Eligibility uses the server's UTC date; `server_time` and `daily_reset_at` anchor the client's monotonic countdown, independent of its device wall clock. Rewards are 50/30, 60/40, 75/50, 90/60, 100/75, 125/100 and 200/200 XP/Starlight. Missed days preserve progress; Day 7 rolls to Day 1 on the next UTC day. The claim and balances share the existing progression CAS. Concurrent/retried claims return the same receipt with `already_claimed: true` after the first successful write; stale dates or the wrong calendar day return 409. A receipt includes `date`, `day`, `xp`, `starlight`, `level_before`, `level_after`, and cosmetic `unlocks`. The claim route is limited to 30 requests/minute/IP. Existing accounts begin at Day 1 without a migration or balance reset.

Mutation responses contain `progression` and `reward` (null for equipping). The client never supplies XP, levels, currency rewards or mission counters. The server computes them. Clear rewards require at least 50% accuracy and the complete chart judgment count. Unknown chart IDs/difficulties, impossible combos, inconsistent scores and early/expired completions are rejected. Runs live for two hours; repeated submissions return the original receipt without awarding again. The last 32 receipts are retained; older run IDs cannot become active again. Run start/mission/equip routes allow 30 requests/minute per IP; completion allows 60.

Each `User` has a `HAS_PROGRESSION` relationship to a `Progression` node indexed by owner ID. Its JSON payload holds counters, daily/career claims, equipment, the active ticket and bounded receipts. A versioned Cypher compare-and-set commits the complete state atomically. Concurrent claims/completions retry on a version conflict, preventing duplicate rewards or overwritten counters even across API instances. Initializing an existing account is lazy and does not modify its credentials. No SQL is used.

The generated `charts.json` embeds all 128 chart IDs, titles, revision hashes, difficulties, playable durations and scoring-unit totals into the Go binary. Whenever charts/catalog change, run `godot --headless --path . --script res://tools/export_progression_catalog.gd` from the game directory, rebuild the backend, and rerun tests. Normalized note times, lanes, hold checkpoints and curve points are also embedded for input replay verification. Audio is not shipped to the API.

See the main README for exact XP, level, mission and cosmetic rules. New online runs require a chart-bound input replay. The server recalculates the result through an independent judge rather than trusting judgment summaries. Plausible machine-generated inputs remain possible; this provides gameplay-rule validation rather than proof of human input or device attestation.

When a clear cannot reach the server, the game atomically retains a pending completion under an API/account-specific `user://pending_progression_<hash>.json`. Refresh or a new login retries it with the same ticket ID. Logout clears the in-memory account but leaves that account's pending queue available for its next login. No passwords or JWTs are included in this queue. Expired or invalid tickets are discarded with the server's error rather than awarded locally.

## Scores and public rankings

All routes require a bearer JWT. Read routes never accept an account identity for the caller's private records:

| Method | Path | Response |
| --- | --- | --- |
| GET | `/api/v1/records` | Current player's current-chart cloud `records`, at most 128. |
| GET | `/api/v1/leaderboards?song_id=…&difficulty=…` | `leaderboard: {top, nearby, me, total}` for the current chart revision; Top 25 and up to five nearby positions. `me` is null for an unranked player. |
| GET | `/api/v1/players/:id` | Whitelisted public `profile`: ID, username, join date, level/XP, equipped title/frame, clear statistics and cloud records. No wallet, credentials, balances, missions or receipts. |

Ranking entries include `avatar: {id, url}` for the player’s current display picture, or `null` when none is set. Top 25, nearby positions and `me` use the same photo reference; refreshing picks up replacements and deletions. Photo URLs use the authenticated player-media endpoint. Gallery photos and private account fields are not included.

Rank positions are unique and deterministic: descending score, descending max combo, ascending achievement time, ascending account ID. A new chart revision has a separate board. Each user has at most one `HAS_PERSONAL_BEST` relationship per song/difficulty to a `PersonalBest` node. Its key, chart key and owner are indexed. The first better score in a revision replaces the previous best; equal scores require a better combo. An exact tie or worse score preserves the original achievement time. Updating progression and a best uses one graph write gated by the progression version; a rejected compare-and-set cannot create a score node. Duplicate completion receipts leave the original record intact.

New run requests use `replay_version: 5` and the hash from `("momentum-v1:" + JSON.stringify(JSON.data).sha256_text()).sha256_text()` as `revision`. A mismatch is 409; missing/unsupported replay protocol is 400. Each ticket stores its protocol version. Version 4 uses ±60ms Perfect, ±105ms Great, ±180ms collection, 0.72-lane trace tolerance and 160ms drift grace. Versions 3 and 4 remain supported with their original rules, and completion must match the ticket’s version. Version 5 adds upward swipe notes. Completions contain `replay: {version: 5, run_id, revision, end_us, events}`. Each event is an integer tuple `[time_us, action, pointer_id, lane_units]`, where actions are 0=press, 1=move, 2=release, 3=pause, 4=vertical sample; lane units are 1/10,000 of a lane. For action 4, the last value is the vertical coordinate in 0–10,000 units over the 1080-high stage, rather than a lane. Only version 5 accepts vertical samples. Swipe collection requires an upward stroke starting in the collector band, at least 450 vertical units within 8–220ms, with upward distance at least the horizontal distance; one touch can collect one swipe note. Swipe timing is judged when the stroke crosses the distance threshold. Taps, keyboard keys and downward motion cannot collect swipe notes. Pointer IDs are native touches 0–31, mouse −1, or keyboard −100 through −104 with a fixed lane per key. Up to ten contacts can be held simultaneously. Movement outside the hit area uses lane −10. Presses must be released before reusing a held pointer.

The server runs the authoritative chart at 120 Hz, applying ordered inputs at their recorded song times. It independently evaluates tap timing, holds, release grace, smooth curved paths, keyboard handoff, health, judgments, weighted score and maximum combo. Declared totals must match. The end time permits the UI's ±150 ms calibration plus 5 ms of codec-duration rounding. Server wall-clock completion bounds and ticket ownership/expiry also apply. Replays are limited to 24,000 events, 1 MiB requests and a 300-second supported chart duration. Two replay validators run concurrently per process; overload returns retryable 503 and the client retains its completion. Other API bodies remain limited to 4 KiB. Replay JSON is stored only in the account/API-scoped client retry queue (up to 2 MiB), and integer fields are restored after JSON reload. The backend stores verified bests and receipts, not raw movement streams.

Receipts include `verification` matching the ticket’s replay version (currently 5); only uninterrupted validated clears have `ranked: true`. An active-play pause is verified with the same regrab behavior but yields `unranked_reason: "paused"` and progression only. Countdown pauses do not enter the replay. Old tickets without the new protocol can finish unranked; new legacy-protocol tickets are refused. `PersonalBest.verification=2` is required by board and cloud-record queries. Existing unverified bests stay stored and can be replaced by a lower first verified score. They never silently become verified. No account or progression reset is performed. Local bests have no upload endpoint.

Use `python3 tools/test_replay.py --godot /path/to/godot` from the game directory for actual Godot-produced streams checked against Go across every chart and additional timing/input cases. `FALKORDB_TEST_URL=redis://127.0.0.1:6379 go test -race ./...` covers malformed/tampered streams, unknown actions, over-limit pointers/events, empty fabricated perfects, invalid hold/slide evidence, duplicate completions, protocol migration and paused-run eligibility.

## Server-managed player wallets

The backend calls Engine's **`POST /v1/user-wallets/managed`** with `X-GMR-Engine-Key`, stable `userID` (the account's immutable ID) and `authProvider: "rescene_password_v1"`. This is the user-linked server-managed wallet route in the supplied Engine source. `/v1/wallets` in the dashboard reference creates project-level wallets and is not used for player provisioning. Both keep private keys in Engine's encrypted vault; this API never requests or stores private keys.

Registration and login return a public `user.wallet` object with `status`, `custody`, and, once ready, Engine wallet `id`, `address`, and `created_at`. Restored sessions receive the same public data through `/api/v1/auth/refresh` (and `/api/v1/auth/me`). Wallet setup runs asynchronously so an Engine outage does not prevent account creation, login or gameplay. It does not mint tokens, transfer funds, request signatures or change game Starlight balances.

Protected routes:

- `GET /api/v1/wallet`: current authenticated player's public wallet, scheduling missing setup if necessary.
- `POST /api/v1/wallet/provision`: rechecks/schedules that same player's wallet; limited to 6 requests/minute per IP. It cannot replace a ready wallet or accept another player's identity/address.

Statuses: `pending`, `ready`, `retrying`, and `not_configured` when no Engine key is present. Profile reads the wallet once on entry and allows copying the address; it has no setup-status polling or refresh button. No Engine credential is included in game settings, exported assets, JWTs or API responses. `.env` is ignored, mode 0600 locally, and the whole backend is excluded from Godot export.

On startup and every 30 seconds, the worker finds existing accounts without a ready wallet. FalkorDB stores `(User)-[:HAS_WALLET]->(Wallet)` with a key derived from the Engine origin, pinned project ID and account ID. A database-atomic two-minute lease prevents simultaneous app instances from provisioning the same account. Ready links are immutable during ordinary retries. Only public wallet metadata and sanitized operational codes are persisted; neither the API key nor vault references/private keys are stored in FalkorDB.

Failed calls back off for five minutes. The lease is retained after ambiguous timeouts, and retries send the same Engine identity so a previously created wallet can be recovered after a lost response or local save failure. Engine's current handler performs lookup-before-create but is not itself a distributed idempotency transaction; direct concurrent callers bypassing this backend or an unusually long upstream request can still create an orphan wallet at Engine. Do not independently provision this same identity through another service. A stronger cross-service exactly-once guarantee would require an atomic identity/idempotency operation in Engine itself.

The HTTP client verifies TLS, bounds response size, refuses redirects and validates project, user ID, auth provider, managed custody/type, active status and EVM address before saving a link. Raw Engine error bodies and credentials are never returned or logged. Changing a key to another project requires deliberately updating `ENGINE_PROJECT_ID`; never reuse a different project's wallet link.

Tests use fake Engine credentials and disposable FalkorDB graphs. `python3 tools/test_wallet.py --godot /path/to/godot --capture` verifies the game/profile over a local HTTPS Engine fixture using a temporary trusted certificate, without disabling certificate validation or creating real test wallets. Go tests cover existing-user backfill, repeat login/refresh, restart persistence, parallel leases, ambiguous upstream failure recovery, identity validation and redirect rejection. Progression test drivers explicitly disable real Engine provisioning for disposable accounts.

Source contract: the provided local `gmr-engine/internal/httpapi/handlers.go` (`createManagedUserWallet`) and `gmr-engine/internal/httpapi/api.go` routes. [Engine API reference](https://engine.fluentxverse.com/reference).

## Android and deployment

`project.godot` has a configurable `rescene/api/base_url`. Leave it empty for debug defaults: desktop uses `http://127.0.0.1:8080`, Android uses the emulator's host address `http://10.0.2.2:8080`. A desktop `RESCENE_API_URL` environment variable overrides the project value for testing.

For a physical Android device over USB, run `adb reverse tcp:8080 tcp:8080` and set the project's API URL to `http://127.0.0.1:8080` for that debug build. For Wi-Fi development, set `ADDR=0.0.0.0:8080`, use the computer's LAN IP in the project's API URL, and allow the API port through the local firewall. Development HTTP credentials should only use test accounts on trusted networks.

The supplied Android export preset enables `permissions/internet`, ARM64 and x86_64, keeps landscape framing, and excludes backend/tests/tools/previews. Install the matching Godot 4.7.2 export templates and configure the Android SDK/JDK before exporting. Android keyboard focus scrolls the form so fields remain reachable. A device APK has not been built or tested in this environment.

For release, set `rescene/api/base_url` to the deployed **HTTPS** API address. Release builds reject HTTP or an empty address, and TLS certificate verification stays enabled. Run Fiber behind an HTTPS reverse proxy, set `APP_ENV=production` and `JWT_SECRET`, and keep FalkorDB private/authenticated with persistent backups. No production server is deployed by this change.

Auth endpoints are limited per client IP (registration 5/10 minutes, login 15/minute) in the API process. Forwarded headers are deliberately not trusted. When deploying behind a proxy or multiple API replicas, configure explicit trusted proxy IPs and shared/edge rate limiting before accepting public traffic; the default limiter otherwise sees the proxy as a single client.

## Verification

```bash
FALKORDB_TEST_URL=redis://127.0.0.1:6379 go test -race -count=1 ./...
go vet ./...
```

Integration tests use disposable randomly named graphs, remove them afterwards, and cover registration/login, password hashing, persistence across connections, concurrent duplicate signup, validation, throttling and invalid/expired/forged JWTs. Progression tests additionally cover reward math, level boundaries, replayed tickets, concurrent claims, account isolation, daily rollover, locked equipment and version conflicts. Without `FALKORDB_TEST_URL`, database integration tests explicitly skip; configuration and progression-rule tests still run.

From the game directory, `python3 tools/test_progression.py --godot /path/to/godot --capture` builds an isolated API and exercises the real game. It renders previews, ages only its disposable graph's fixture tickets to avoid waiting full songs, tests a real API disconnect/restart and queued result delivery, then removes its own graph. No test-only clock-adjustment API is exposed.

To exercise the Godot account flow without putting test users in the real account graph, start a separate instance:

```bash
ADDR=127.0.0.1:18080 FALKORDB_GRAPH=rescene_ui_test go run .
```

From the game directory, point the test at it:

```bash
RESCENE_API_URL=http://127.0.0.1:18080 /path/to/godot --headless --path . --script res://tests/auth_flow_regression.gd
```

After stopping that test server, delete only its graph with `redis-cli GRAPH.DELETE rescene_ui_test`. The test covers login gating, form validation, real registration, bearer profile lookup, logout, bad-password recovery, login, expiry and offline recovery. `tools/capture_auth.gd` saves native login/register previews when run without `--headless`.

References: [FalkorDB Go client](https://github.com/FalkorDB/falkordb-go), [Fiber v3](https://docs.gofiber.io/), [Godot HTTPRequest](https://docs.godotengine.org/en/stable/classes/class_httprequest.html).

Persistent-login regression: `tests/auth_persistence_regression.gd` supports `RESCENE_AUTH_TEST_MODE=seed|restore|logout|empty|expired|invalid|offline`. Run each in a fresh Godot process against a disposable API graph, with an isolated `RESCENE_AUTH_FILE` path (debug-only override). The `seed` mode registers a test account and saves its token without logging out; `restore` verifies startup reaches the lobby. Use expired/forged token fixtures for rejection modes and an unavailable API for offline recovery. Never print the saved JWT in logs.

## Automatic on-chain score publication

With `LEADERBOARD_ENABLED=true`, replay-verified ranked personal-best improvements are automatically mirrored to the deployed RESCENE leaderboard through the `rescene-rhythm` Engine project. The game backend stores each job in the same FalkorDB compare-and-swap transaction as the best and rewards, so restart or network failure cannot lose a committed publication. Numeric scores are calculated by replay validation; clients cannot submit arbitrary contract scores.

Set these server-only values in `.env` (see `.env.example`):

| Variable | Default / requirement |
|---|---|
| `LEADERBOARD_ENABLED` | `false`; set `true` to activate |
| `LEADERBOARD_ENGINE_API_KEY` | Required dedicated project key with `contracts:write`, `transactions:read` |
| `ENGINE_PROJECT_ID` | Required; `7fe1ecf2-b715-43bc-ba03-3f0a1149bc5d` for rescene-rhythm |
| `ENGINE_BASE_URL` | `https://engine.fluentxverse.com` |
| `LEADERBOARD_CHAIN_ID` | `99901` (Elysium Mainnet) |
| `LEADERBOARD_ADDRESS` | `0xc0bb3f4190d5732878536fc15c75c712e9966d33` |
| `LEADERBOARD_PUBLISHER` | `0x78646fedde207c4574116ac9c455b56e4091c517` |
| `LEADERBOARD_RPC_URL` | `https://rpc.elysium.kinetiq.xyz`; production overrides this with the private provider URL |
| `LEADERBOARD_CONFIRMATIONS` | `3` (allowed range 1–64) |
| `LEADERBOARD_START_BLOCK` | `4774246`, deployment block used for historical event recovery |

The publisher must have gas and `PUBLISHER_ROLE`; Engine must use that project's publisher wallet. Register new chart revisions with `CHART_ADMIN_ROLE`; the worker can register missing authoritative charts when its wallet also holds that role. Disabled boards remain disabled. HTTPS, project identity, RPC chain and publisher role are checked before work starts. The existing wallet provisioning key remains separate and unchanged.

The worker uses two-minute database leases and processes best improvements in commit order per player/chart. Engine persists `Idempotency-Key` identities independently of API key rotation. The worker verifies the destination, method, arguments, receipt success, exact score event, canonical block hash and confirmation depth. It recovers lost responses from chain events and periodically audits confirmed jobs to republish after reorganizations. Network/Engine failures leave jobs retryable without blocking gameplay. Startup backfill includes only current-revision bests with retained replay-validation proof.

Authenticated `GET /api/v1/leaderboard-publication?song_id=...&difficulty=...` returns the caller's publication `status`, `score`, `max_combo`, `transaction_hash`, `chain_id`, `contract_address` and `retrying` flag when applicable. Leaderboard responses include the same optional `on_chain` object. Statuses include `not_published`, `pending`, `submitted`, `retrying`, `confirming`, and `confirmed`. The game shows waiting/syncing/retrying/confirmed beside its personal best; reopen or refresh the leaderboard to fetch current status. Rankings and Near Me remain immediately available from FalkorDB.

`FALKORDB_TEST_URL=redis://127.0.0.1:6379 go test -race ./...` includes disposable-graph publication tests. With `forge`, `cast` and `anvil` available, the end-to-end test deploys the real contract locally, completes a replay-verified run through the API, loses a successful Engine response, recovers after worker restart, and repairs a simulated chain reorganization. It never publishes fixture scores to the deployed chain.

## Momentum scoring

Replay version 3 applies 1× below 20 combo, 2× at 20–39, 3× at 40–59 and 5× at 60+. Each successful scoring unit earns its judgment weight (10/8/5) times the multiplier after incrementing combo. Misses reset the next hit to 1×. The total is normalized against the all-perfect uninterrupted weighted budget for that chart, keeping a 1,000,000 maximum. Holds and slide checkpoints follow the same rules. The server derives bonus points from its own ordered replay judgments; client multiplier claims are never accepted. Accuracy and grades remain unboosted judgment quality, and the clear-reward gate still requires 50% accuracy. Bests store accuracy independently from score.

Scoring revision hashes include `momentum-v1`, separating old and new rankings, board IDs, and device/cloud caches without deleting accounts or progression. Older in-flight tickets can still complete for unranked progression under their original score rules. The deployed chain contract retains its 500,000 score minimum; valid lower momentum scores earn progression and a FalkorDB ranking but do not enqueue an on-chain transaction. Backfill applies the same threshold. New scoring boards are registered lazily by the existing publisher before its first eligible score.

## Energy

`progression.energy` contains `current`, `max: 15`, `run_cost: 1`, `recovery_seconds: 1800`, `next_recovery_at`, `next_recovery_in_seconds`, and `full_at`. Full balances have null recovery timestamps. Missing persisted energy state initializes once to 15; zero is distinct from missing state. Initialization and recovered balances persist through a progression CAS; repeated reads do not issue extra grants. Only server Unix time determines recovery. Partial intervals are retained until full, and time at the cap is never banked.

`POST /runs` spends 1 energy in the same graph write as ticket creation. Empty balances return 409 without a ticket or charge. Malformed chart/protocol requests cannot charge energy. An optional 16-byte hexadecimal `request_id` makes starts idempotent; the current client always supplies and atomically saves it before sending. The most recent 32 start receipts persist through API restarts. Retrying the active request returns the same ticket, even at zero energy. Reusing an ID for another chart or an obsolete attempt returns 409; it cannot revive an old ticket. New explicit retries are new attempts and cost energy. Failed/abandoned songs do not refund it. The client requires an approved ticket before countdown and retains ambiguous start requests per API/account for recovery.

## Read-only marketplace connection

`GET /api/v1/marketplace` requires the player's access JWT. Enable with `MARKETPLACE_ENABLED=true`; configure `MARKETPLACE_CHAIN_ID`, `MARKETPLACE_ADDRESS` and `MARKETPLACE_COLLECTION_ADDRESS` (defaults are the recorded RESCÉNE Elysium Mainnet deployments). `MARKETPLACE_ENGINE_API_KEY` requires `contracts:read` and falls back to `ENGINE_API_KEY`. Keep it server-only. The separate leaderboard publishing key does not need additional permissions.

The backend uses Engine's `/v1/rpc/read` and `/v1/contracts/read` to check the chain, verify `contractType() == MarketplaceV3` and read `totalListings()`. Successful responses include `status: connected`, decimal-string `total_listings`, `checked_at`, public contract addresses and `checkout_enabled: false`. Total listings counts all created IDs, including cancelled or sold listings; it is not the available-stock count. Successes are cached 30 seconds, failures 5 seconds. Upstream failures return 503 without a fabricated zero count; disabled integration returns `not_configured`. No private key, Engine key or upstream error details are sent to the game.

The contract-status route itself is read-only. The separate shop routes below enable only the real Energy Drink listing. Cards and packs remain previews with no authoritative token IDs/prices. An HTTP 202 from Engine only means queued. Engine's reference documents the original thirdweb eight-field listing tuple and the string-encoded tuple arguments expected by Engine.

Tests: `FALKORDB_TEST_URL=redis://127.0.0.1:6379 go test -race ./...` uses isolated temporary graphs and a fake Engine. Optional read-only live check: source the backend `.env`, then run `MARKETPLACE_LIVE_TEST=true go test -run TestMarketplaceLiveReadOnly -v`.


## STARL treasury reward payouts

Set `STARLIGHT_ENABLED=true` with the addresses in `.env.example`. STARL and the immutable treasury-only distributor are deployed on Elysium Mainnet; all addresses and receipts are recorded in `../contracts/deployments/elysium-mainnet.json`. `STARLIGHT_ENGINE_API_KEY` falls back to `ENGINE_API_KEY` and requires `contracts:write` plus `transactions:read`. Managed-wallet provisioning still needs the existing wallet scopes. Signing keys stay in Engine Vault, and API keys stay on this backend. `STARLIGHT_RPC_URL` is used for independent canonical-chain receipt verification.

`GET /api/v1/starlight` requires the player's JWT and ignores client-supplied wallet/recipient fields. It returns public token/chain metadata, their own managed `wallet_address`, exact decimal strings `balance` / `balance_raw`, and integer-string `pending`. `wallet_pending` waits for provisioning; RPC failures return 503 without fabricating a zero balance. `GET /api/v1/progression` includes `starlight_token` metadata. The HUD reads the actual token balance and refreshes pending transfers automatically. `/api/v1/marketplace` advertises STARL as the payment token when both integrations use the same chain; checkout is enabled separately with SHOP_ENABLED for the configured Energy Drink listing; CARDS_ENABLED adds the five fixed member listings.

Every successful progression CAS also atomically creates a `StarlightPayout` for newly earned Starlight, including clears, missions and daily gifts. A per-token earned high-water mark converts existing balances exactly once. Initial startup backfills existing progression without deleting accounts or changing XP. The ledger is lifetime earned currency, not a spendable token balance, and must not be decremented by future purchases. Changing the Engine/RPC URL or reward distributor does not re-grant historical earnings. Keep pending jobs bound to their original deployment; migrate them explicitly before switching a production token/router.

The worker durably pins the managed destination and scan boundary before sending, uses a stable Engine Idempotency-Key, and calls the distributor's `pay(rewardId,recipient,amount)`. The contract checks the treasury caller and records a recipient/amount digest before `transferFrom`; exact duplicate calls are no-ops, changed payloads revert. No gameplay mint call exists. The approved router allowance is bounded to the initial supply, not unlimited. Low funds/allowance keep payouts queued for retry; replenish the treasury or explicitly renew its finite approval to resume.

A reward is marked confirmed only after the matching RewardPaid event **and** exact treasury-to-player ERC-20 Transfer are found in a successful canonical receipt with `STARLIGHT_CONFIRMATIONS` blocks. Lost responses recover through chain events. Confirmed jobs are periodically rechecked for reorganizations; replacement submissions retain the same on-chain reward ID. Internal provider messages and signing data are never exposed to the client.

Validation: `FALKORDB_TEST_URL=redis://127.0.0.1:6379 go test -race ./...`, `forge test` in `../contracts`, and the strict Godot check plus `tests/starlight_hud_regression.gd`. Tests cover concurrent migration/claims, rejected CAS writes, duplicate completions, exact base units, account ownership, ambiguous Engine responses, wrong-recipient events and noncanonical receipts. Optional read-only live check: source `.env`, then `STARLIGHT_LIVE_TEST=true go test -run TestStarlightLiveReadOnly -v`. Test fixtures never transfer real deployed STARL.

## Real Energy Drink shop

Enable `SHOP_ENABLED=true` with `SHOP_ROUTER_ADDRESS=0x5ace042c739c4b49fef8774a7eb2c54136ef55af`, `SHOP_TOKEN_ID=0` and `SHOP_LISTING_ID=0`. STARL, Marketplace and the shop must share a chain/project. The same server-only Engine key needs contracts:write and transactions:read; the deployed Engine worker supports project-scoped active managed-user signers as well as the default admin. No signer data is returned to Godot. The project treasury covers small bounded testnet gas grants for approvals, protected on-chain against retry duplication.

All routes require the player's JWT:

| Method | Route | Purpose |
|---|---|---|
| GET | `/api/v1/shop/catalog` | Server-selected real items, current stock, fixed STARL prices, maximum quantity 10. |
| POST | `/api/v1/shop/purchase` | JSON `request_id` (16-byte nonzero hex), `item_id: energy_drink` or `scene_01`–`scene_05`, integer `quantity` 1–10, `expected_total` decimal-string whole STARL. |
| GET | `/api/v1/inventory` | Confirmed own-wallet item quantities, verified equipped_card, current/last operation and progression. |
| POST | `/api/v1/inventory/consume` | JSON `request_id`, `item_id: energy_drink`, `quantity: 1`. Rejects full energy and no ownership. |

Neither recipient, token, listing, currency, arbitrary price nor energy amount is accepted from the client. The server quotes the exact pinned listing and serializes item actions per account using a progression CAS and a durable `ShopOperation`. Requests with reused IDs return the original action and reject changed arguments. The worker saves destination, scan boundary and execution intent before submitting. Ambiguous responses recover the stable Engine transaction identity; it never releases an account lock while an execution is uncertain. Client intents are atomically saved per API/account before requests, including conversion of JSON-restored quantities to integer request fields.

The worker checks chain/router bindings, stages an idempotent native gas grant when necessary, signs an exact-amount STARL approval with the managed buyer, then calls `purchase` with the treasury. `EnergyDrinkShop` pulls the exact STARL amount, buys the pinned MarketplaceV3 listing for that buyer, and verifies delivery atomically. A persisted order ID prevents a second charge/delivery even if Engine rebroadcasts. The Marketplace's original thirdweb sale fee comes from proceeds; the buyer pays exactly 100 STARL per unit. No off-chain earnings balance is debited.

For consumption, the managed player approves this immutable operator-only router on the collection. The router can burn only the configured token ID, once per consume ID. The worker verifies a canonical `Consumed` event and matching ERC-1155 burn before a single FalkorDB query writes both the final receipt and the energy refill under the progression CAS. Retrying the claim cannot grant again. Inventory uses a canonical block with the configured confirmation depth. Full balances keep the drink; delayed requests recheck before the first burn submission. If partial recovery reaches full between burn and confirmation, the refill remains capped and may restore less than five.

Pending operations survive API restarts, unavailable RPCs and ambiguous Engine responses. Terminal success requires the actual router event plus the exact STARL payment/ERC-1155 delivery (purchase) or ERC-1155 burn (use). A confirmed idempotent no-op transaction is not mistaken for the original receipt. Failed/uncertain upstream submissions stay locked for recovery rather than inventing a refund or permitting another untracked payment; an operator must inspect receipts if a permanent upstream problem prevents recovery. Do not delete a pending ShopOperation or its progression lock.

Deployment/operator tooling: `../tools/setup_energy_drink.py` saves step IDs before polling mint, approval and listing calls. It never remints a completed stock step. An uncertain launch response requires receipt inspection. The first listing attempt was rejected for its start timestamp without a transaction; the corrected attempt reused the existing stock. `gmr-engine/cmd/energy-shop-operator` deployed the immutable router with Engine's Vault signer and wallet lock and imported its ABI. Source, ABI, launch receipts and the successful live test are in `../contracts/deployments/`.

Default tests use fake chain/Engine calls and disposable graphs. The opt-in `SHOP_LIVE_TEST=true` test **does make testnet transactions**: it creates an isolated test account/wallet, funds it with exactly 100 treasury STARL, purchases/burns one drink and verifies 9→14 energy plus duplicate request recovery. Run only with the expected RESCENE Arbitrum Sepolia configuration and `FALKORDB_TEST_URL`; ordinary test runs skip it. `../tools/test_commerce.py` tests native Godot network/restart behavior against a local mock without chain writes.

## First Scene collectible cards

Enable `CARDS_ENABLED=true` and `CARDS_ROUTER_ADDRESS=0xa8e3dd8cf231da2bf318e0e6c3486c11b6d1acb7` alongside the existing shop configuration. The five cosmetic SR cards cost 450 STARL each: scene_01 Woni, scene_02 Liv, scene_03 Minami, scene_04 May, scene_05 Zena. ERC-1155 token IDs and MarketplaceV3 listing IDs are fixed at 1–5. Preflight checks the card router's token, treasury, collection, market, initial IDs and price independently of the drink router.

`POST /api/v1/collection/equip` requires JWT and JSON `{ "item_id": "scene_03" }`; an empty string removes the favorite. It rejects drinks, unknown cards and unowned cards. Preferences use progression's existing compare-and-set persistence. Inventory returns `equipped_card` only while the managed wallet still owns the card in a confirmed block; public player profiles independently verify it. No score, XP or energy modifiers are applied.

Card checkout uses the same durable ShopOperation outbox with an immutable item ID and pinned router per order. An exact retry is safe; reusing an ID for a different item, operation or quantity is rejected even after completion. Worker execution/receipt checks bind the chosen card, 450 × quantity STARL payment, buyer, collection and token ID. The card router has no consumption method and needs no ERC-1155 burn approval. Do not change a router while its orders are pending; the worker fails closed on a pinned-router mismatch.

`../tools/setup_member_cards.py --execute` minted and listed the five cards using saved exact Engine request bodies and stable idempotency keys. It resumes existing transaction IDs instead of reminting. `../tools/deploy_member_shop.mjs` deploys the compiled router once through the Engine operator; its launch guard prevents blind repeats. Public records and metadata live in `../contracts/deployments/member-card-*.json`.

Validation: the normal FalkorDB suite includes card purchases, changed quotes, wrong item receipts, lost responses, duplicate requests, ownership checks, persisted equipment, transfer-out filtering and removal. `CARDS_LIVE_TEST=true go test -run '^TestCardsLiveTestnetPurchaseAndEquip$' -v -timeout 8m` is opt-in and uses the sourced server environment plus FALKORDB_TEST_URL. It creates a disposable graph/account and managed wallet, funds exactly 450 testnet STARL, buys one Minami card, equips it and verifies its public profile. The wallet retains that test card for audit; the test graph is deleted. Existing players are not changed.

Inventory uses one confirmed-block ERC-1155 balanceOfBatch read for all six real item types. To verify the deployed router and that read without any writes, source `.env` and run `CARDS_LIVE_READ_TEST=true go test -run '^TestCardsLiveReadOnly$' -v`. The public live-test wallet remains in the recorded verification JSON.

## Individual PULSE cards and album decks

The local implementation replaces the account/member enhancement draft with unique supply-one ERC-1155 cards, immutable server-rolled Perfect-only stats and skills, on-chain per-token XP/levels/stars, refinement and permanent donor burns. Five member-specific slots are scoped to each song set; all five equipped cards contribute, while the gameplay portrait carousel is visual only. Existing First Scene collectibles remain cosmetic.

See [card rules, skill tables, APIs, protections, deployment prerequisites and rollout status](../docs/cards.md). `PULSE_CARDS_ADDRESS` enables the new VERSION 2 router alongside the existing shop configuration. It is blank by default. This change has not deployed the new router, minted launch stock, restarted the live API or opened sales. LE supply/reissue rules remain deferred.

## Player avatars and gallery

Players can upload a separate profile avatar plus up to **five** gallery photos. Owners can replace/delete them; authenticated players can view them from public profiles. The native profile has a Gallery tab, a full-size viewer, an avatar edit button and the uploaded avatar in the lobby header. File selection uses the native desktop/Android file dialog for JPG/PNG; no broad storage permission is added.

- `GET /api/v1/profile/media` returns the current account's avatar, gallery, revision and limit.
- `POST /api/v1/profile/media/avatar` uploads/replaces the avatar (raw image bytes).
- `POST /api/v1/profile/media/gallery` adds a gallery image.
- `PUT /api/v1/profile/media/gallery/:key` replaces that existing image, even when all five slots are full.
- `DELETE /api/v1/profile/media/:kind/:key` removes that exact avatar/gallery ID. Repeated deletion cannot remove a replacement.
- `GET /api/v1/players/:id/media/:key` serves a referenced JPEG to authenticated players. Removed/unreferenced images return 404. The public player endpoint also includes photo references, never filesystem paths.

Uploads are limited to 8 MiB, JPG/PNG, 20 megapixels and 8192 pixels per side. The server checks actual encoded content, applies JPEG EXIF orientation, strips metadata/GPS, flattens transparency onto pearl, center-crops avatars to at most 512×512 and resizes gallery images to a 1600-pixel maximum side. Images are re-encoded as JPEG. Two decoders run per API process. Existing 4 KiB JSON and 1 MiB replay limits remain enforced.

FalkorDB stores only photo IDs and a compare-and-set revision on User; bytes live under `PROFILE_MEDIA_DIR` (default `data/profile_media`) in owner-specific folders with server-generated IDs. Atomic database updates enforce five gallery images across API processes. Replacements/deletions remove the old file. A lost database response conservatively retains the new file rather than risking a broken committed reference. Network upload errors trigger a state refresh so a saved upload can appear without a blind duplicate retry.

Persist **both** FalkorDB and this folder; database backups alone do not contain photos. Multiple API instances must share the same persistent photo directory or migrate this storage layer to object storage. Photos require a bearer token, are never served as static executable content, and are cached only in the current game's account-scoped memory, cleared on logout. Runtime photos stay under the ignored backend data directory and are excluded from the game export.

Validation: Go/FalkorDB tests cover two-instance concurrent limits, replacement/deletion, account isolation, invalid/oversized images, EXIF orientation, metadata removal and restart persistence. `python3 tools/test_profile_media.py --godot /path/to/godot --capture` exercises the real API and native game with a disposable graph/photo directory, including expired-access refresh during a binary upload and read-only public gallery UI. It writes native screenshots under `previews/player-gallery-*.png` and `previews/player-profile-avatar-20-9.png` using existing artwork as test uploads, then deletes only its temporary accounts/files.

## Social graph, friends and direct chat

The right lobby rail is **Friends**, showing up to five online mutual follows, ordered by most recent conversation, most recent presence, then username. It uses real player avatars and unread badges; empty slots never show placeholder member accounts. The **+** opens Find Players; the header envelope opens Messages. Players can follow/unfollow from username search and public profiles. Both players must follow each other to become friends and send new direct messages. Offline friends still receive messages for their next login.

FalkorDB stores `(:User)-[:FOLLOWS]->(:User)` and `[:BLOCKS]` relationships, per-device `Presence`, participant-pinned `Conversation` nodes and ordered `DirectMessage` nodes. Blocks remove both follow directions and prohibit new messages/follows in either direction. Unblocking never restores a friendship automatically. Previously delivered messages remain available only to their participants. The sender-supplied random request ID is scoped to sender/conversation; identical retries return the original message, while changed text with the same ID is rejected. Concurrent processes serialize sequence assignment and idempotency in one write query.

- `GET /api/v1/social`: own counts, top-five online friends, 50 most recent conversations and unread badges.
- `GET /api/v1/social/players?kind=friends|followers|following|search|blocked&q=prefix&cursor=username`: own relationship lists or username-prefix search; 50 results with an optional next cursor. Searches require at least three valid username characters.
- `POST /api/v1/social/players/:id/follow` / `block`: `{ "enabled": true|false }`, always acts as the authenticated account.
- `POST /api/v1/social/presence`: `{ "device_id": "32 hex characters", "online": true|false, "activity": "lobby"|"playing"|"" }`. Online status is visible only to unblocked mutual friends. A 30-second native heartbeat creates a 90-second lease; suspended/logout devices go offline independently, without hiding another active device.
- `GET /api/v1/social/conversations/:id`: last 50 messages in ascending sequence order. `before=sequence` loads older history; `after=sequence` fetches incremental messages. `has_more` supports paging without skipping messages.
- `POST /api/v1/social/conversations/:id/messages`: `{ "request_id": "32 hex characters", "text": "…" }`, 1–500 characters, at most 2000 UTF-8 bytes. Messages are rendered as plain text.
- `POST /api/v1/social/conversations/:id/read`: `{ "seq": number }`, monotonic read cursor bounded by confirmed conversation sequence.

All routes require JWT authentication and social limits apply per authenticated account. The native client polls an open conversation every 2.5 seconds; inbox/presence refresh runs every 30 seconds while the app is active. This is HTTP polling, not WebSockets. The server is authoritative for relationships, message history, unread/read state and presence expiry. Direct messages are access-controlled server records, not end-to-end encrypted. Closing a chat stops its polling. Logout/account changes clear all in-memory conversations and pending send intents. A network send retry preserves its ID while that game session remains open; committed history survives API/game restarts. UI resize preserves the selected conversation and draft, and unchanged polls do not rebuild message bubbles or disturb scroll position.

Run `FALKORDB_TEST_URL=redis://127.0.0.1:6379 go test -race ./...` for graph/API tests and `python3 tools/test_social.py --godot /path/to/godot --capture` for real native integration. The latter creates a disposable graph, avatar directory and accounts, simulates a lost successful send response, checks replies, follows, blocks, unread/read, resize and restart, and then deletes its fixtures. Native sample screenshots are `previews/social-online-friends-20-9.png`, `social-chat-20-9.png` and `social-followers-20-9.png`.

## Hosted release (November 10, 2026)

The game API and FalkorDB are deployed on the VPS at **https://api.remineph.online**. See [the deployment guide](../docs/vps-deployment.md). The development computer is no longer the live writer. The standalone signed APK connects to this API; no Firebase integration is required. Background push when the app is closed is not implemented.

New account endpoints: `GET /api/v1/account/security`, `POST /api/v1/account/recovery-codes` with the current password, `POST /api/v1/account/password`, and public `POST /api/v1/auth/recover` with a one-time recovery code. Recovery codes are displayed once and stored only as SHA-256 digests. Password changes/recovery revoke refresh sessions and existing access JWTs.

`POST /api/v1/reports` accepts a player/photo/received-message report. The server verifies the target, captures evidence, and sends it to the admin Reports queue. Reports have immutable request IDs and a ten-per-day cap. Reported normalized photos are retained privately for moderators even after profile removal.

`GET /api/v1/social/events` is an authenticated, bounded eight-second long poll with a persistent Redis Stream cursor. It carries message, relationship, challenge and ephemeral typing events; message bodies remain behind conversation authorization. `POST /api/v1/social/conversations/:id/typing` is restricted to mutual friends. The native client shows in-game notifications and retains slower polling as a reconciliation fallback.

Friend challenges: `GET/POST /api/v1/challenges` and `POST /api/v1/challenges/:id` with accept/decline/cancel. Up to five invitations per day; invitations expire after 24 hours and accepted challenges run for 24 hours. Participants use the same chart revision and difficulty; best server-verified score wins, with combo breaking ties. Runs must start after acceptance and finish before expiry. Results commit in the same graph transaction as verified progression. There are no challenge currency rewards or additional entry fees.

### Registration agreement

New accounts must submit `accept_policies: true`, `terms_version: "2026-11-11"`
and `privacy_version: "2026-11-11"` alongside username/password. Missing, declined
or outdated versions return `400 policy_agreement_required` before account
creation. Existing login/refresh requests need no new fields. FalkorDB stores
`terms_version`, `privacy_version` and server-generated `legal_accepted_at` on the
User node atomically with creation; duplicate registration never rewrites it.
These audit properties are excluded from public user responses.

The canonical documents are `assets/legal/policies.json`, used by the native app
and Solid companion. Contact: winterape25@gmail.com. Keep the server's
`legalPolicyVersion` synchronized when publishing a new policy version; the Go
contract test checks this. Accepted text/version must not be silently rewritten
under an existing version. Registration starts unchecked; opening or closing a
policy does not opt the player in. The required agreement is separate from any
optional marketing or advertising permission.


## Current Elysium production deployment

The hosted API and `rescene-rhythm` Engine project now use Elysium mainnet (`99901`) exclusively. HYPE pays gas; STARL remains the gameplay/payment token. All eight current contracts, deployment receipts, stock/allocation settings and registered chart counts are listed in [the mainnet manifest](../contracts/deployments/elysium-mainnet.json). Older Arbitrum examples above describe the original test deployment.

Production `.env` has `LEADERBOARD_CHAIN_ID`, `STARLIGHT_CHAIN_ID` and `MARKETPLACE_CHAIN_ID` set to `99901`, with the new addresses and server-only Alchemy RPC URLs. Dedicated Engine credentials remain server-only. The legacy First Scene router defaults only on Arbitrum Sepolia, so it cannot leak into mainnet inventory reads. Admin session responses expose the configured network; explorer links are emitted only for known matching networks.

The test-player reset removed accounts, login sessions, scores, progress, wallet links and pending jobs after a cold backup. New players start fresh. Administration identities and content remain intact. The exact live image and before/after census are recorded in [the cutover report](../contracts/deployments/elysium-cutover.json). Live verification uses `PULSE_LIVE_READS=1`, `STARLIGHT_LIVE_TEST=true`, and `MARKETPLACE_LIVE_TEST=true` with only their read-only test names selected; never run testnet purchase smoke tests against mainnet.

### Active song catalog

The active native/web library contains 29 songs. BamBamBam, Love Frequency and
Higher (Music from THE SPECIALS) are retired soundtrack releases. The audio
indexer excludes soundtrack albums on regeneration; the song-set generator also
exports the web catalog. Missing membership in `song_sets.json` blocks new runs
and challenge invitations before energy is spent. Existing issued tickets and
historical records retain their original charts in `charts.json` (116 active
charts plus 12 archived soundtrack charts). The progression exporter preserves
archived entries when rebuilding current charts.
