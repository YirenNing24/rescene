# Admin implementation status

Deployment: https://admin.remineph.online · November 10, 2026. The game API and FalkorDB now run on the VPS at https://api.remineph.online; the former desktop origin is disabled.

The 24 planned areas and expanded player/social area have navigation and underlying inspection or record-management surfaces. This is a functional first admin release, **not completion of every bullet in the exhaustive scope**. The table distinguishes active capabilities from remaining implementation.

| Area | Available now | Remaining |
| --- | --- | --- |
| 1. Overview | Real account, presence, progression, order and queue counts; registration history; freshness and scan limits | Full lifetime economic/supply rollups and saved multi-dimensional views |
| 2. Analytics | New authenticated mutation telemetry, outcomes, latency, unique players and completion counts in a labeled retained window; export | DAU/WAU/MAU rollups, D1/D7/D30 cohorts, acquisition, sessions/crashes, historical warehouse and retention policy |
| 3. Player detail | Search by username, ID or wallet; progression, records, wallet, sessions, inventory, avatar/gallery, follows/friends/blocks, support notes | Search by arbitrary order/transaction/token; merged historical timeline and profile bio/privacy extensions |
| 4. Support | Suspend/restore, revoke sessions and existing tokens, restrict social/uploads, bounded idempotent XP/energy grants, player password changes and recovery codes, STARL compensation intents, cases/notes | Timed restrictions, username migration, approval escalation |
| 5. Configuration | Five server-enforced live switches; current compiled energy/level rules; versioned proposals and history | Live energy/reward/mission rule overrides with run snapshots, scheduled activation and compatibility gates |
| 6. Missions/gifts/events | Authoritative current mission/calendar inspection and versioned event/mission/calendar/announcement records | In-game content feed, targeting/localization delivery, scheduling and reward-rule migration |
| 7. Songs/charts | Real embedded chart catalog, difficulties, revisions, scoring units/duration; release records | Import pipeline, revision diff/validation UI, distribution and compatibility rollout |
| 8. Runs/leaderboards | Retained active tickets/decks, records, quarantine/restore off-chain, publication queues, typed pause/board availability intents | Complete replay history, anti-cheat cases, board registration UI and contract migration for score deletion |
| 9. Store | Live stock, price, router checks and readiness; fixed-price constraints | Dynamic merchandising feed, featured placements, account limits and future bundles |
| 10. Listings | Typed create/update/cancel intents with ABI packing, bounded quantities, fixed prices and simulation | Stock alerts, reserved/sold aggregates, scheduled changes and richer reconciliation |
| 11. Minting | Registered stock mint intents, recipient/quantity/metadata validation, CSV imports, simulation/review, durable operation state | New type allocation, richer metadata publisher, multi-approval signing and automatic batch execution/recovery |
| 12. Individual cards | Deployed PULSE registry, initial 50/member sale allocation, admin issuance with persisted random traits, material stock and mutable metadata | Global token/holder index and long-term release planning |
| 13. Card registry | Retained purchase/upgrade operations; player confirmed inventory inspector | Global token/holder index, transfer/burn provenance, full unique PULSE registry after deployment |
| 14. Refinement/decks | Upgrade operation inspection, current rules, run-bound deck snapshots and reservations | Dedicated complete skill/upgrade analytics and post-deployment unique-card drill-down |
| 15. Inventory | Confirmed per-player inventory and consumable inspection, registered item definitions | Full stock/holder index, global reservations view, administrative delivery reconciliation |
| 16. Transactions | Unified retained shop/payout/publication queues; operation intent/result views and JSON export | Global chain index, additional filters and complete historical attribution |
| 17. Recovery | Wake original jobs without clearing active leases; retain immutable signing intent and idempotency keys | Automatic resolution of ambiguous admin Engine submissions lacking a verified ID; reorg incident tooling |
| 18. Treasury/wallets | Live STARL/supply/gas, wallets/provisioning, bounded transfer/allowance/compensation intents | Gas budgets/alerts, multisig approval policy and detailed treasury ledger |
| 19. Contracts | Configured deployment registry and explorer links; allowlisted typed write paths | Dedicated live role-grant/revoke/ownership migration controls and deployment automation |
| 20. PULSE launch | Deployed testnet registry, collection roles/URI checks, stocked materials and initial sales; artwork reissues/admin mints explicitly allowed | Mainnet release, economic review and published edition schedule |
| 21. Admin identity | Owner bootstrap, access-key login, encrypted TOTP, six roles, revocation, write audit and document revisions | Self-service key rotation/MFA recovery, richer audit payload diffs, independent approval/quorum workflow; Cloudflare Access requires additional permissions |
| 22. Monitoring/releases | Database latency, configured integrations, queue inspection, versioned release records | External uptime/error alert delivery, incident workflow, actual backup/restore automation and retention jobs |
| 23. Shared UI | Responsive navigation, search/filter, profiles, tables, record inspection, JSON exports, guarded review/confirmation and errors | Saved views, richer bulk tools, CSV exports throughout and further accessibility audit |
| 24. Artwork/metadata | Private normalized JPG/PNG uploads, content hashes, authenticated media library, reviewed mint metadata URI | Cropping/variants, schema-aware public metadata publishing, localization and release asset promotion |
| 25. Profiles/friends/photos | Existing native friends through mutual follows, blocking, messaging, avatar/five-photo gallery; admin inspection and server moderation restrictions | Explicit friend-request alternative, profile biography/privacy expansion, social retention and profile privacy controls |

## Operational notes

- The later PULSE rollout deployed the unique-card router, stocked refinement IDs 11–13, retired old listings and enabled the initial 50/member allocation. This remains Arbitrum Sepolia testnet.
- The older deployed First Scene router only supports its own item/listing IDs. The catalog now uses those compatible products when a PULSE router is not configured; reserved PULSE products/materials are not advertised as purchasable.
- The API/database run in a separate VPS Compose project with the existing named tunnel, boot services and daily private backups. See [vps-deployment.md](vps-deployment.md).
- The Owner key is local in `backend/data/admin-owner-access.txt`. The Owner authenticator has not been enrolled by automated checks.
- Existing player passwords, JWT secrets, Engine keys, refresh tokens and database credentials are never sent to the admin browser.
