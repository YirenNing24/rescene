# RESCENE game administration: proposed implementation scope

Prepared November 10, 2026 (Asia/Manila). This is a requirements and implementation plan based on the repository and recorded deployment artifacts. It does not assert that recorded deployments are currently healthy, and it does not execute any mint, transfer, burn, or contract change.

## Intended application

- Separate SolidJS 2 administration frontend, proposed hostname `admin.remineph.online`, deployed on Cloudflare Workers.
- Dedicated administrator identity, permissions, sessions, and `/api/admin/v1` endpoints in the existing Go backend.
- Existing FalkorDB remains the authoritative game store. Engine remains the server-side signing/transaction service; chain/RPC reads verify ownership and receipts.
- Admin browser requests never receive Engine credentials, private keys, database credentials, or player refresh tokens.
- Monitoring data and historical aggregates receive a defined retention model; query-heavy analytics should not scan the live account graph on every dashboard refresh.
- Clear development/staging/production and chain indicators. Initial chain configuration follows the recorded Arbitrum Sepolia deployments; mainnet requires a separate rollout.

## Audit findings and missing foundations

1. `backend/server.go` exposes player-facing routes and `/healthz`; no admin route group, administrator accounts, or admin authorization layer was found.
2. Accounts, rolling player sessions, progression, energy, missions, daily gifts, verified scores, wallet provisioning, durable background jobs, player avatars, and a five-photo gallery already exist in the repository.
3. STARL rewards, EnergyDrinkShop, MemberCardShop, MarketplaceV3, and the ERC-1155 collection have recorded testnet deployments. Connecting the admin must independently verify code, chain, roles, balances, and current state.
4. The Energy Drink and First Scene purchase/consumption workflows exist. Stock setup, minting, and listing management currently rely on operator scripts rather than an admin workflow.
5. `PulseCards` VERSION 2, related APIs, native UI, and tests exist locally. `docs/cards.md` explicitly records that the new router has not been deployed, materials have not been minted by that implementation, and sales begin closed.
6. PULSE LE supply limits and artwork reissue rules remain undecided and unenforced. Launch must resolve these before sales open.
7. Several economic values, chart definitions, and scoring rules are compiled into Go/Godot code; some contract prices, recipients, and operators are immutable. An editable form alone cannot make them dynamic.
8. No complete analytics/event ingestion, global transaction explorer, admin audit trail, support console, live configuration publishing system, or operator alerting layer was found.
9. Raw input replays are not retained by the backend. Progression receipts are bounded. Complete historical investigations and retention metrics require additional collection and storage from rollout onward; unavailable history must remain labeled unavailable.
10. Player password recovery is outside the current login flow. Account restrictions, recovery, and session invalidation require backend work; admin UI alone is insufficient.
11. Player photo uploads and profile viewing have existing Go/Godot implementations. A friendship/request/block system was not found. The expanded social scope requires game UI, API, persistence, privacy enforcement, and admin moderation work.

## Functional modules

### 1. Operations overview

- Total accounts, new registrations, active players, active runs, validated clears, and game/service health.
- Store orders, delivered items, consumed items, STARL earned/paid/spent, treasury balances, and pending payouts.
- Minted and burned supply, stock alerts, wallet provisioning backlog, transaction backlog, and oldest unresolved operation.
- Date, environment, chain, item, album, and release filters; saved views and drill-down into the underlying records.
- Explicit freshness timestamps, source labels, and unavailable-data states.

### 2. Analytics and telemetry

- Session starts/ends and activity heartbeats; DAU/WAU/MAU and concurrent-player estimates with documented definitions.
- D1/D7/D30 retention, acquisition cohorts, session duration, progression cohorts, and version/platform breakdowns where collected.
- Song selection/start/completion/abandon/failure funnels; difficulty, accuracy, grade, combo, and completion distributions.
- Shop view/quote/checkout/delivery/use funnel and unique buyer/repeat buyer reporting.
- Card generation, refinement outcomes, star upgrades, donor burns, and deck usage.
- Crash/error ingestion, API latency/error rates, dashboards, CSV exports, and historical rollups.
- Separate measured events, derived aggregates, test accounts, and incomplete history. No fabricated historical charts.

### 3. Player search and full player detail

- Search by player ID, username, wallet address, order ID, token ID, or transaction hash.
- Account creation, status, observed activity, sessions, wallet provisioning, progression, energy, daily rewards, and mission history.
- Records, current rankings, publication state, inventory, favorite card, five-member album decks, active run, and card reservations.
- Unified chronological support timeline with links to each related entity.
- Internal notes, support labels, and appropriately scoped exports.
- Open a player's profile from search, leaderboards, friends, reports, and transaction records. Provide a player-visible preview beside permission-scoped administrative details.
- Profile images, gallery, social settings, friendship/request counts, blocks, and reports as those social capabilities are implemented.

### 4. Account and support operations

- Suspend/restore accounts with reason, duration, and history; enforce the restriction server-side.
- Revoke one/all sessions and prevent existing access tokens from bypassing an imposed restriction.
- Secure recovery workflow and username changes where supported; never reveal existing passwords or credentials.
- Investigate blocked purchases, missing rewards, stuck inventories, or failed wallet setup from a player detail page.
- Compensation requests with explicit recipients, reason, item/amount, approval, delivery, and idempotency.
- Separate support grants from earned progression and on-chain balances; preserve ledger meaning.

### 5. Game configuration and economy rules

- Versioned settings with draft, validation, preview, scheduled activation, rollback, author, and history.
- Energy cap, run cost, regeneration period, refill amounts, XP curves, clear rewards, and mission rewards.
- Feature switches for purchases, card systems, rewards, events, and maintenance.
- Limits on purchases, reward grants, gas funding, and operational batch sizes.
- Declare which changes are live, require an API restart, require a game release, or require a new contract.
- Client/server compatibility gates; in-flight runs retain the rules with which they began.

### 6. Missions, daily gifts, events, and announcements

- Manage mission definitions, eligibility, reset schedules, rewards, activation windows, and completion/claim reporting.
- Manage seven-day calendars and future reward cycles without double-granting existing claims.
- Create scheduled events, temporary reward multipliers where supported, notices, and maintenance messages.
- In-game delivery, localization, preview, expiration, and client-version targeting require new API/client integrations.
- Record every event/config version and grant policy.

### 7. Songs, charts, and scoring operations

- Browse the authoritative song catalog, album mappings, chart revisions, difficulties, durations, scoring units, and release status.
- Chart validation, import staging, revision comparison, compatibility review, and deployment status.
- Enable/disable eligible songs and boards using implemented server/client gates.
- Completion and failure rates, difficulty balancing reports, and calibration-related telemetry if collected.
- Publish new embedded catalogs and preserve existing revision boundaries.
- A full musical chart editor or automatic new-chart generation is separate work; the admin manages approved chart releases.

### 8. Runs, validation, and leaderboards

- Active, completed, abandoned, expired, paused/unranked, rejected, and pending-sync run visibility as data is retained.
- Verification outcomes, rejection reasons, score/accuracy/combo distributions, suspicious patterns, and case notes.
- Top/nearby records, chart revision filters, player contributions, and on-chain publication links.
- Quarantine/reinstate off-chain records through an auditable moderation model.
- Register/enable/disable on-chain boards, and retry original eligible publication jobs without inventing scores.
- The current leaderboard contract has no arbitrary historical-score deletion function. Address that limitation explicitly in any remediation or contract migration.

### 9. Store catalog and merchandising

- Products for Energy Drinks, First Scene collectibles, PULSE cards, and refinement materials.
- Item definitions, category, display order, artwork, descriptions, visibility, featured placement, availability, and eligibility.
- Price, currency, stock, quantities, schedules, sold-out states, listing/token mappings, and per-account limits.
- Store/game preview and validation before publication.
- Draft future bundles/packs only; opening them requires their purchase, distribution, and gameplay implementations.
- Existing immutable router prices cannot be changed by updating a catalog field. Contract-compatible price/version migrations must be explicit.

### 10. Listings and stock

- Marketplace listings, treasury inventory, available/reserved/sold stock, start/end times, and seller/asset/currency verification.
- Create/update/cancel listings where the deployed marketplace ABI and permissions support the operation.
- Mint/replenish stock, approve delivery operators, and reconcile chain stock with catalog availability.
- Low-stock thresholds, sale scheduling, and launch previews.
- Pin orders to their original listing/router; block unsafe migrations while operations remain unresolved.

### 11. Item definitions and minting

- Register ERC-1155 item types, token-ID allocation/reservations, metadata URI, artwork, categories, and intended use.
- Fungible item batch mints for drinks/materials and controlled First Scene stock issuance.
- Select treasury or eligible recipient wallets; validate chain, contract, recipient, quantity, metadata, and supply policy.
- Single/batch jobs, CSV recipient imports, per-row validation, preview, simulation, approvals, progress, and receipts.
- Minted supply, burned supply, treasury stock, holder distribution, and allocation reporting.
- Stable action IDs and durable intent prevent retries from minting twice.

### 12. Individual card issuance and mint policy

- PULSE card issuance with unique supply-one token IDs, member, set, rarity, immutable traits, and skill.
- Persist the selected randomness policy/version and rolled outcome before submission; retries reuse the original outcome.
- Authorized promotional/admin generation separate from paid purchases, with source and reason in the audit trail.
- Per-member/per-set supply budgets, allocation pools, sale windows, issuance limits, and reissue policy once decided and enforced.
- Distinguish the unique token's supply of one from the overall number of LE cards that can be issued.
- Show the existing trusted server randomness accurately; verifiable randomness would require a separate protocol integration.

### 13. Card registry and ownership

- Search every card by individual ID, collection/token, owner, member, rarity, skill, and set.
- Original traits, generation transaction, current level/XP/stars, progress, revision, metadata, and current confirmed owner.
- Lock/equipped/listed/in-use flags and off-chain reservations with their originating run or operation.
- First Scene cosmetic cards versus gameplay-affecting PULSE cards.
- Owner transfer history, burns, metadata changes, and integrity warnings.
- Minted immutable traits are inspected rather than silently edited.

### 14. Refinement, star upgrades, skills, and decks

- Material definitions and stock, XP per bundle, level costs/odds, and versioned policy explanations.
- Per-attempt history: inputs, persisted roll/outcome, consumed material, XP movement, resulting level, and transaction.
- Star-upgrade donor/receiver review, permanent burns, wasted donors, compatibility, and protection checks.
- Separate successful transactions with failed probabilistic refinement from failed blockchain transactions.
- Five member slots per album, ownership eligibility, frozen run loadouts, and reservation diagnostics.
- Skill catalog, star-rank effects, duplicate-skill rules, team caps, and parity tests for proposed changes.
- Balance changes affecting the judge, client, or contracts go through coordinated versioned releases.

### 15. Inventory and consumables

- Player and treasury quantities at a confirmed block; acquired/used/transferred/burned history.
- Item-consumption receipts and the associated energy refill or other supported game effect.
- Detect missing delivery, duplicate-looking receipts, stale ownership, or accounting differences.
- Authorized grants/replacements and reservation-aware corrections through explicit operations.
- Recovery checks preserve the at-most-once burn and at-most-once grant guarantees.

### 16. Orders and transactions

- Global orders plus Engine transaction IDs, hashes, action IDs, user, wallet, item, quantity, expected total, and contract.
- Step timeline: validation, gas funding, approval, execution, submission, confirmation, event verification, game-state fulfillment.
- Filters for waiting, retrying, submitted, confirming, confirmed, reverted, uncertain, and intervention-required states.
- Exact STARL payment, NFT mint/delivery/burn, block, confirmations, fees, and explorer links.
- Search, saved filters, exports, and related player/card/listing views.
- Separate off-chain operation status, Engine acceptance, and verified on-chain outcome.

### 17. Recovery and reconciliation

- Queues for wallet setup, payouts, score publication, shop operations, and card actions.
- Attempt history, sanitized errors, lease owner/expiry, next retry, original pinned deployment, and oldest pending age.
- Re-query original Engine/chain evidence, re-index events, resume the original job, and verify canonical receipts.
- Reorg detection, repeat-safe reconciliation, orphan/duplicate investigation, and per-operation recovery reports.
- Explicit compensation or refund transactions where supported; never fake success, silently delete uncertain jobs, or erase evidence of a charge/burn.
- Safe release of reservations only after a terminal state or independently verified reconciliation.

### 18. STARL treasury, wallets, and gas

- Treasury token/native balances, approved allowances, payout obligations, supply, reward flows, shop proceeds, and gas costs.
- Separate lifetime-earned progression, actual wallet balances, pending payouts, and purchase spending.
- Wallet provisioning status, managed-address mapping, retry visibility, and identity mismatches.
- Fund treasury/gas and manage finite allowances through role-scoped transaction proposals.
- Reward-distributor and gas-grant limits, low-balance alerts, and per-user/per-operation funding reports.
- Mint/burn/treasury operations only where supported by the deployed token and assigned authority; no private-key viewing/export.

### 19. Contracts, roles, and deployment registry

- Registry of STARL, ERC-1155 collection, MarketplaceV3, reward distributor, leaderboard, drink/card routers, and PULSE router versions.
- Chain, address, deployed code/version, ABI, deployment receipt, operator/owner, supported actions, immutable values, roles, and relevant approvals.
- Read-only state inspector plus typed, allowlisted write forms for supported administration functions.
- Role grants/revocations and delayed ownership transfers where the contract implements them.
- Deployment/import/verification checklists, compatible router migration, environment configuration, and pending-job compatibility gates.
- No arbitrary browser-supplied contract method execution through the game backend.

### 20. PULSE launch console

- Readiness for VERSION 2 deployment, ABI import, correct token/treasury/collection bindings, roles, and mutable metadata.
- Token-ID reservations for existing products, material IDs 11/12/13, stock minting, and treasury delivery approval.
- Confirm supply/reissue policy and enforce it before sales activation.
- Isolated test purchase, refinement, star upgrade, donor protection, deck use, and receipt verification.
- Sales open/close control, rollout state, monitoring, and a rollback/migration plan suited to the actual contract.
- Local implementation readiness must never be shown as a completed live launch.

### 21. Admin identity, permissions, and activity audit

- Invite-only admins, MFA/identity-provider integration, sessions, access revocation, and role-scoped API enforcement.
- Roles for owner, game operations, economy/minting, content, support, and read-only analytics; configurable permission assignments.
- Audit actor, timestamp, environment, target, reason, before/after values, approval, request/action ID, and transaction outcome.
- Draft/simulate/review/execute/confirm lifecycle for blockchain and consequential economy actions; configurable additional approval thresholds.
- Scoped exports, redacted operational details, and audit retention.
- Public fan-site users and game players never gain administrator access through their ordinary login.

### 22. Monitoring, incidents, and releases

- API/database/Engine/RPC health, worker heartbeat, request errors/latency, transaction queues, confirmations, and indexing freshness.
- Alerts for low treasury/gas/stock, stalled jobs, elevated validation failures, failed mints, or config/role mismatches.
- An in-app incident center, acknowledgment/assignment, runbooks, and operational history; external alert delivery requires an explicitly configured destination.
- Maintenance/read-only modes and individual feature shutdowns where server/client gates are implemented.
- Contract pause only where a pause function actually exists; closing the PULSE sales switch does not imply every card operation is paused.
- Client minimum/recommended version, announcements, deployment history, staged config releases, backups, and restore verification.
- Rollback is version-aware: a web deployment rollback cannot reverse confirmed blockchain transactions.

### 23. Shared administration interface

- Global entity search, cross-links, consistent status chips, date/time/chain formatting, and source freshness.
- Pagination, server-side filters, saved views, bulk-action previews, CSV export, and resumable job progress.
- Clear empty/error/loading/disabled states and mobile/tablet access.
- Live updates or polling scoped to the visible view, bounded queries, cached aggregates, and no signing credentials in the browser bundle.

### 24. Artwork, metadata, and publishing assets

- Central library for member/card artwork, frames, item icons, album covers, and announcement assets.
- Upload validation, dimensions, formats, optimized variants, preview, versioning, and broken-URL checks.
- Metadata templates, token URI preview, attribute validation, image/metadata content hashes, and durable hosting or pinning through the selected provider.
- Publish asset changes separately from minting; record which immutable or mutable metadata version each token references.
- Show collection-level URI/metadata permissions and frozen-state limitations before offering an edit.
- Cache invalidation and client/store preview for updated media.

### 25. Player profiles, friends, pictures, and social moderation

Accepted addition to scope: players can view each other's profiles, add friends, and use profile pictures/gallery photos. This includes the native game and backend as well as the admin app.

Player experience:

- Expand the existing player profile with avatar, display name, optional short bio, favorite card, relevant gameplay statistics, records, and gallery.
- Retain the existing avatar plus up to five gallery photos, with upload, replacement, removal, and full-size viewing. Reuse current normalization, file limits, metadata stripping, and ownership checks.
- Find a player by username or player ID; open profiles from leaderboards and friend lists.
- Send/cancel a friend request; accept/decline incoming requests; remove a friend. Friendship requires acceptance by both players.
- Friends screen with accepted friends, incoming/outgoing requests, search, pagination, and clear request/relationship states.
- Friend-request/activity notifications and unread indicators through an implemented notification API/client flow.
- Block/unblock and report a player or individual picture. Blocking must prevent new requests and disallowed social interactions on the server.
- Profile/gallery/friend-list visibility controls with clearly defined everyone/friends/private rules. Existing uploaded images must receive explicit compatibility handling when privacy is introduced.
- Optional presence visibility after activity heartbeat support exists; respect the player's privacy setting and avoid claiming exact online status from stale requests.
- Expose only allowed public fields. Credentials, private wallet/account details, transaction history, and internal support information remain scoped to authorized admin views.

Admin experience:

- Search/open any player; inspect the complete profile and the player-visible rendering.
- Review avatars/gallery, reports, friendship/request relationships, block state, and relevant social activity with permission-scoped access.
- Hide/quarantine reported media, restore it after review within the retention policy, record reasons, and apply upload/profile/social restrictions.
- Report queues with assignee, evidence, decision, appeal/review state, notifications, and audit history.
- Configure photo limits, request/friend limits, request rate limits, visibility defaults, and moderation thresholds through versioned policy.
- Track requests sent/accepted/declined, active friendships, blocks, photo uploads, and report resolution. Collect only the history required by the defined retention policy.
- Define quarantine retention separately from a player's explicit photo deletion; do not promise restoration after permanent deletion.

Backend/game additions:

- Stable friendship/request records and blocked relationships in FalkorDB, including concurrent acceptance, duplicate requests, and idempotent removal.
- Authenticated relationship APIs and visibility-aware profile/media reads. Validate access server-side rather than relying on hidden client controls.
- Game profile/friends/gallery screens, notification UI, local cache invalidation, and account-change isolation.
- Regression tests for cross-account access, blocked users, simultaneous requests, privacy changes, upload limits, and persistence.

## Implementation order

1. Foundation: admin identity/permissions/audit, dedicated Go admin APIs, deployment registry, read-only dashboard, player-profile inspection and preview, wallets, inventory, orders, and queue inspection.
2. Operations and social: telemetry and historical rollups, reconciliation tooling, role-scoped support actions, treasury monitoring, versioned configuration, incident controls, friendships, profile privacy, and picture/social moderation.
3. Economy authoring: catalog/listings, metadata/media workflow, stock and item minting, bulk jobs, compensation, and transaction proposal/approval flows.
4. PULSE rollout: finalize supply/reissue policy and enforcement, deploy VERSION 2, provision materials/roles, validate the integrated lifecycle, then activate approved sales.
5. Advanced live operations: scheduled missions/events/gifts, richer retention/economy analytics, coordinated song/chart releases, and automation around established workflows.

Each phase must connect to authoritative APIs and jobs. Unimplemented controls remain explicitly unavailable rather than reporting simulated success.

## Decisions still required before the corresponding feature can go live

- Initial administrator identity and which people receive each role.
- PULSE LE supply limits per member/set, promotional allocation, and artwork reissue rules.
- Whether supply limits must be guaranteed on-chain. A dashboard limit alone cannot enforce a public hard cap while another collection role can mint outside it.
- Admin/mint/treasury approval thresholds and which signer/role can execute each class of action.
- Analytics collection/retention choices and alert destinations.
- Social visibility defaults and moderation/quarantine retention. Preserve the existing avatar and five-photo gallery as the initial upload scope.
- Whether future packs, player-to-player trading, real-money payments, or mainnet are wanted. They are not implied by an administration console and require their own game/contract/payment scope.

## Repository evidence

- `backend/server.go`: current routes and player authentication.
- `backend/profile_media.go`, `backend/profile_media_test.go`, and the avatar/gallery sections of `backend/README.md`: existing profile picture/gallery behavior and limits.
- `backend/README.md`: progression, wallet, publication, payout, shop, and collection workflows.
- `backend/shop_store.go`, `backend/starlight_store.go`, `backend/publication_store.go`: durable operation records.
- `docs/cards.md`: individual card rules, local-only implementation status, launch prerequisites.
- `contracts/src/*.sol` and `contracts/README.md`: supported actions, permissions, constants, immutability, and recorded deployment distinctions.
