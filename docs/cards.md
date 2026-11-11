# Individual cards and album decks

Implementation status: PULSE is deployed on Arbitrum Sepolia at `0xa9a2add390c43a521532824e75c88eeb437c10bc`. The VPS API uses it, its collection roles and mutable metadata are verified, and material IDs 11–13 have treasury stock. The initial public allocation is **50 LE cards per member (250 total)**. It is not a lifetime supply cap: artwork may be reissued and administrators may generate additional cards. Admin issuance and sacrifices do not replenish or consume the initial allocation. Existing First Scene collectibles remain cosmetic; their old listings are closed.

## Identity, rolls and ownership

Each card is a unique ERC-1155 token ID with supply one in the existing collection. Its `PulseCards` registry entry holds member, rarity, immutable base stats and skill, banked XP, level, stars and receiver sacrifice progress. Transfers retain that entry and its progress. Old owners immediately lose eligibility when confirmed ownership changes. On-chain data-URI metadata is updated atomically with refinement, star upgrades and locking; images use the existing PULSE member artwork.

The backend uses Go `crypto/rand` to roll each stat independently and choose a skill. It saves the rolls in the durable operation before submitting the purchase. Exact retries reuse the saved traits. This is trusted server randomness, not a publicly verifiable random oracle. Only LE PULSE cards are offered at launch; lower-rarity rules are prepared for later generation.

| Rarity | Perfect Score | Perfect Recovery rating | Skill chance |
| --- | --- | --- | --- |
| Common | 1–2% | 1–2 | 0% |
| Uncommon | 2–3% | 2–3 | 10% |
| Rare | 3–5% | 3–5 | 25% |
| Epic | 5–7% | 5–7 | 50% |
| Legendary | 7–10% | 7–10 | 80% |
| LE | 7–10% | 7–10 | 100% |

Integer values in each range are equally likely. When a card gets a skill, each of the six skills is equally likely. A launch LE card costs 450 STARL, starts at level 1 and 1★, and has exactly one permanent skill. Stars and refinement never reroll traits or grant a missing skill.

Perfect Score applies only to PERFECT scoring units. Recovery applies only to PERFECT note heads, never hold ticks: rating 10 restores 0.10% of max HP (1 HP on a 1,000-HP bar), rating 7 restores 0.7 HP. Normal judgment recovery is separate. Both base stats grow linearly with level, reaching +20% of the original rolled value at level 100; fixed-point arithmetic rounds down.

## Five member slots per song set

Each album has its own inventory view and five slots: Woni, Liv, Minami, May and Zena. A card must match both its member slot and song set. PULSE cards apply only to **Finest Thing, With, Inside Out, MEME and Dragon**. Other song sets currently have empty decks until their own cards exist.

All five equipped cards contribute throughout the song. Perfect Score values add up to a 60% team cap; extra Perfect Recovery adds up to 0.60% max HP per PERFECT head (6 HP). Different skills coexist; duplicate skills use the strongest equipped star rank and never multiply their triggers. The portrait carousel beside the road rotates visually every 4.5 seconds without changing which bonuses apply.

The backend freezes confirmed ownership, individual IDs, stats and skills into the energy-paid run ticket. It replays inputs using the same fixed-point rules as Godot. Ranked score remains capped at 1,000,000. Player XP and STARL rewards use the unboosted replay; card bonuses cannot inflate rewards. Cards earn **no XP from gameplay**.

## Skills by star rank

| Skill | Trigger | 1★ / 2★ / 3★ / 4★ / 5★ |
| --- | --- | --- |
| Overture | Starting fill of the first momentum bar; lost on first miss | 20 / 40 / 60 / 80 / 100% |
| Spotlight | Every 30 consecutive PERFECT note heads; bonus on that hit | +3 / 3.5 / 4 / 4.5 / 5% score |
| Second Wind | Once per song, at or below 30% HP, after consecutive PERFECT note heads | 15 / 14 / 13 / 12 / 10 heads restore 3 / 3.5 / 4 / 4.5 / 5% max HP |
| Encore | PERFECT hits during the final 20% of the song | +1 / 1.5 / 2 / 2.5 / 3% score |
| Resonance | Finish an unbroken hold/curve with a PERFECT head | +2 / 2.5 / 3 / 3.5 / 4% of that note's score, once |
| Overdrive | PERFECT hits while at 5× momentum | +0.5 / 0.75 / 1 / 1.25 / 1.5% score |

Other head judgments reset the PERFECT streak; misses reset the streak and Overture fill. Sustain ticks do not charge head streaks or generate extra recovery.

## Refinement: levels 1–100

The store materials grant card XP: Prism Shards ×10 (100 XP / 150 STARL), Resonance Cores ×3 (225 XP / 300 STARL), Aurora Catalyst (450 XP / 550 STARL). One ERC-1155 unit represents the advertised bundle. One refinement consumes one bundle, adds its XP, then attempts at most **one** level if the bank is sufficient. The cost is `20 + (current_level - 1) * 5` XP.

Success spends that XP cost and raises the level. Failure consumes the bundle, preserves the level and keeps all XP, including the new XP. Insufficient XP is banked without a level roll. Banked XP is capped at 1,000,000; level 100 rejects further refinement. The preview shows cost, odds and permanent item consumption before confirmation.

| Target level | Success chance |
| --- | --- |
| 2–10 | 100% |
| 11–20 | 90% |
| 21–30 | 80% |
| 31–40 | 70% |
| 41–50 | 60% |
| 51–60 | 50% |
| 61–70 | 40% |
| 71–80 | 30% |
| 81–90 | 25% |
| 91–100 | 20% |

The server persists a single CSPRNG roll before execution. Payment/item burn, outcome, progress and metadata commit in the contract transaction together. A probability failure is a confirmed refinement with `level_upgraded: false`, not a transaction failure.

## Guaranteed star upgrades

| Upgrade | Donors needed |
| --- | --- |
| 1★ → 2★ | 2 |
| 2★ → 3★ | 4 |
| 3★ → 4★ | 6 |
| 4★ → 5★ | 8 |

LE accepts LE or Legendary; Legendary accepts either as well. Lower rarities accept only the same rarity. Each donor contributes exactly **one**, regardless of member, level, XP, stars, skill or partial progress. The donor is burned permanently and transfers none of its investment. Partial progress belongs only to the receiver.

Upgrades never fail or downgrade. Excess donors and already-maxed receivers are allowed after an explicit warning that excess gives no benefit. Advanced donors also show an investment-loss warning. Duplicate donors, self-sacrifice, and locked, equipped, listed or in-use donors are rejected. Locks can be changed explicitly by the owner; they never silently unlock a donor.

## Authoritative actions and reservations

- `GET /api/v1/inventory`: confirmed owned individual cards, per-card stats/progress/protection and album decks.
- `POST /api/v1/collection/quote`: read-only preview for `refine`, `star`, `lock` or `equip`.
- `POST /api/v1/collection/action`: submit the quoted immutable intent with `request_id`, `quote_hash` and explicit warning acknowledgment.
- Existing shop purchase route: chosen member or material purchase, with exact server price and quantity validation.

The existing FalkorDB ShopOperation outbox pins the router, actor, ownership/revision, operands, saved random outcome and digest. Engine queues do not count as success: the worker verifies canonical confirmed receipts, exact payment and ERC-1155 mint/delivery/burn logs. A missing HTTP response is recovered from on-chain action digests and logs. Reusing an ID with a changed payload is rejected.

Global FalkorDB reservations cover pending operations until a terminal result. Run reservations cover the frozen deck for up to two hours and release on completion or abandonment, including failures and leaving gameplay; energy is not refunded. Ownership transfers cannot bypass a card's active reservation through another account. Contract protection hooks also support locked, equipped, listed and time-bounded in-use flags. External marketplace listing integrations must maintain listing protection explicitly.

## Deployment configuration

The deployed `PulseCardsLaunch` binds VERSION 2 to the existing STARL, treasury/operator, ERC-1155 collection and material IDs 11/12/13. The public initial allocation is 50/member; it does not constrain future admin generation. `PULSE_CARDS_ADDRESS` is enabled in the private VPS environment and optional/blank in `.env.example` for isolated local development. The previous `PulseItemShop` draft and live cosmetic `MemberCardShop` are not compatible substitutes.

Reserve existing product IDs 6–10 before allocating stock at material IDs 11–13; unique card IDs then come from the collection's next unused ID. Grant the new router `MINTER_ROLE` and `METADATA_ROLE` on the collection, ensure its URI is not frozen, approve the router to deliver treasury material stock, and import its ABI into Engine. The server validates immutable bindings, roles, material IDs, version and the 450-STARL unit price before writes. Buyer wallets approve exact STARL amounts and, when required, the collection burn operator through Engine-managed signing; gas provisioning uses the existing bounded drink router.

Publish the deferred LE supply and reissue rules and implement the corresponding launch constraints before enabling sales. Nothing in the current configuration claims an enforced public LE supply cap.

## Validation

Foundry tests cover unique mint/payment, retries, refinement outcomes and level cap, sacrifice accounting and protections, transfer continuity, metadata updates and atomic rollback. Go/FalkorDB tests cover server quotes, durable random rolls, exact receipts, account conflicts, global reservations, album restrictions and combined teams. Native tests exercise quoted intents after a lost response/restart, refinement failures, warnings, all five slots and the carousel. Golden fixtures compare Godot and Go scores, per-hit skills and real replay inputs. Screenshots in `previews/pulse-*.png` are native renders with test inventory, not evidence of live minting.

## Live verification

`output/pulse-live-verification.json` records the dedicated testnet QA flow: confirmed STARL debit and unique delivery, idempotent purchase retry, material purchase/burn, refinement to level 2, two donors burned for a 2-star receiver, album-slot equipment, and one-use energy restoration with replay rejection. One Woni card was purchased from its initial allocation during QA; two additional donor cards were generated administratively and sacrificed. The initial public stock is therefore 49 Woni and 50 for each other member when no other sales have occurred.
