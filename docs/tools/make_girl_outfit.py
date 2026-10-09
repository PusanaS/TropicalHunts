# Makes the customer's level 2 outfit (PLACEHOLDER) from Violeta's girl-Sheet.png, without touching it: the
# same 4 idle frames, her pale long-sleeved jacket turned into a sleeveless red sundress (its sleeves become
# bare arms), her green scarf top the dress's bodice, her hat a black wide brim, her flower a red hibiscus, her
# purse straw and its strap gold (Morgan's call, 2026-10-09: "a different outfit for level 2"). Violeta would draw the
# real one. Run it again if her sheet changes (from the project folder):
#   python3 docs/tools/make_girl_outfit.py girl-Sheet.png scene/design/art/girl_level2.png /tmp/girl_preview.png
import sys
from PIL import Image
SRC, OUT, PREVIEW = sys.argv[1:4]
def hx(h): return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))
SKIN, SKIN_SHADE = hx('ecded9'), hx('d3bdbd')
JACKET = {hx('bcc9ca'), hx('cbd5d0'), hx('d7ddd6')}
SCARF = {hx('66956d'), hx('b4c8b7')}
RECOLOR = {
    hx('66956d'): hx('c8303e'),   # the scarf top -> the bodice, red
    hx('b4c8b7'): hx('f06a6a'),   # ...its light
    hx('bcc9ca'): hx('b02a3a'),   # the jacket -> the dress, shaded
    hx('cbd5d0'): hx('d8384a'),   # ...lit
    hx('d7ddd6'): hx('f06a6a'),   # ...its highlight
    hx('817969'): hx('2e2430'),   # the hat -> a black wide brim (cream blended into her light hair)
    hx('c3b9a4'): hx('4a3a48'),   # its brim's edge (the purse, the same colour, is done below)
    hx('aca28d'): hx('cdb27a'),   # the purse's shade
    hx('b6668c'): hx('e8384a'),   # the flower -> a red hibiscus
    hx('acb4b6'): hx('e0b84a'),   # the strap and earring -> gold
    hx('777f81'): hx('b08a2a'),
}

def outfit(cell):
    w, h = cell.size
    px = cell.load()
    scarf = [x for y in range(h) for x in range(w) if px[x, y][3] and px[x, y][:3] in SCARF]
    out = cell.copy()
    o = out.load()
    cx = (min(scarf) + max(scarf)) / 2.0 if scarf else w / 2.0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if not a:
                continue
            c = (r, g, b)
            if c in JACKET and (x < cx - 7 or x > cx + 6):
                # a sleeve: a bare arm now, shaded along its edges
                edge = any(not px[x + dx, y][3] or px[x + dx, y][:3] not in JACKET for dx in (-1, 1) if 0 <= x + dx < w)
                o[x, y] = (SKIN_SHADE if edge else SKIN) + (a,)
            elif c == hx('c3b9a4') and y > 60:
                o[x, y] = hx('f4e6c0') + (a,)            # the purse (low down): pale straw
            elif c in RECOLOR:
                o[x, y] = RECOLOR[c] + (a,)
    return out

im = Image.open(SRC).convert('RGBA')
res = Image.new('RGBA', im.size, (0, 0, 0, 0))
for i in range(im.size[0] // 128):
    res.paste(outfit(im.crop((i * 128, 0, i * 128 + 128, 128))), (i * 128, 0))
res.save(OUT)
pv = Image.new('RGBA', (8 * 52, 70), (232, 154, 106, 255))
for i in range(4):
    for row, sheet in enumerate((im, res)):
        pv.alpha_composite(sheet.crop((i * 128 + 38, 30, i * 128 + 88, 100)), ((row * 4 + i) * 52, 0))
pv.resize((pv.width * 4, pv.height * 4), Image.NEAREST).save(PREVIEW)
