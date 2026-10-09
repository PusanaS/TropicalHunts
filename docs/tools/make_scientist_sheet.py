# Makes the lab scientist's sheets (PLACEHOLDER) from BOOM's player sheets, Sprite/PsV3.png and PsVxp.png,
# without touching them: the same frames in the same places, with his orange top and mustard sash turned into
# a white lab coat, and his sword swapped for a big syringe (a glass barrel of green serum with ticks, a needle
# and a plunger) drawn straight along the blade's line from his hand. In the swing frames the sword's smears
# stay, as pale whooshes. Run it again if BOOM changes his sheets (from the project folder):
#   python3 docs/tools/make_scientist_sheet.py Sprite/PsV3.png PsVxp.png scene/design/art/scientist_PsV3.png \
#       scene/design/art/scientist_PsVxp.png /tmp/scientist_preview.png
# (Morgan's idea, 2026-10-09: level 2's lab scientist, lab_scientist.gd)
import sys, math
from PIL import Image
SRC, XP, OUT, OUTXP, PREVIEW = sys.argv[1:6]
def hx(h): return tuple(int(h[i:i+2],16) for i in (0,2,4))
SWORD_LIGHT = {hx('bdbdbd'), hx('a8a8a8')}
SWORD_DARK = {hx('797979'), hx('757575'), hx('7c6e6e')}
SWORD = SWORD_LIGHT | SWORD_DARK
FX = {hx('ebebeb'), hx('ffffff')}
RECOLOR = {
    hx('c35216'): hx('d6dee6'),   # the orange top -> the coat, shaded
    hx('d36618'): hx('f3f7fa'),   # ...lit
    hx('ccad4b'): hx('e8eef3'),   # the mustard sash -> the coat
    hx('624021'): hx('7d8a96'),   # the strap -> a grey pocket edge
}
WHOOSH = hx('e9fbff'); WHOOSH_GREEN = hx('b9f0b4')
EDGE = hx('7fb4c4'); GLASS = hx('dff8ff'); SERUM = hx('5fd15a'); SERUM_HI = hx('a6f08f'); TICK = hx('4f8796')
ROD = hx('9aa5ae'); CAP = hx('f4f7f9'); CAP_EDGE = hx('6b7680'); NEEDLE = hx('e3eaf0'); NEEDLE_DARK = hx('9aa5ae')

def process(cell, swing):
    w, h = cell.size
    px = cell.load()
    sword, body = [], []
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0: continue
            c = (r, g, b)
            if c in SWORD: sword.append((x, y))
            elif c not in FX: body.append((x, y))
    out = cell.copy(); o = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a and (r, g, b) in RECOLOR:
                o[x, y] = RECOLOR[(r, g, b)] + (a,)
            elif a and (r, g, b) in FX:
                o[x, y] = WHOOSH + (a,)
    if len(sword) < 8 or not body:
        return out
    cx = sum(p[0] for p in body) / len(body); cy = sum(p[1] for p in body) / len(body)
    bodyset = set(body)
    touching = [p for p in sword if any((p[0]+dx, p[1]+dy) in bodyset for dx in (-1,0,1) for dy in (-1,0,1))]
    pool = touching if touching else sword
    hand = min(pool, key=lambda p: (p[0]-cx)**2 + (p[1]-cy)**2)
    near = [p for p in sword if (p[0]-hand[0])**2 + (p[1]-hand[1])**2 < 22**2]
    mx = sum(p[0] for p in near) / len(near) - hand[0]; my = sum(p[1] for p in near) / len(near) - hand[1]
    n = math.hypot(mx, my) or 1.0
    dx, dy = mx / n, my / n
    def along(p): return (p[0]-hand[0])*dx + (p[1]-hand[1])*dy
    def perp(p): return abs(-(p[0]-hand[0])*dy + (p[1]-hand[1])*dx)
    axis = [p for p in sword if perp(p) < 3.0 and along(p) > 0]
    L = max([along(p) for p in axis] + [24.0])
    L = max(24.0, min(L, 50.0))
    # the blade goes; in a swing, its smears stay, as pale whooshes
    for (x, y) in sword:
        if not swing or (perp((x, y)) < 5.0 and -3.0 < along((x, y)) < L + 3.0):
            o[x, y] = (0, 0, 0, 0)
        else:
            o[x, y] = (WHOOSH if px[x, y][:3] in SWORD_LIGHT else WHOOSH_GREEN) + (255,)
    # the syringe, straight along the blade's line: a glass barrel of green serum with ticks, a needle,
    # and the plunger behind the hand
    def put(t, s, c):
        x = round(hand[0] + dx*t - dy*s); y = round(hand[1] + dy*t + dx*s)
        if 0 <= x < w and 0 <= y < h: o[x, y] = c + (255,)
    def steps(a, b, step=0.5):
        v = a
        while v <= b:
            yield v; v += step
    bl = max(14.0, L * 0.64)
    for t in steps(3.0, bl):
        for s in (-2.0, 2.0): put(t, s, EDGE)
    for t in steps(3.0, bl):
        for s in steps(-1.5, 1.5):
            fill = t < bl - 4.0
            put(t, s, (SERUM_HI if s <= -1.0 else SERUM) if fill else GLASS)
    for t in steps(5.0, bl - 2.0, 4.0): put(t, 2.0, TICK)
    for t in steps(bl, bl + 2.0):
        for s in steps(-1.0, 1.0): put(t, s, EDGE)
    for t in steps(bl + 2.5, L + 6.0): put(t, 0.0, NEEDLE)
    put(L + 6.0, 0.5, NEEDLE_DARK)
    for t in steps(-6.0, 2.0): put(t, 0.0, ROD)
    for s in steps(-3.0, 3.0):
        put(-7.0, s, CAP); put(-8.0, s, CAP_EDGE)
    for s in (-4.0, -3.0, 3.0, 4.0): put(3.0, s, ROD)
    return out

SWING_ROWS = {896, 1024, 1152, 1664, 1792, 1920, 2048}   # the attack and landing rows: their smears stay
for src, dst in ((SRC, OUT), (XP, OUTXP)):
    im = Image.open(src).convert('RGBA')
    res = Image.new('RGBA', im.size, (0, 0, 0, 0))
    for cy in range(0, im.size[1], 128):
        for cx in range(0, im.size[0], 128):
            cell = im.crop((cx, cy, cx+128, cy+128))
            if cell.getbbox() is None: continue
            res.paste(process(cell, src == SRC and cy in SWING_ROWS), (cx, cy))
    res.save(dst)

# a preview: some frames side by side, the player's above the scientist's, big
src = Image.open(SRC).convert('RGBA'); sci = Image.open(OUT).convert('RGBA')
cells = [(0,0),(128,0),(0,128),(0,256),(0,512),(0,1280),(0,1792),(128,1792),(256,1792),(0,1920),(128,1920),(0,2048),(256,2048),(384,2048),(512,2048),(128,896),(384,896),(0,1152),(128,1024)]
pv = Image.new('RGBA', (len(cells)*96, 192), (232,154,106,255))
for i,(x,y) in enumerate(cells):
    for row, sheet in enumerate((src, sci)):
        c = sheet.crop((x+16, y+16, x+112, y+112))
        pv.alpha_composite(c, (i*96, row*96))
pv = pv.resize((pv.width*2, pv.height*2), Image.NEAREST)
pv.save(PREVIEW)
