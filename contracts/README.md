# RESCENE on-chain leaderboards

`src/ResceneLeaderboard.sol` stores a personal best for every published player/chart and maintains a sorted Top 25 on-chain. It is a standalone, non-upgradeable EVM contract. The Go API automatically publishes replay-verified personal-best improvements through Engine. Engine deployed it for the `rescene-rhythm` project on Arbitrum Sepolia (421614) at `0xb5cc39d72012345198bf17c56c1bbb4adad60933`. All 128 current chart revisions are registered and verified. See [addresses and receipts](deployments/arbitrum-sepolia.json) for the leaderboard, exact thirdweb MarketplaceV3 and TokenERC1155 instances, and [chart registration receipts](deployments/arbitrum-sepolia-boards.json).

## Ranking and identity

Each board is `keccak256(abi.encode(string songId, uint8 difficulty, bytes32 revision))`. Difficulty is Easy=0, Normal=1, Hard=2, Ultra Hard=3. Use the raw SHA-256 revision bytes from `backend/charts.json`, not the hash of its hex text. `registerBoard` records its scoring-unit count, which cannot be overwritten. Register new revisions as separate boards; `setBoardEnabled` can close old boards to writes while preserving reads.

Player IDs and run IDs are the backend's existing 16 random bytes. Decode each 32-character hex ID directly into `bytes16`; do not hash it, ASCII-encode it or use the wallet address as the player ID. This retains account identity independently of wallet provisioning. Comparing these fixed-width bytes also preserves the backend's lexicographic account-ID tie-breaker. All published identifiers and scores are public. Usernames, credentials, wallets and input replays are not stored in this contract.

Ordering matches `backend/scores.go`: score descending, combo descending, achievement time ascending, player ID ascending. Only a higher score, or an equal score with a higher combo, replaces a player's best. An exact score/combo tie retains the existing record and timestamp. Achievement time is UTC Unix **milliseconds**. The contract accepts timestamps in or before the current block's second; it does not derive achievement time from transaction ordering.

`submitScore(boardId, Entry)` is restricted to `PUBLISHER_ROLE`. `Entry` is `(bytes16 playerId, bytes16 runId, uint32 score, uint32 maxCombo, uint64 achievedAt)`. Score must be 500,000–1,000,000, matching the backend's rewarded-clear threshold; combo must be 1–the board's scoring units. Successful submissions consume `(playerId, runId)` across all boards, including non-improvements. Failed calls consume nothing. Reusing a run reverts. `processedRuns` and `ScoreProcessed` support safe retry reconciliation.

Every best is available through `personalBests(boardId, playerId)`, and `boards(boardId)` reports scoring units, distinct published players, and enabled status. `getTop(boardId)` returns up to 25 complete entries in rank order. `topRank` returns a one-based Top 25 position or zero. An unknown board has empty reads and rejects writes.

Updates scan at most 25 players. Full ranks and Near Me outside the Top 25 require an event indexer: replay `ScoreProcessed` events with `improved=true`, retain each player's latest improvement and apply the same ordering. The contract does not scan or sort the entire player population to calculate arbitrary ranks.

## Trust and administration

The publisher is the gameplay authority. The contract cannot replay inputs, prove a human played, or stop a compromised publisher from submitting plausible false scores or timestamps. It checks access, chart bounds, duplicate runs and best/ranking rules. It does not award XP, mint tokens or distribute prizes. Only publish runs that the Go backend has committed as replay-validated, uninterrupted ranked clears.

The constructor takes `(admin, publisher, adminDelay)`. It grants the publisher only `PUBLISHER_ROLE`; the admin receives `CHART_ADMIN_ROLE`, `PAUSER_ROLE`, and the default admin role. Roles can be separately granted/revoked for key rotation. Pausers can stop all score writes, while only the default admin can resume them. Reads remain available when paused. Use a separate admin/multisig and operational publisher address.

OpenZeppelin's [AccessControlDefaultAdminRules](https://docs.openzeppelin.com/contracts/5.x/api/access#AccessControlDefaultAdminRules) enforces delayed, two-step default-admin transfer. The deployment script defaults to two days. Transferring default administration does **not** transfer the old admin's chart/pauser roles; explicitly rotate these too. No role can directly delete or overwrite an existing best. This implementation has automated tests, not an independent security audit.

## Build and test

Requires Foundry (`forge`, `cast`, and optionally `anvil`) and Python 3. From `contracts/`:

```bash
bash script/install_dependencies.sh
python3 script/export_charts.py
forge fmt --check
forge build --sizes
forge test -vv
```

The install script pins OpenZeppelin Contracts 5.6.1 and forge-std 1.12.0 to exact commits. Solidity is pinned to 0.8.30, with the Paris EVM target. Dependencies/build outputs are ignored, and `.gdignore` plus the Android export exclusion keep contracts and tooling out of the game package.

The tests cover publication authorization, publisher rotation, delayed administration, immutable chart metadata, chart isolation, score bounds, duplicate and non-improving submissions, all ordering rules, Top 25 eviction/reentry, pause/disable recovery, and 256 randomized differential runs against an independent full-sort model.

## Deployment and chart registration

Choose an EVM chain/RPC first. Configure public addresses and use a Foundry encrypted keystore or hardware signer for the deploying account:

```bash
export RPC_URL='https://YOUR_RPC'
export LEADERBOARD_ADMIN='0xYOUR_ADMIN_ADDRESS'
export LEADERBOARD_PUBLISHER='0xYOUR_PUBLISHER_ADDRESS'
export LEADERBOARD_ADMIN_DELAY=172800

# Simulate first. Add --broadcast to send the deployment.
forge script script/DeployLeaderboard.s.sol:DeployLeaderboard \
  --rpc-url "$RPC_URL" --account YOUR_DEPLOYER_KEYSTORE
```

Copy the deployed address into `LEADERBOARD_ADDRESS`. The chart registration signer must hold `CHART_ADMIN_ROLE` (initially the admin). Regenerate `charts.json` whenever the authoritative backend catalog changes. The generated manifest contains registration metadata only; Foundry reads object fields in alphabetical order to decode the script's `Chart` struct.

```bash
python3 script/export_charts.py
export LEADERBOARD_ADDRESS='0xYOUR_DEPLOYED_CONTRACT'
export CHART_START=0
export CHART_COUNT=16

# Simulate first. Add --broadcast to register this batch.
forge script script/RegisterCharts.s.sol:RegisterCharts \
  --rpc-url "$RPC_URL" --account YOUR_CHART_ADMIN_KEYSTORE
```

Repeat with start indices 16, 32, etc.; the current catalog has 128 revisions. Registration skips boards already present with matching units and rejects a unit mismatch. It does not re-enable disabled boards. Ranges must fit within the manifest. Choose a batch size appropriate for the chain. The deployment and all 128 registrations were also exercised against a disposable local Anvil chain.

## Backend integration

The Go backend commits a durable publication job atomically with each replay-verified ranked personal-best improvement and account progression. Its worker preserves per-player/chart order, submits through Engine with a persistent idempotency key, and checks `processedRuns` plus the exact `ScoreProcessed` receipt before reporting confirmation. It waits for three confirmations by default and periodically audits confirmed jobs for reorganizations. Lost HTTP responses are recovered from indexed events; failed jobs retry without delaying gameplay.

Startup backfill accepts current-revision bests only when a version-2 replay validation marker or retained verified progression receipt proves their origin. Original best timestamps are retained. Practice, failed, paused, offline, and unverified results are not published.

See [backend configuration and status API](../backend/README.md#automatic-on-chain-score-publication). The game displays publication status beside the player's leaderboard best. Full rankings, Near Me and public profile lookup continue to use FalkorDB; the on-chain contract independently retains personal bests and Top 25.

## Starlight rewards

STARL is an Engine ERC-20 on Arbitrum Sepolia: `0xea99194cb96917672973eb55350c667c68c04c20`, name RESCENE Starlight, 18 decimals, initial supply 100,000,000. The project treasury owns the token; the standard Engine template allows owner minting and holder burning. Ordinary rewards transfer existing supply, never mint.

`src/StarlightRewards.sol` is deployed at `0xb2fd98c13d2c11cc79315706554eacb185bb8743` and registered as an imported contract in the Engine project. Its immutable token and treasury bindings were checked on-chain. Only the treasury may call pay. The contract spends a finite treasury approval via transferFrom, records a digest per reward ID, returns for an identical retry, and rejects reuse with a different recipient/amount. A failed ERC-20 transfer rolls back its reward marker. Treasury can revoke the allowance directly on STARL.

The Engine operator source is `gmr-engine/cmd/starlight-rewards-operator/main.go` in the Engine workspace. It uses Engine's wallet lock and Vault signer inside the Engine container, checks the expected project/testnet/treasury/token, saves a launch guard before broadcasting, and imports the confirmed public ABI into the dashboard. No private key was exported. Inspect chain history and saved receipts before repeating an uncertain deployment. Public request/receipt/ABI artifacts live in `deployments/`; no credentials are included.

`forge test --match-contract StarlightRewardsTest` checks authorization, supply conservation, failed-transfer rollback, changed-payload rejection and duplicate payouts across fuzzed amounts/retry counts. The Go worker additionally verifies the canonical receipt and both RewardPaid and token Transfer events.

## EnergyDrinkShop

`src/EnergyDrinkShop.sol` is deployed at `0x5ace042c739c4b49fef8774a7eb2c54136ef55af` on Arbitrum Sepolia. It binds the existing STARL, ERC-1155 collection, MarketplaceV3, treasury/operator, token ID 0, listing ID 0 and price 100 STARL. There is no upgrade/admin setter. The initial 10,000 Energy Drinks were minted in the existing collection and listed through Engine; the item metadata is an on-chain data URI with a public PNG image.

`purchase(orderId,buyer,quantity)` is treasury-only. It validates listing identity/status/currency/price/stock/time, pulls exactly the buyer's approved STARL, approves exactly that total to the market, buys for the player, and checks delivery. A digest prevents repeats or changed payloads. `consume(consumeId,player)` burns exactly one of the fixed item ID after approval and remembers its ID. The backend grants energy only from the confirmed burn and atomically records its receipt. `fundGas` grants at most 0.0001 ETH per ID; an exact retry refunds its duplicate native value to the operator instead of funding twice. All external state-changing functions are non-reentrant.

The approved collection operator can only be exercised by the backend treasury and this fixed-item router. Players may revoke approvals on-chain; the server never treats approval alone as payment or item delivery. The original MarketplaceV3 fee/royalty rules still apply. The game keeps off-chain XP/energy authority in FalkorDB and on-chain token/item authority in the contracts.

Foundry tests cover atomic payment/delivery, changed quotes, authorization, missing approvals, rollback, repeated burns, repeated gas funding, and fuzzed purchase retry counts. An explicit testnet integration test confirmed a 100 STARL payment, one delivered NFT, one burn and exactly +5 energy using a separate managed test wallet. See `deployments/energy-shop-live-verification.json`.

## MemberCardShop

`src/MemberCardShop.sol` is deployed at `0xa8e3dd8cf231da2bf318e0e6c3486c11b6d1acb7` on Arbitrum Sepolia. It fixes treasury/STARL/collection/market, initial token and listing IDs 1, a five-card range and price 450 STARL per unit. Card order digests include buyer, quantity and token ID; the treasury-only `purchaseCard` verifies the exact corresponding listing, pulls payment, buys for the player and requires matching ERC-1155 delivery in one execution. Failed payment/delivery rolls back the order marker. An identical retry is a no-op; a different card or quantity with the same ID reverts.

The five metadata data URIs and 10,000-unit initial listings are recorded in `deployments/member-card-listings.json`. Portrait images use the existing, named concept-photo sources under `output/cards/pulse-le-set/sources`, served at the URLs in metadata. These First Scene SR cards have their own native frame and do not replace the separately prepared PULSE LE artwork. The original ERC-1155 admin mint authority remains unchanged.

There is no burn/consume function or mutable configuration in MemberCardShop. Cosmetic equipping is a server ownership check and persisted preference, not a token transfer or blockchain transaction. Managed-wallet STARL approvals and bounded gas grants follow the drink workflow. Foundry tests exercise all five IDs, quantity bounds, retry digests, authorization, invalid item IDs, price changes and payment rollback. The opt-in live verification record contains the isolated test purchase and equip result.

## PulseCards — individual PULSE LE cards

`src/PulseCards.sol` VERSION 2 implements unique supply-one tokens in the existing ERC-1155 collection. Its registry stores immutable rolled stats/skill and mutable per-token level, XP, stars and sacrifice progress; transfers preserve this state. Purchase, material delivery, refinement and donor burns update action digests and metadata atomically. Identical retries are no-ops and changed payloads revert. Managed-wallet approvals and receipt verification are handled by the backend through Engine.

The operator-only purchase path starts closed. Before enabling it, configure the existing collection/STARL/treasury, material IDs 11/12/13, collection minter and metadata roles, mutable URI, treasury material stock and delivery approval. The older `PulseItemShop` draft and live cosmetic `MemberCardShop` do not implement this protocol. No new router or stock has been deployed by this change. The user deferred the LE supply/reissue policy; publish and enforce that policy before opening sales.

See [the complete card rules and rollout prerequisites](../docs/cards.md). Run `forge test --match-contract PulseCardsTest` for payment/delivery, frozen traits, refinement success/failure, all star costs, donor protection and overflow, transfer continuity, metadata and rollback tests. Native and Go integration tests also verify five-member album decks and combined gameplay bonuses.

## Elysium mainnet launch

All 8 current game contracts are deployed and verified on Elysium mainnet (`99901`, HYPE gas). The Engine project is in production and permits Elysium only. The hosted game API uses these addresses for automatic score publication, treasury rewards, the Energy Drink shop, PULSE cards and event materials. The legacy First Scene shop was excluded.

See [the mainnet manifest](deployments/elysium-mainnet.json), [all 145 confirmed deployment/setup transactions](deployments/elysium-mainnet-launch.json), and [cutover/reset verification](deployments/elysium-cutover.json). The 13 contract creations comprise 8 application contracts plus the ERC-1155 implementation, Marketplace implementation and 3 marketplace extensions. The existing two TWProxy addresses are included among the 8 application contracts.

The launch registered all 128 current chart revisions, issued 100,000,000 STARL to the treasury, stocked 10,000 Energy Drinks and 10,000 of each refinement material, configured the finite reward allowance, and opened PULSE's initial 50/member allocation. Independent backend reads verified market connectivity, reward bindings/allowance, card roles, mutable metadata and stocks. The exact existing thirdweb sources and custom contract artifacts are pinned under `launch/elysium-20261111/`.

Player test accounts, progress, scores, sessions, wallet links and queued jobs were cleared after a cold backup. Operator identities and administration content remain available. Production backup: `/opt/remine/backups/elysium-20261111`. The local retired test graph was backed up and cleared too. Arbitrum deployment manifests remain historical references.
