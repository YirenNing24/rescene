# First Scene portraits

Original photographs copied without modification from output/cards/pulse-le-set/sources/: Woni 10.jpg, Liv 08.jpg, Minami 06.jpg, May 04.jpg, Zena 03.jpg. That set's README records the photo source and member-label cross-check. MemberCardArt uses AtlasTexture crops and a native Godot frame shared across Collection, Shop, Profile and the gameplay HUD. The separately prepared PULSE LE cards remain unchanged.

Godot imports cap the longer side at 1024 pixels and generate mipmaps. Normalized runtime crops preserve the portrait framing at that import size. The source JPGs and public metadata images retain their original resolution.

# Approved release cards

`releases/` contains all 45 approved LE composites: PULSE, Re:Scene, SCENEDROME, Glow Up, Dearest, lip bomb, Pretty Girl, Runaway and Busy Boy. Five members per release. The latest shared-border revisions and corrected portrait crops are imported without recompositing or generative edits. `provenance.json` records original paths, source/runtime checksums and dimensions. Photography is credited to THE MUZE Entertainment and the original performance-video providers; original per-set source records remain under `output/cards/`.

Run `python3 tools/integrate_card_art.py` to rebuild from the approved local masters. Uniform resize to 662×1024 and WebP quality 92 keeps game textures small; native and web assets are byte-identical. Release numeric identities are permanent and shared by the contract, backend, game and companion.
