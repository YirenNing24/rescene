"""Godot 4.7.2 release template for RESCENE's GLES3, canvas-only game.

Keep advanced GUI (photo picker, dropdowns and reports), advanced Unicode text,
TLS, SVG, image decoders and MP3 playback. No game code uses physics or 3D.
"""
target = "template_release"
optimize = "size"
lto = "thin"
debug_symbols = False
disable_3d = True
disable_physics_2d = True
disable_navigation_2d = True
disable_navigation_3d = True
disable_xr = True
vulkan = False
opengl3 = True
swappy = True
modules_enabled_by_default = False
module_basis_universal_enabled = True
module_freetype_enabled = True
module_gdscript_enabled = True
module_jpg_enabled = True
module_mbedtls_enabled = True
module_mp3_enabled = True
module_msdfgen_enabled = True
module_regex_enabled = True
module_svg_enabled = True
module_text_server_adv_enabled = True
module_webp_enabled = True
