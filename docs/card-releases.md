# Release-specific LE cards

Nine permanent numeric release identities are shared by `ReleaseCards`,
`backend/card_releases.json`, `CardReleases`, and the companion catalog:

| Number | Release | Song-set ID |
| --- | --- | --- |
| 1 | PULSE | `pulse` |
| 2 | Re:Scene | `re:scene` |
| 3 | SCENEDROME | `scenedrome` |
| 4 | Glow Up | `glow_up` |
| 5 | Dearest | `dearest` |
| 6 | lip bomb | `lip_bomb` |
| 7 | Pretty Girl | `pretty_girl_-_special_single` |
| 8 | Runaway | `runaway` |
| 9 | Busy Boy | `[rescene_x_???]` |

Each release has one slot per member: Woni, Liv, Minami, May, Zena. The existing
song catalog supplies album membership; unrelated soundtrack songs have no LE
deck. Bonuses are snapshotted from confirmed ownership when a run starts and
apply only to the matching release. All five cards combine under existing caps.

Every product costs 450 STARL. Initial sale allocation is 50 per member **per
release**, enforced in the contract. Burns do not replenish it. Admin generation
and later artwork reissues remain permitted and separate from initial sales.
The trusted server samples permanent cryptographic stat/skill rolls once per
durable purchase intent. There is no client roll or VRF fee. LE rules remain
7–10% Perfect Score, Recovery 7–10, and one of six equally likely skills.

Existing `pulse_<token>` instance IDs remain stable across all releases. They
identify the common card registry, not the album. `set_id`, `template_id`,
`series`, and `art_slug` identify the artwork and compatible deck. The PULSE
templates `scene_01`–`scene_05` remain unchanged. Additional templates use
`le_<release_slug>_01`–`05`. Purchase member values encode `(release-1)*5+member`;
stored member values and deck slot indexes remain 0–4. Existing transaction ABI
and action digests remain compatible.

Level 100, refinement-only XP, decreasing level success, and guaranteed star
progression are unchanged. LE and Legendary donors are compatible across
releases. Each donor counts as one; investment is destroyed, never inherited.
Protected donors are rejected, upgraded donors require the existing warnings,
and the receiver retains its release, permanent rolls, and skill identity.

Deployment drains pending shop operations and stops the sole API writer before
closing old sales. The new registry imports existing tokens without reminting,
including levels, XP, stars, progress, revisions, locks, equipment and leases.
PULSE allocation counters are carried forward. The old router loses mint,
metadata and treasury-material permissions. No database or wallet reset occurs.
Sales only open after migration completeness. The new ABI is imported into the
engine project so existing managed-wallet purchase/upgrade execution works.

Artwork comes from the approved other-chat composites, with shared border and
corrected face crops. Native/WebP assets are byte-identical. Runtime dimensions
are 662×1024. Metadata uses versioned public artwork URLs. Provenance records
original checksums. Rebuild with `tools/integrate_card_art.py` using local masters.

Validation: all 45 products pay and mint exactly once; nine independent decks;
wrong-set rejection; migration equivalence; allocation caps; compatible donor
burns; Go/FalkorDB checkout/inventory integration; native artwork/filter checks;
web TypeScript and browser checks. Live deployment details and transaction
receipts are recorded in `contracts/deployments/release-cards-elysium.json`.

## Lobby preview and provider

Featured Scene cycles through all nine approved LE releases every 4.8 seconds,
with a five-member card fan and a short crossfade. Tapping it opens that release
in the shop. Animation pauses while the lobby is hidden or another panel is open;
retired card textures are released after each transition. Player-facing shop copy
shows card stats and availability without administrator mint/reissue details.

Elysium on the Engine and game API was restored to Alchemy on November 12, 2026
after the application network was re-enabled and chain/balance reads passed.
`node tools/repair_elysium_rpc.mjs --alchemy` restores the protected Alchemy binding
from the original private backup and verifies both services are healthy.
