# Hosted game API

The authoritative Fiber API and FalkorDB run on the existing VPS, with a dedicated Docker Compose project in `/opt/remine`. Public origin: **https://api.remineph.online**. The admin app at https://admin.remineph.online is pinned to this API in its Worker deployment configuration. The old desktop tunnel registration endpoint and KV routing override have been removed. Both continue working when the development computer is off.

A separate Cloudflare Worker serves the public API hostname. The existing named tunnel routes only `engine-api.fluentxverse.com/rescene/` to the private gateway on `127.0.0.1:8086`; its other services retain their original routes. The gateway checks a dedicated edge credential, removes the path prefix, and forwards to the API. Player rate limits use the verified edge IP. Admin requests still require their independent signed gateway proof and role/MFA checks. No database port is published.

`remine-api.service` starts the Compose services at boot. Containers have restart policies, health checks, bounded memory, rotated logs and persistent storage. The API runs without root on a read-only image; media and releases use separate mounts. Server-only Engine, JWT, admin and database credentials are not included in the game or frontend.

The cold migration preserved the original JWT key, accounts, sessions, wallets, progression, admin identities and media. The transferred RDB SHA-256 and graph node count matched before writes were enabled. Redis was bootstrapped from that snapshot before enabling AOF; a second restart confirmed persistence. Checkpoint and private transfer archives are under `backend/data/vps-deployment/`. The old local API and admin origin/tunnel services are disabled to prevent two writers.

Daily backups run at 02:00 Asia/Manila, with up to five minutes of scheduling jitter, retaining a week in `/opt/remine/backups/`. Backups contain private credentials and player data and are readable only by root. They are on the same VPS: an external backup destination and full disaster-recovery rehearsal remain outstanding.

For a code update, run the backend checks, build `backend/bin/rescene-api-vps` with `CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build`, stage with `tools/deploy_game_vps.mjs`, then run `docker compose up -d --wait api` from `/opt/remine`. Do not rerun the migration or overwrite the live database with the desktop snapshot.

The signed standalone APK uses the public HTTPS API address. Downloads at
`https://api.remineph.online/download` are served directly from the `rescene` R2
bucket by the API Worker, with range support and no VPS download traffic. The
existing VPS release directory is a legacy backup, not the public download
origin. `tools/build_android_release.py` builds, aligns, signs and verifies the
slim ARM64 APK; `tools/publish_android_release.mjs` uploads and verifies it in R2
before switching the Worker. See [Android build/publishing](../infra/android/README.md).
The update signing key and password remain private in `backend/data/android-signing/`;
preserve them for future APK updates. `builds/release.json` records APK and
certificate hashes. The current deployment uses **Elysium mainnet (99901), HYPE gas**; STARL is the game currency. Mainnet addresses are recorded in `contracts/deployments/elysium-mainnet.json`.

Registration agreement rollout (2026-11-11): API code was built with the existing
runtime settings and staged without copying environment files or database data.
The pre-change binary is `/opt/remine/rescene-api.before-legal-20261111`; the
running API was replaced with `docker compose up -d --wait --no-deps api` after
publishing the updated client. The required policy version is `2026-11-11` and
agreement audit fields are stored on each newly registered User node. Existing
sessions and login requests need no migration. Policy text/contact and UI checks
are documented in `backend/README.md` and `infra/android/README.md`.


Elysium cutover (2026-11-11): the API now runs `remine-api:elysium-20261111` with all three chain IDs (leaderboard, STARL and marketplace) set to 99901. New addresses and server-only provider configuration are stored in `/opt/remine/api.env`. The service's Compose image and base binary were updated so restart/boot retains the launch. Before reset, the API was stopped and the database, runtime configuration, binary and data files were backed up under `/opt/remine/backups/elysium-20261111`. Eight production-hosted test accounts and their player state/queues were cleared; administrator identities and content configuration were retained. Runtime health, public API health, publisher connection, exact mainnet contract bindings and zero-player census were checked after startup. The admin Worker displays the live network and HYPE gas; Worker version is `71c66f50-6553-4aa4-ba0e-11d1098151a7`.
