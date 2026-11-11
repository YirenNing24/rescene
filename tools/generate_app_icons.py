#!/usr/bin/env python3
"""Rebuild outlined brand icons. Requires fonttools and cairosvg (build tools only)."""
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
import cairosvg
root=Path(__file__).resolve().parents[1]
font=TTFont(root/'assets/fonts/NimbusRoman-Italic.otf'); glyphs=font.getGlyphSet(); pen=SVGPathPen(glyphs);glyphs[font.getBestCmap()[ord('R')]].draw(pen)
r=f'<path d="{pen.getCommands()}" transform="translate(148 286) scale(.25 -.25)"/>'
# Brand artwork stays within Android's central 66dp safe zone.
mark=f'''<g fill="url(#pearl)">{r}</g>
<g fill="none" stroke="url(#orbit)" stroke-linecap="round">
<path d="M118 255 A108 108 0 0 1 286 134" stroke-width="2.5"/>
<path d="M319 181 A108 108 0 0 1 142 295" stroke-width="2.5"/>
<path d="M109 260 C150 294 295 187 326 156" stroke-width="2" opacity=".6"/>
</g>
<path d="M295 124 L301 141 L318 147 L301 153 L295 171 L289 153 L272 147 L289 141Z" fill="url(#pearl)"/>
<g fill="#dbceff"><circle cx="123" cy="279" r="3"/><circle cx="314" cy="244" r="2.5"/></g>
<g stroke="#c6b2ef" stroke-width="3.5" stroke-linecap="round"><path d="M198 310v4 M210 306v12 M222 309v6 M234 303v18 M246 308v8"/></g>'''
defs='''<defs>
<linearGradient id="pearl" x1="0" y1="0" x2=".8" y2="1"><stop stop-color="#fff9ff"/><stop offset=".45" stop-color="#eee5ff"/><stop offset="1" stop-color="#aa8cdd"/></linearGradient>
<linearGradient id="orbit" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#eee0ff"/><stop offset=".5" stop-color="#8d7cc1"/><stop offset="1" stop-color="#f7dbe9"/></linearGradient>
<radialGradient id="bg" cx=".25" cy=".1" r="1.1"><stop stop-color="#51466b"/><stop offset=".55" stop-color="#242139"/><stop offset="1" stop-color="#111223"/></radialGradient>
</defs>'''
bg='''<rect width="432" height="432" fill="url(#bg)"/>
<path d="M-40 370 C100 320 260 80 490 34" fill="none" stroke="#bba6ea" stroke-opacity=".08" stroke-width="32"/>
<path d="M-30 376 C110 330 275 80 470 50" fill="none" stroke="#e2cfff" stroke-opacity=".18" stroke-width="1.5"/>'''
def svg(body):return '<svg xmlns="http://www.w3.org/2000/svg" width="432" height="432" viewBox="0 0 432 432">'+defs+body+'</svg>\n'
assets=root/'assets/branding'
for name,body in [('launcher-foreground',mark),('launcher-background',bg),('launcher-monochrome',mark.replace('url(#pearl)','#ffffff').replace('url(#orbit)','#ffffff').replace('#dbceff','#ffffff').replace('#c6b2ef','#ffffff'))]:
 source=svg(body);(assets/(name+'.svg')).write_text(source)
 cairosvg.svg2png(bytestring=source.encode(),write_to=str(assets/(name+'.png')),output_width=432,output_height=432)
main=svg(bg+'<g transform="translate(216 216) scale(1.35) translate(-216 -216)">'+mark+'</g>')
(root/'icon.svg').write_text(main)
cairosvg.svg2png(bytestring=main.encode(),write_to=str(assets/'launcher.png'),output_width=192,output_height=192)
# Keep the companion's browser tab consistent with the game's brand.
(root/'webapp/public/favicon.svg').write_text(main)
cairosvg.svg2png(bytestring=main.encode(),write_to=str(root/'builds/rescene-icon-preview.png'),output_width=512,output_height=512)
