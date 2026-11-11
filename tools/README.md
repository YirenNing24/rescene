Current production is Elysium Mainnet (chain 99901), with HYPE for gas and STARL for game payments. The canonical addresses are in `../contracts/deployments/elysium-mainnet.json`.

For read-only checks, use `node tools/cutover_elysium.mjs verify` and the opt-in backend tests `TestMarketplaceLiveReadOnly`, `TestStarlightLiveReadOnly`, and `TestPulseLaunchLiveReadiness` with the private production configuration. These checks do not publish scores, mint inventory, or send transactions.

The Elysium launch and database reset are complete. Do not rerun `launch_elysium.mjs stage/run`, `cutover_elysium.mjs prepare/activate`, or the initial inventory setup as routine verification. They are migration operations, not health checks.

The older `deploy_*`, `setup_*`, and `verify_pulse_live.py` scripts containing Arbitrum Sepolia settings document the retired test deployment. They must not be retargeted or replayed against mainnet: sender nonces produced overlapping addresses for different contracts across the two networks. Historical manifests and receipts retain their original chain IDs intentionally.

`verify_launch_api.py` creates a QA player and managed wallet. It is not a read-only production check. `deploy_game_vps.mjs` is the initial bootstrap helper and copies private environment files; preserve the running VPS environment and database for subsequent code releases.
