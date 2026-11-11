# RESCENE Rhythm web companion

Live at https://rhythm.remineph.online. The fansite at https://remineph.online links here from its navigation and hero. This is a SolidJS 2 / TypeScript companion to the native Android game. It uses the same accounts, progression, server-managed wallet, STARL, inventory, decks, and social backend. It contains no game engine, chart playback, audio files, song previews, or run submission endpoints.

## Screens

- Game-styled lobby, top-five online friends, Android download and installation guide.
- Sign in, register, recovery-code password reset, 30-day persistent browser sessions, logout.
- PULSE member-card marketplace, live stock and prices, explicit checkout confirmation.
- Inventory, five-member PULSE deck, card locking, refinement and permanent donor sacrifice using the server quote/confirmation protocol. Item use restores energy only after backend confirmation.
- Daily gifts, dated daily mission claims, milestone rewards, titles and frames.
- Searchable 32-song catalog, four-difficulty leaderboards and personal records; all playing remains on Android.
- Profile, avatar upload, up to five gallery photos, replacement/removal, wallet, password change and one-time recovery codes.
- Followers/following, mutual friends, private chat/read receipts/typing delivery, player and content reports, block/unblock, challenge invitations and results. Chat refreshes every five seconds while open; friends and unread counts refresh every 20 seconds while the page is visible. No Firebase or closed-browser push integration.

## Browser security and hosting

Cloudflare Worker `rescene-rhythm-web` serves `dist/` and proxies an explicit allowlist of game APIs. The private `GAME_API` service binding targets the existing `remine-game-api` Worker, which forwards to the VPS. The verified client IP is retained for backend rate limiting. No Engine signing credentials are shipped to the browser.

Each login creates an opaque random 256-bit `__Host-rhythm` cookie (HttpOnly, Secure, SameSite=Strict, path `/`, 30-day lifetime). Access/refresh tokens are held only in a durable SQLite `SessionVault`, with expiration alarms. Refresh rotation is serialized across simultaneous requests/tabs; the refresh request ID is persisted before sending so lost responses can retry safely. Logout revokes the backend refresh token and deletes durable session state. Password changes invalidate backend credentials as in Android.

Browser mutations require an exact same-origin Origin header; no cross-origin API access is granted. Browser-provided authorization, cookies, admin proofs and target URLs are never forwarded. The companion blocks `/runs` routes. CSP also sets `media-src 'none'`. The companion uses the game API on Elysium Mainnet (99901); HYPE pays gas and STARL remains the in-game currency.

Asset output is limited to `public/` and the Vite bundle. `.gdignore` and Android export exclusions keep the companion, dependencies, and tests outside the APK.

## Development

Node 24 (or supported Node 22), npm, and the existing Wrangler OAuth login:

```sh
npm ci
npm run check
npm run build
npm test
npm run test:browser
npm run deploy
```

`npm run dev` starts the Solid dev server on port 5190. `npm run preview` starts the production Worker on port 8790. Local authenticated requests need a connected local `remine-game-api` Worker/service binding; production uses the configured deployed binding. Browser tests intercept only APIs with explicit test fixtures and verify frontend confirmation payloads. The normal app uses live APIs.

`node scripts/live-smoke.mjs` additionally verifies deployed login persistence, secure cookies, live APIs, profile media upload/removal using an isolated QA account, blocked gameplay, no playback, and the real APK redirect/range response. It reads credentials privately from `../backend/data/vps-deployment/qa-player.json`; it never logs credentials or saves browser sessions. It does not spend STARL or sacrifice cards. Its non-secret report is `../output/webapp-live-verification.json` and screenshots are `../previews/webapp-live-*.png`.

Dependencies follow the existing fansite/admin: Solid 2.0.0-rc.21 and matching @solidjs/web, pinned compiler/runtime versions, strict TypeScript. Artwork is optimized WebP from existing game assets. Fonts and licenses originate from `../assets/fonts/`. The API download URL streams the APK from the private `rescene` R2 bucket through its Worker binding, without routing download bytes through the VPS. `node ../tools/publish_android_release.mjs` verifies/uploads a release and updates `public/release.json`; redeploy this companion afterward so the displayed version, size, and checksum match the download.
