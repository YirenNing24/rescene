# REMINE Operations

Deployed at **https://admin.remineph.online** on Cloudflare Workers. The application uses SolidJS **2.0.0-rc.21**, `@solidjs/web` and the Solid 2 compiler; there is no React frontend.

## Owner access

Initial Owner: **paulanthonyarriola@gmail.com**. The private setup instructions and access key are in `../backend/data/admin-owner-access.txt` (mode 0600, excluded from version control). Sign in, click **Get setup key**, add REMINE to a TOTP authenticator, then enter the six-digit code. The Owner's authenticator is intentionally left for the Owner to enroll. Do not publish or upload the setup file.

Every administrator needs an access key and authenticator verification. Keys are bcrypt hashed; TOTP secrets are encrypted at rest. Gateway cookies are Secure/HttpOnly/SameSite Strict. The Worker validates the gateway session; the backend independently verifies a short-lived, nonce-bound HMAC over the actor, method, URL and body. Roles and revocation are checked in the database on every request. Player tokens do not grant administrator access.

Six roles: Owner, Operations, Economy, Content, Support, Analyst. Inviting an administrator displays their new key once. Editing an existing administrator does not replace their key. An Analyst cannot mutate records. The initial Owner cannot accidentally revoke or demote their own account.

Cloudflare's current OAuth credentials could deploy Workers but returned 403 for Access organization/application writes and DNS writes. Therefore this deployment uses dedicated app authentication rather than claiming that Cloudflare Access email login is configured.

## Running and deploying

```sh
cd admin
npm ci
npm run check
npm run build
npm run deploy
```

Use `wrangler secret put ADMIN_GATEWAY_SECRET` to install the same server secret held in `backend/.env.admin`. Do not put secrets in Vite environment variables or public assets. Local `.dev.vars` is ignored and supplies the development gateway secret and the VPS API origin. Run `wrangler dev --port 8788` after building assets for a complete local proxy. `npm run dev` alone starts the UI without the authenticated Worker gateway.

```sh
# Production browser checks; these read the local deployment secret to issue
# short-lived test cookies in a disposable browser context.
ADMIN_TEST_ORIGIN=https://admin.remineph.online npm test
ADMIN_TEST_ORIGIN=https://admin.remineph.online npm run test:smoke
node scripts/api-smoke.mjs

cd ../backend
FALKORDB_TEST_URL=redis://127.0.0.1:6379 go test -race ./...
```

Backend tests use randomly named disposable graphs. Browser tests inspect real game data and validate login/MFA enforcement without enrolling or changing the Owner authenticator. They do not execute on-chain writes.

## VPS hosting

The Worker serves the UI globally and forwards signed admin requests to **https://api.remineph.online**, backed by the authoritative Go API and FalkorDB on the VPS. Origin routing is pinned in `wrangler.jsonc`; the retired desktop Quick Tunnel registration endpoint and KV override are removed. This computer can be switched off without interrupting the admin or game API.

The VPS runs the `remine` Compose project under `/opt/remine`, started at boot by `remine-api.service`. The API Worker injects an independent edge credential before forwarding through the existing named tunnel. The admin's separate HMAC, role, access-key and MFA checks remain enforced. See [the deployment guide](../docs/vps-deployment.md) for service and backup details.

The former desktop services `remine-game-api`, `remine-admin-origin` and `remine-admin-tunnel` remain stopped and disabled. The desktop tunnel launcher exits with a retirement notice instead of starting another origin. There is one authoritative VPS database; do not restore the old desktop snapshot over it.

## Operation semantics

No mint, STARL transfer, approval, listing write or PULSE launch was executed during implementation. An operator saves an immutable intent, validates/simulates it, then types `CONFIRM` before execution. The backend also re-simulates chain writes, restricts methods/targets, bounds quantities and allowances, persists intent before submission, uses stable Engine idempotency keys and verifies the returned transaction against the approved intent. RPC receipts and configured confirmations drive reconciliation. An ambiguous submission without a retained Engine ID is held for manual Engine reconciliation; it is never blindly resent with a new key.

Minting supports registered stock IDs 0–5 and 11–13, with quantities up to 10,000 per intent. CSV import validates up to 50 rows and creates individually reviewable intents. Reserved PULSE IDs and unique-card issuance cannot be minted through the stock endpoint. PULSE is deployed with an initial 50/member sale allocation. Admin generation rolls traits once when the intent is created; retries retain those traits. Admin issuance does not consume or replenish the initial allocation, and artwork reissues are allowed. Fixed router prices cannot be edited as catalog metadata.

Support actions enforce suspension, session revocation, upload/social restrictions, photo quarantine and score quarantine in the game backend. XP/energy support grants are bounded and idempotent. Quarantine affects off-chain visibility; it cannot erase already published contract records. Queue recovery preserves original intents and respects active leases.

Published settings apply five live flags within three seconds: maintenance, pause purchases, pause new runs, pause uploads and pause social writes. Other versioned documents are administrative records or release proposals; saving them does not silently modify compiled game rules, deploy contracts, change prices, deliver announcements to the game, or run backups.

See [the full implementation status](../docs/admin-implementation-status.md) for the accepted scope and remaining work.

For backend updates, follow [the VPS deployment guide](../docs/vps-deployment.md). Do not restart the former desktop API or rerun the cold database migration. Preserve the VPS environment files, FalkorDB storage, uploaded media and private backups. The media library is not a database backup service.
