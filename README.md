# RESCÉNE Rhythm

Godot 4.7 mobile rhythm game with a landscape splash, lobby, song library and playable rhythm stage.

The live game runs on **Elysium mainnet (99901), with HYPE for gas**. All 8 game contracts are deployed and connected through the hosted API. STARL remains the game currency. See [mainnet addresses and receipts](contracts/deployments/elysium-mainnet.json). The production Engine project permits Elysium only; Arbitrum Sepolia manifests are historical test deployments.

Open `project.godot` in Godot and press **F6** with `scenes/splash_screen.tscn` open, or **F5** to run the project. Desktop preview is **1600 × 720 (20:9)**; the design viewport is **2400 × 1080 (20:9)**. Mobile orientation is landscape. Stretch aspect is **keep**, so the splash and menu maintain the same wide framing when the window or device has another shape, with letterboxing rather than rearranging or stretching the UI. The Compatibility renderer keeps this 2D screen lightweight.

The splash fades in and accepts a tap, click, Enter, or Space. A brief pearl flash acknowledges the input. The extended artwork fills the fixed 20:9 game canvas. The members, title and start prompt stay centered. The title and start prompt are part of the supplied artwork.

The splash's **Next Scene** is assigned to `scenes/auth_screen.tscn`. Tap, click, Enter or Space to fade into login/registration, then enter the main menu after authenticating.

## Strict GDScript

Every GDScript warning is an error, including untyped/inferred declarations, unsafe calls/casts, discarded return values, missing awaits and shadowed names. These rules cover runtime code, regression tests and capture/export tools, with no directory exclusions or warning suppressions. Variables, constants, loop variables, parameters and returns use explicit types. Screens and gameplay components use named script classes; `GameServices` supplies typed autoload access. `StrictData` checks values arriving from JSON, ConfigFile and heterogeneous dictionaries before passing them into typed APIs.

Run the compiler gate before shipping changes:

```sh
python3 tools/check_gdscript.py --godot /path/to/godot
```

It imports the project, verifies every warning remains set to Error, compiles all game/test/tool scripts, and fails on Godot error or warning output even when the engine exits with status zero. Rebuilding the song catalog preserves its named script type.

## Accounts and backend

The Go Fiber backend uses **FalkorDB** for accounts and JWT bearer authentication. Start it from `backend/` with `docker compose up -d --wait` followed by `./run.sh`, then run the Godot project. The launcher loads the server-only `.env`. The native login and registration screen matches the lavender/pearl lobby and supports show/hide password, validation, loading and error states. Successful registration logs in immediately; Profile shows the account username, server-managed wallet and **Log Out**.

Login persists for **30 days** through a server-managed refresh session. Every password login issues new credentials, and returning to the game or renewing access rotates the refresh token and starts a fresh 30-day window. The one-hour access JWT refreshes automatically in the background and before protected requests, including after the app has been closed longer than an hour. Desktop and Android builds atomically save access/refresh credentials in an API-specific local JSON text file (`user://auth_token_<API-hash>.txt`); no password is saved. Linux/Android files use owner-only permissions. Refresh tokens are stored as SHA-256 digests in FalkorDB. Logout removes local credentials and revokes the server refresh session when reachable. Network outages preserve saved login for retry. Existing valid JWT-only files upgrade automatically; an already-expired old JWT needs one password login to establish the new session. Local personal bests are separated by account. Validated online clears update account progression and cloud personal bests in FalkorDB. Song/difficulty leaderboards include Top 25, Near Me, your rank, and public player profiles. Android debug builds default to `http://10.0.2.2:8080` for the emulator. Configure `rescene/api/base_url` in Project Settings for a device or deployed server; release requires HTTPS. The Android preset enables Internet permission. See [backend/README.md](backend/README.md) for setup, environment variables, API endpoints, physical-device testing and security/deployment details.

## Progression

**Missions** opens Your Journey. **Collection / Cards** opens its Unlocks tab. **Daily Gifts** opens a seven-day login reward calendar. The lobby displays the account's actual level, XP bar, equipped title/frame and wallet Starlight balance. Refresh reloads from the server; daily progress refreshes after midnight UTC. Account progression survives game and API restarts.

Daily Gifts grants one manually claimed reward per server UTC day, resetting at **00:00 UTC / 08:00 Manila**. The seven rewards (XP / Starlight) are **50/30, 60/40, 75/50, 90/60, 100/75, 125/100, 200/200**. A complete cycle earns 700 XP and 555 Starlight. Missing days preserves your calendar position; after claiming Day 7, a new cycle begins at the next daily reset. The calendar shows collected, today's and upcoming gifts, a server-synced reset countdown, confirmation and level/cosmetic unlocks. Claims require a connection and are saved atomically in FalkorDB; a repeated request recovers the receipt without another payout. Login rewards do not count as song clears or mission gameplay progress.

Clear a Free Play song with at least **50% accuracy** to earn XP and Starlight. Failed stages, test captures and runs without a server ticket award nothing. All songs and difficulties remain available; unlocks are cosmetic. Results show XP, Starlight, first-clear bonuses, level-ups and newly unlocked cosmetics.

- Clear XP: `80 + 25 × difficulty index + floor(score / 50,000)`; Easy/Normal/Hard/Ultra Hard use indices 0–3. The first clear of each song/difficulty adds **40 XP**.
- Starlight: `30 + 10 × difficulty index + floor(score / 100,000)`; first clear adds **20**. Earned rewards are transferred as STARL to the managed player wallet; players spend their actual wallet balance on member cards and Energy Drinks.
- The next level costs `200 + 100 × (current level − 1)` XP, up to level 100. Claimable mission XP also counts toward levels.
- Three daily missions: clear one song, clear three songs, and earn a combined 1,000,000 score. Replays count as separate clears. They reset at **00:00 UTC**, with stale-day and duplicate claims rejected.
- Five career missions: first clear, five clears, 90% accuracy, 100 combo, and a full combo. Career claims never reset.
- Titles: First Scene (default), Rising Star (level 2), Scene Maker (5), Scene Stealer (10), Perfect Harmony (full combo). Frames: Pearl (default), Rose Mist (3), Frost (7). Equip earned items in Unlocks; the header changes immediately.

The backend creates one active run ticket per account before the countdown. Tickets bind rewards to the actual chart and minimum elapsed song time; submitted judgment totals and score must match its embedded metadata. Completed tickets and claimed missions cannot award twice, including concurrent requests. A connection failure after a clear saves its result in an account/API-specific queue and retries during the next refresh/login, up to the ticket's two-hour validity. Starting another rewarded run waits for this queue to sync. New online runs bind a versioned input replay to the server ticket and exact chart revision. The Go backend replays presses, releases and movements through the same fixed-step timing rules as the game, then verifies score, judgments, life and maximum combo before committing rewards.

Run `python3 tools/test_progression.py --godot /path/to/godot` against a local FalkorDB for a disposable full-stack test. Add `--capture` to render journey/results previews. It verifies real rewards, mission claims, equipping, retry/failure behavior, authoritative energy spending and recovery, restart persistence, and a dropped connection followed by queued sync. The driver deletes only its own random test graph.

## Cloud records and leaderboards

Song selection has a **Rankings** button beside Preview. Each song/difficulty/chart revision has a Top 25 and Near Me view, with your row highlighted even when outside the top list. Entries show score, accuracy and max combo. Equal scores use higher combo, then the earliest achievement, then player ID for deterministic placement. Tap a row to open that player's full public profile and cloud records; private account controls and wallet details are absent.

Cloud bests sync on login/menu entry and after a validated online Free Play clear. New processes/devices restore them through the account API; a small API/account-specific cache keeps previously fetched records visible during outages. Existing local and offline records stay on the device and are never silently uploaded as ranked results. Profile Records labels the winning best as CLOUD or DEVICE; selecting a record opens that chart's ranking. Failed, paused and old metadata-only runs do not enter verified rankings. Paused runs can still earn progression after input validation. Completing the same ticket twice cannot create duplicate bests or duplicate progression rewards: the score upsert and progression receipt commit in one FalkorDB compare-and-set query.

The current client sends a chart hash and `replay_version: 3` when starting a run. It records quantized input times/lanes and retains that replay in the durable pending-completion queue. A server judge uses the authoritative embedded notes, hold checkpoints and curved paths to calculate the result at 120 Hz. Impossible pointer actions, bad ordering, wrong-run/wrong-chart evidence, false score/combo/judgment claims, game-over replays, oversized payloads and early completion are rejected. The game and server share deterministic timing, release-grace and keyboard-handoff rules; high-frequency mouse movements are sampled consistently before both judging and recording.

Only uninterrupted, replay-validated clears appear in rankings. Pausing during countdown is harmless; pausing active gameplay preserves casual progression but marks that run unranked. New tickets require replay version 3. Older in-flight tickets can finish as unranked progression, while legacy bests remain stored but are excluded from verified cloud records/rankings until a new validated clear replaces them. No accounts, XP or device records are reset. Input validation checks whether reported play is possible under the rules; it cannot attest that a human generated the inputs or eliminate automated input bots.

Run `python3 tools/test_replay.py --godot /path/to/godot` for all-chart Godot/Go replay parity, including 30/60/240 Hz render cadence, timing-window boundaries, stationary slides, pauses and keyboard handoffs. Backend validation limits a replay to 24,000 events and the request to 1 MiB, with at most two concurrent validators per API process. Other API bodies retain their 4 KiB limit.

`FALKORDB_TEST_URL=redis://127.0.0.1:6379 go test -race ./...` in `backend/` checks score ordering, improvements, concurrent/duplicate submissions, rejected evidence, revision separation, nearby ranking outside Top 25, persistence and public profile privacy. `python3 tools/test_progression.py --godot /path/to/godot --capture` also exercises the actual game ranking button, difficulty races, public profile navigation, cloud restore after removing local bests, and interrupted completion sync. Both use disposable graphs and do not touch real users or Engine wallets.

## On-chain leaderboard contract

[`contracts/src/ResceneLeaderboard.sol`](contracts/src/ResceneLeaderboard.sol) adds a standalone EVM leaderboard with separate song/difficulty/revision boards, account personal bests, a sorted Top 25, duplicate-run protection, and role-restricted publication by the backend. It uses the existing score/combo/time/player-ID ordering and keeps updates bounded to 25 entries. The publisher remains responsible for gameplay verification; the contract enforces publication and ranking rules.

Foundry tests, deployment/registration scripts, and a generated manifest for all 128 chart revisions are included. See [`contracts/README.md`](contracts/README.md) for setup, trust assumptions, deployment, and backend integration requirements. The contract is deployed for `rescene-rhythm` on Arbitrum Sepolia (421614) at `0xb5cc39d72012345198bf17c56c1bbb4adad60933`; [deployment addresses and receipts](contracts/deployments/arbitrum-sepolia.json) also include the thirdweb marketplace and ERC-1155 collection. The Go API automatically mirrors replay-verified personal-best improvements through Engine using an atomic FalkorDB outbox. Publication survives restarts, retries ambiguous responses without duplicate writes, verifies chain receipts, and repairs reorganized transactions. The leaderboard displays each player’s publication status. Live full ranks and Near Me continue to use FalkorDB. See [backend configuration](backend/README.md#automatic-on-chain-score-publication).

## Player profile

The avatar in the lobby opens a full-screen **Player Profile**, with Info, Records, Unlocks and Wallet navigation, plus a selectable RESCÉNE portrait showcase. Info displays account level, XP, song clears, best accuracy, best combo and full combos. Records merges this account's restored cloud bests with existing device records, explicitly labeled CLOUD or DEVICE; Unlocks equips earned titles and frames through the progression API. Wallet shows the account address with **Copy Address**, username, player ID and join date. **Log Out** returns to login. Back/Escape restores the originating lobby or song selection, including song, search and difficulty. The profile has no wallet setup status, refresh button or automatic wallet polling.

## Player wallets

With `ENGINE_API_KEY` and `ENGINE_PROJECT_ID` configured on the Go backend, every registered account receives a server-managed Engine wallet. Existing accounts are backfilled automatically. Engine generates and encrypts the private key; FalkorDB stores only the public wallet ID/address and provisioning state. The game never receives the Engine API key or wallet private key.

Wallet creation is asynchronous, with persisted leases and automatic retry/recovery; re-login, restart and refresh retain the same ready wallet. A temporary Engine failure does not block gameplay. This integration creates wallets only; game rewards remain game progression rather than on-chain tokens. See the backend README for API routes and retry/idempotency limits.

`python3 tools/test_wallet.py --godot /path/to/godot --capture` exercises registration, provisioning, profile display and identity continuity using a local HTTPS Engine fixture. It also verifies full-profile navigation, clipboard copying, records, locked cosmetics, resize, library return state and logout. It does not create wallets in the real Engine project.

Splash music: `assets/audio/with.mp3` starts automatically at **0:49**, softly fades in, and loops back to **0:49** when the track ends. The Music node controls its volume (default −8 dB). The root's **Music Start Seconds** property controls both the opening position and loop point. Music fades out with the splash when opening an assigned next scene and stops when the splash is removed.

The **Particles** node adds floating pearl sparkles, lavender bokeh, occasional shooting stars and a sparkle burst on start. Its **Sparkle Count** and **Intensity** properties control density and brightness. Effects scale with the viewport and fade away over the faces, title and start prompt. They use native 2D drawing and a small generated glow texture with the mobile Compatibility renderer.

Artwork: `assets/art/rescene-rhythm-splash-wide.png`, extended from the original `assets/art/rescene-rhythm-splash.png`. Created from the supplied group photo and RESCÉNE wordmark reference. The original is retained for reference.

## Main menu

The lobby follows the reference's layout with a pearl, ice-blue and lavender visual style: profile and resource counters at the top, shortcuts and featured scene on the left, five member portraits on the right, and navigation plus a large Play button below. `scripts/main_menu.gd` builds native Godot controls over `assets/art/rescene-main-menu.png`. Both scenes use the same fixed 20:9 canvas, so their framing stays consistent across screen sizes. The art and imagegen prompt are stored in `assets/art/`.

Working interactions:

- **Play / Songs:** opens the full song-selection screen, retaining the lobby's background, particles, profile and top HUD.
- **Profile:** view the signed-in username and log out. Level, XP, title and frame appear in the header.
- **Settings:** adjust menu music volume and toggle menu particles. Both persist locally in `user://lobby.cfg`.
- **Members:** open portrait previews and select a member in the rail.
- **Energy:** song attempts cost 1 energy, including retries. The resource button shows the balance and recovery countdown.
- **Records:** view local personal bests per song and difficulty.
- **Daily Gifts:** claim today's XP/Starlight from the seven-day calendar. **Missions:** complete gameplay challenges and claim account XP/Starlight. **Collection / Cards:** view and equip cosmetic unlocks.
- **Other shortcuts:** Shop sells member cards and Energy Drinks for STARL. Collection shows owned cards and lets you equip a favorite; packs and upgrades remain previews.

The menu plays `assets/audio/loveattack-instrumental.mp3` (RESCENE – LOVE ATTACK Instrumental) from the beginning and loops the full track. WITH remains the splash music. Opening song selection pauses the instrumental background for the entire view; only the focused library track plays. The instrumental resumes when returning Home. The music volume setting applies to both players. Font licenses are included in `assets/fonts/`. Icons are native SVG UI assets in `assets/ui/`.

## Song selection

The fixed 20:9 view uses large selected-song artwork and details on the left, with search, sorting, **Easy / Normal / Hard / Ultra Hard** tabs and a scrollable song list on the right. **Start** loads the selected song and difficulty into gameplay. Personal bests show real completed-stage scores saved on this device.

The library has **32 original entries**, with duplicate titles and alternate Japanese, English, sped-up, acoustic and special-video recordings excluded. Covers, artists, albums and durations come from the supplied MP3 metadata. The untagged splash copy of WITH and the second Heart Drop copy are also excluded from the list. Source audio stays in the folder; LOVE ATTACK Instrumental is used only as the main-menu soundtrack. Embedded covers are extracted into `assets/art/covers/`. Files without covers use the existing group artwork. The catalog builder applies these filters whenever it runs, so rebuilding does not restore unwanted versions.

Tracks use **short versions: the first half of the full audio**, starting at 0:00. The playback cutoff is half the decoded stream's exact length; displayed durations show the short version, and catalog metadata retains both full and playable durations. There is no automatic restart or lobby soundtrack after the cutoff. The Preview button can restart or stop the focused track.

`scripts/kinetic_song_scroll.gd` handles touch swipes, mouse dragging, wheel scrolling and trackpad gestures with momentum and deceleration. Rows center where possible, with no artificial top or bottom padding: the first row starts at the top and the last row ends at the bottom. Explicit taps retain the requested song even when its centered position is clamped at an edge. Audio stops while the list moves and switches to the focused song after it settles. Tapping another row glides it into focus; keyboard focus also centers its row where possible. Drag gestures are consumed before row buttons, so a swipe cannot accidentally trigger a song tap.

The custom scroller also consumes touch-generated mouse events, preventing the native ScrollContainer drag handler from competing with it when a gesture starts between rows or after a short result list. Forwarded/emulated mouse-wheel events use the same momentum controller. Native scrollbar dragging remains available and snapping waits for the thumb to be released.

Scroll regressions can be run with the Godot executable using `--headless --path . --script res://tests/scroll_input_regression.gd` and `--headless --path . --script res://tests/scroll_boundary_regression.gd`. These reproduce touch/mouse emulation conflicts, swipes starting between rows, wheel recovery at the first song, both end boundaries, direction reversals and a lost release.

The sort dropdown uses the shared `assets/ui/lobby_controls.tres` theme: lavender button states, a custom chevron, a dark rounded popup, pearl typography and selection marks. The lobby scene supplies this theme to dropdowns and popup menus throughout its child screens.

The search placeholder is **Search song**. Search matches title, artist and album; sorting supports title in both directions, album and duration. Empty results stop song playback and disable Start and Preview. Difficulty changes retain the current audio, with all four difficulty options carried to Start. Back or Escape returns Home.

After adding more MP3s, run `python3 tools/build_song_catalog.py`, then let Godot import the new files. This requires `ffprobe` and `ffmpeg`. The generated `scripts/song_catalog.gd` stores file paths and metadata, and audio is loaded only for the selected preview. Use Godot's **Export all resources in the project** setting when packaging, so all dynamically loaded library tracks and covers are included.

## Gameplay

`tools/capture_momentum.gd` captures actual chart input at 1×, 2×, 3× and 5× into `previews/momentum-<tier>x-20-9.png`.

The native 2D stage keeps the same 20:9 framing, group background and lavender/pearl palette. A five-lane perspective highway brings notes toward the illuminated hit line. Round noteheads match the catchers' ellipse and size at the hit line; their edges and catcher rings use pixel-smoothed shader drawing. Each note receives a random color from seven muted shades: lavender, periwinkle, mist blue, sea glass, dusty rose, orchid and silver lilac. Notehead colors stay fixed through the approach and collection, and retries assign fresh colors; curved ribbon bodies have their own flowing palette. Slide ribbons have visible turning points. Hit flashes, rings and sparks respond to judgments. The HUD shows score, accuracy, combo, life, selected song/difficulty and song progress.

- **Touch:** tap notes as they reach the hit line. Keep a finger down for holds; move it sideways along the hit line to follow a curved ribbon. Independent fingers support chords.
- **Mouse:** click, hold and drag along the hit line to trace ribbons. Use keyboard or multitouch for chords.
- **Keyboard:** **D / F / Space / J / K** map to the five lanes. For slides, hand off between the keys under the moving head; overlapping adjacent keys is allowed.
- **Pause:** use the top-right pause button or **Escape**. Resume has a ready countdown; Retry restarts the song and chart. Losing focus or backgrounding the app also pauses the stage.
- **Calibration:** the pause panel's timing offset adjusts judgments by ±150 ms and persists in `user://lobby.cfg`.
- **Finish:** music stops at exactly half the decoded recording. A full-screen results page replaces the gameplay view, with large album art, an animated score reveal, accuracy, maximum combo, stage progress and a judgment breakdown. Failed runs show **GAME OVER** with a rose accent and **Try Again**; successful runs show **STAGE CLEAR**, a rank medallion and first-clear/personal-best badges when earned. Retry restores the highway and countdown; Song Selection returns to the same library selection and resumes its preview. **Enter** retries when no results button has focus; focused buttons retain normal keyboard activation. **Escape** returns to songs. Failed-run accuracy and judgments count only attempted notes, excluding future notes the player never reached.

Perfect/Great/Good timing windows are ±45/90/150 ms. Late notes and broken ribbons reset combo and reduce life; Free Play ends when life runs out. Tap heads and ribbon checkpoints share a normalized maximum score of 1,000,000. Momentum multiplies judgment points by **2× at 20 combo**, **3× at 40**, and **5× at 60**, including the milestone judgment. Any miss or broken ribbon resets the multiplier to 1×; points already earned stay earned. The three-segment bar sits below HP and shows progress to the next tier. Rails, road surface and feathered side lighting shift through ice blue, violet and rose as momentum rises. The atmosphere eases between tiers, freezes on pause and clears on retry. There are no extra full-screen shader passes or particle emitters for momentum.

Momentum score is the sum of integer judgment weights (10/8/5), each multiplied by its current combo tier, normalized against that chart's all-perfect uninterrupted momentum budget. Thus all-perfect full combos still score exactly 1,000,000, while dropping a streak reduces subsequent note contributions. Accuracy, grades and the 50% clear-reward requirement use unboosted judgment quality. Replay version 3 independently verifies bonus scoring in Go. The scoring ID is included in chart revision hashes so old and new scores never share a ranking. Old device records stay on disk but are excluded from momentum bests; accounts, XP and unlocks are retained. Completed Free Play results update `user://rhythm_records.cfg` only when the score improves. Failed stages do not overwrite personal bests.

Pressed catchers light up with a soft elliptical glow, including empty taps; there are no lane-wide light blocks or polygon beams. Successful heads and ribbon tails launch note-colored firework bursts with ballistic sparks, curved fading trails, twinkling stars and an expanding ground ripple. Sustain checkpoints use smaller sprays. Bursts use additive light, freeze during pause, clear on retry and have a fixed overlap cap for dense charts. `scripts/rhythm_hit_effects.gd` draws the effects above the notes. For an animation review, `godot --path . --script res://tools/capture_hit_effects.gd` writes 30 frames into `/tmp/rescene-hit-frames/` and a still into `previews/hit-fireworks-20-9.png`.

Every **10 combo** creates a quick pillar of pearl, lavender and ice-blue light on the triggering catcher. Fourteen distinct side streams have bright spines, soft halos and varied rising tips. The column, grounding ellipse and rising glints fade within 0.52 seconds, behind the notes and HUD. Three reusable shader sprites bound the overlap; pillars freeze during pause and reset on retry. A broken combo can earn milestones again. `tools/capture_combo_pillars.gd` captures the real first milestone into `previews/combo-pillar-20-9.png`.

Collected holds and curved ribbons have a fast-spinning pearl/lavender vortex on the road beneath the head, with two rising orbital arcs. Each vortex follows its ribbon, fades within 0.12 seconds after release or a broken trace, freezes during pause and clears on retry. Empty presses and tap notes do not create vortices. A fixed pool of ten small shader sprites matches the judge's maximum simultaneous pointers. `tools/capture_sustain_vortex.gd` writes a still to `previews/sustain-vortex-20-9.png` and 30 native animation frames to `/tmp/rescene-vortex-frames/`.

Curved ribbons are approximately twice as wide as straight holds, reaching 192 pixels across at the catcher in the 2400-pixel design view. A smooth lavender/rose/periwinkle/ice-blue gradient flows along and across each curved ribbon with a gentle brightness pulse. The color animation uses the gameplay visual clock, so pause freezes it. Feathered mesh edges keep the wider curves smooth; the tracing path and hit tolerance stay the same.

There are **128 stored charts** for the 32 library tracks and four difficulties. They are generated offline from the supplied audio's beats/onsets, then loaded deterministically. They are playable starting charts and need musical review and hand tuning before release. The beat/bar data layout follows the author's previous rhythm project, extended with curved paths; see `assets/beatmaps/README.md` for provenance, editing, packing and regeneration instructions.

Gameplay regression commands (replace `godot` with your Godot executable):

```sh
godot --headless --path . --script res://tests/rhythm_core_regression.gd
godot --headless --path . --script res://tests/rhythm_stage_regression.gd
godot --headless --path . --script res://tests/rhythm_ribbon_regression.gd
godot --headless --path . --script res://tests/combo_effects_regression.gd
```

Core checks validate all 128 charts, legacy timing conversion, note windows, holds, required curve tracing and representative full-chart completions. The stage check exercises actual Start/input/pause/retry/results/library flow, including simultaneous touch notes, touch-to-mouse emulation, a curved drag and regrabbing a paused ribbon with a different finger index. With a display, `godot --path . --script res://tools/capture_gameplay.gd` writes gameplay, pause and results screenshots into `previews/`; its simulated review play does not save records.

## Energy

Energy is owned by the Go API and persisted with progression in FalkorDB. New and existing accounts start at **15/15** on their first energy initialization. Each accepted song attempt costs **1 energy**, including retries; leaving or failing does not refund it. Run creation and spending commit in one compare-and-set write, so concurrent starts cannot overspend. Start request IDs recover a lost response without another charge, including after a client/API restart. The game requires server approval before countdown and has no alternate free-play mode.

Recover **1 energy every 30 minutes**, up to 15. Partial recovery time survives additional spending; recovery catches up while offline, stops at full, and never banks excess time. The server supplies the balance, next recovery and full-recovery times. The lobby/song HUD displays the authoritative balance with a monotonic countdown and refreshes when recovery is due or the app regains focus. Expiring the client timer only requests a fresh server balance. Client clocks and local files cannot grant energy.

`python3 tools/test_progression.py --godot /path/to/godot --capture` also covers the real energy HUD, cost on retry, depletion, rejected-start screen and client-countdown tampering. Previews include `previews/energy-20-9.png` and `previews/energy-empty-20-9.png`. Backend energy tests cover exact recovery boundaries, offline catch-up, partial intervals, caps, account isolation, persistence, concurrent starts and duplicate requests.

## Marketplace UI

The lobby **Shop** button opens a full marketplace destination beneath the existing player/resource HUD. The catalog contains five First Scene portrait cards, two card packs, three card-upgrade materials and two energy-drink products. Featured, Cards, Card packs, Upgrade items and Energy drinks filters, text search and ascending/descending Starlight price sorting are interactive. Item details show larger artwork, descriptions, planned contents and a quantity selector with a preview total.

Five First Scene member cards are real ERC-1155 items sold for 450 STARL each, alongside the Energy Drink for 100 STARL. Packs, upgrade materials and the drink bundle remain previews. Browsing does not change balances or inventory. The authenticated storefront now reads `/api/v1/marketplace`, which verifies the configured thirdweb MarketplaceV3 through Engine and reads its direct-listing count. The deployed Arbitrum Sepolia marketplace is `0xa3d343ea5bb4c2242b5214588886e9d3c52e0c57`; its collection is `0xa468d30613fe78692f857f55326a069b157c8b56`. Reads are cached briefly and failures are never presented as zero stock. Energy Drink maps to collection token ID 0 and direct listing ID 0; First Scene cards map to token IDs and listing IDs 1–5 (Woni, Liv, Minami, May, Zena). Packs, upgrades and the drink bundle remain unlisted.

Energy Drink and member card checkout are enabled. The backend validates the authenticated player, fresh listing, price, stock and STARL balance. It confirms the atomic on-chain payment and delivery before reporting success; clients cannot grant items. Card packs and pack opening remain unavailable. Pack drop rates are deliberately unspecified until the actual purchase system is defined. See the [Engine Marketplace V3 API reference](https://engine.fluentxverse.com/reference) for the listing, approval, purchase and transaction-confirmation workflow.

The grid reuses the song list's gesture controller for mouse, touch, wheel and momentum scrolling, with per-cell tap picking so swipes and gutters do not open items. Back closes item details first; a second Back returns to the lobby. Category, query, sorting and selected-item quantity survive menu rebuilds. Product art uses the existing group portraits, lightweight foil-pack/material SVGs and the project's supplied lavender energy-bottle artwork, copied into `assets/art/items/energy-drink.png` with a 512-pixel import limit.

Validation: `godot --headless --path . --script res://tests/marketplace_regression.gd`. Native previews: `godot --path . --script res://tools/capture_marketplace.gd` writes featured, cards, energy and item-detail images into `previews/marketplace-*.png`.

## Starlight token rewards

**RESCENE Starlight (STARL)** is deployed on **Arbitrum Sepolia (421614)** at `0xea99194cb96917672973eb55350c667c68c04c20`, with 18 decimals and an initial supply of 100,000,000 sent to the project treasury. The Engine ERC-20 template retains owner-controlled minting and holder burning; gameplay does not mint tokens.

Verified clear rewards, mission claims and daily gifts move existing STARL from the treasury to the player's Engine-managed wallet through `StarlightRewards` at `0xb2fd98c13d2c11cc79315706554eacb185bb8743`. Each entitlement is queued atomically with progression in FalkorDB; its on-chain reward ID prevents duplicate transfers even if Engine retries a broadcast. Wallet provisioning delays, outages and insufficient treasury funds leave the reward queued. Existing server-recorded earnings are converted once per token.

The HUD shows the actual ERC-20 wallet balance, preserving decimal amounts and displaying an ellipsis while loading. Pending rewards appear in the balance tooltip and refresh automatically. `progression.starlight` remains the lifetime earned ledger; purchases must use actual token balance/allowance instead. No transfer amount or recipient is accepted from the game client. Energy Drink and member card checkout use separate fixed-price routers; packs and upgrades remain previews. Deployment receipts and the public ABI are in `contracts/deployments/`; see `backend/README.md` for server configuration.

## Energy Drink checkout and Inventory

Open **Shop → Energy drinks → Energy Drink**, choose 1–10, then **Buy → Confirm**. Each drink costs **100 STARL**. The server validates the order and pays testnet gas for required managed-wallet approvals; the player pays STARL from their own wallet. Payment and ERC-1155 delivery occur atomically through MarketplaceV3, and the order stays Processing until canonical receipts confirm both. Closing/restarting the game does not abandon a saved purchase.

Open **Inventory** from the lobby footer or shop. It reads confirmed ERC-1155 ownership. **Use Energy Drink → Confirm** burns one item and restores up to **5 energy**, capped at 15. Full energy rejects use and keeps the drink. The backend also checks again before submitting a burn if energy recovered while waiting. A natural recovery timer is preserved unless the refill reaches full. The burn and energy grant each happen at most once, including concurrent clicks, lost HTTP replies and API restarts.

The existing collection is `0xa468d30613fe78692f857f55326a069b157c8b56`; Energy Drink is **token ID 0**, **listing ID 0**, initial stock **10,000**. `EnergyDrinkShop` is `0x5ace042c739c4b49fef8774a7eb2c54136ef55af` on Arbitrum Sepolia. Its immutable bindings and fixed price prevent a backend quote from accidentally charging for another asset. Existing accounts/balances were not used for the live test: a separate test wallet paid 100 STARL, received and burned one drink, and restored energy from 9 to 14. Receipts are in `contracts/deployments/energy-shop-live-verification.json`.

Validation includes `go test -race ./...` with disposable FalkorDB graphs, `forge test` in `contracts`, `tools/test_commerce.py --godot /path/to/godot`, `tests/inventory_regression.gd`, and strict explicit-type GDScript checks. The client regression uses a mock local API and makes no chain writes.

## First Scene member cards

Open **Cards** or **Collection** to browse Woni, Liv, Minami, May and Zena. Each SR card belongs to the First Scene series and costs **450 STARL** in **Shop → Cards**. Token/listing IDs are 1–5 in the existing ERC-1155 collection. Each listing started with 10,000 units; this is treasury stock, not a promise that the collection admin can never mint more.

After confirmed delivery, open the card and choose **Equip Favorite**. The server checks the authenticated player's confirmed on-chain ownership and persists the preference in FalkorDB. Your favorite appears on your profile (including public profiles) and next to your score during a song. Cards are cosmetic: score, energy, XP and anti-cheat rules are unchanged. **Remove Favorite** clears the preference without burning or transferring a card. An inventory refresh hides a favorite if its card leaves the player's wallet.

`MemberCardShop` is deployed at `0xa8e3dd8cf231da2bf318e0e6c3486c11b6d1acb7` on Arbitrum Sepolia. Engine automatically signs the exact STARL approval with the player's server-managed wallet, then treasury executes the atomic payment/delivery. No NFT burn approval is requested for cards. Duplicate requests recover the original order, and the same request ID cannot switch member or quantity. [Public deployment records](contracts/deployments/arbitrum-sepolia.json) include the addresses and metadata.

Native UI checks: `tests/collection_regression.gd`; existing inventory and commerce regression tests still cover drinks. `backend/cards_test.go` checks ownership/equipment/receipt validation and lost-response recovery. The opt-in live test uses an isolated test account and 450 treasury testnet STARL; see `backend/README.md`.

## Player photos

Click the **+** on your profile avatar to upload a JPG/PNG. The **Gallery** tab supports five photos in addition to the avatar, with Replace/Remove controls and a full-size viewer. Photos persist on the server and are visible on player profiles. See [upload limits, storage and API setup](backend/README.md#player-avatars-and-gallery).

## Friends and messages

The right lobby rail shows up to five online friends with their uploaded avatars and unread badges. Tap an avatar to chat, **+** to find players, or the header envelope to open Messages. Follow each other to become friends. The social screen includes Followers, Following, private message history and Blocked lists; profiles also show social counts and follow/message controls. See [social API and presence behavior](backend/README.md#social-graph-friends-and-direct-chat).

## Web companion

The SolidJS 2 companion is live at https://rhythm.remineph.online and linked from https://remineph.online. It shares player accounts, marketplace, cards, decks, rewards, profiles and social APIs with Android. Gameplay and song playback stay in the APK. See [webapp/README.md](webapp/README.md) for commands, session security, deployment and browser/live verification.

Android v0.1.1 uses a dedicated 1600 × 720 gameplay viewport (20:9), retaining the 2400 × 1080 coordinate space and full-resolution menus. The mobile path targets 60 FPS and bounds fireworks to eight simultaneous bursts, with 24 sparks for perfect hits. Desktop rendering is unchanged. Native touch/curve regression can exercise the same path with `--script res://tests/rhythm_stage_regression.gd -- --mobile-rendering`.

Song outros fade smoothly over the final 3 seconds of the existing playable duration. The fade follows the audio clock, freezes while paused, and resets on retry; chart timing and the half-song cutoff are unchanged.

Android releases use a project-specific Godot template with unused engine
features removed, ARM64-only phone packaging, and only referenced audio tracks.
The public download streams directly from Cloudflare R2, so APK downloads use no
VPS transfer bandwidth. See [Android build and publishing](infra/android/README.md).

Android v0.1.6+ can check, download/resume, verify and install updates from within
the game. Use **Settings → Check for updates**, or the button on the login screen.
Android may ask to allow installations from RESCÉNE Rhythm and confirm Update.
The menu soundtrack is now LOVE ATTACK Instrumental.
