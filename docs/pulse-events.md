# PULSE / The First Scene

The first event is controlled by the game server. Its immutable event ID is
`pulse_first_scene_2026`. Gameplay starts 2026-11-10 16:00 UTC and ends
2026-11-24 16:00 UTC; eligible rewards remain claimable until 2026-11-26 16:00
UTC. In Manila these boundaries are midnight on November 11, 25, and 27.
The featured track changes daily at 16:00 UTC, starting with Finest Thing and
continuing With, Inside Out, MEME, and Dragon in a repeating sequence.

The game issues the event eligibility and featured-track snapshot at run start.
A PULSE run must be completed with at least 50% accuracy, an accepted input
replay, and no pause. It must be started during the event and submitted within
its existing two-hour run expiry. Repeated songs count for clear and featured
missions; the album mission counts distinct songs. Mission targets and rewards
are server-defined. A new edition needs a new ID and a new server release.

Authenticated endpoints:

* `GET /api/v1/events` returns `server_time` and event details. The same event
  snapshot also appears in `GET /api/v1/progression` and progression mutation
  responses.
* `POST /api/v1/events/{event_id}/missions/{mission_id}/claim` accepts `{}`.
  A successful response contains the refreshed progression and reward. A retry
  after a committed claim returns `already_claimed: true` without awarding again.

Claims atomically update progression and durable payment outboxes in FalkorDB.
XP is applied immediately. STARL uses the existing treasury distribution
protocol. The Prism Shards ×10 bundle is ERC-1155 token 11; the dedicated
`EventRefinementRewards` router transfers existing treasury inventory, checks
an immutable reward ID on chain, and emits a receipt. The delivery worker checks
wallet, contract, receipt, transfer, chain confirmations and canonical block;
retries are safe across lost responses and server restarts. Item delivery may
remain pending if the chain, Engine, treasury balance, or wallet is unavailable.
The event router is configured using `EVENT_REWARD_ROUTER_ADDRESS` on the server;
its API key and signing authority never go to the game or companion browser.

The current deployment is on Arbitrum Sepolia, a test network. Production launch
requires the production chain, a separate deployed and funded router, and verified
configuration. On-chain item and currency balances in this environment are test
assets.
