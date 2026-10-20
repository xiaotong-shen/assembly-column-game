"""Turn a saturn-capture run (frames.bin + ticks.txt + events.txt) into README visuals.

usage: python render.py <run-dir> <out-dir>
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from frames import load, ticks, frame_at, px, landings  # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # noqa: E402

run, out = sys.argv[1], Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
frames = load(run)
events = [line.split(maxsplit=2) for line in open(f"{run}/events.txt")]
ev = lambda name: [int(e[0]) for e in events if e[1] == name]  # noqa: E731

BG = (13, 17, 23)
FG = (230, 237, 243)
MUTED = (139, 148, 158)


def frame_img(frame, scale=10, crop=None):
    im = Image.frombytes("RGB", (32, 32), frame[1])
    if crop:
        im = im.crop(crop)
    return im.resize((im.width * scale, im.height * scale), Image.NEAREST)


# ------------------------------------------------------------- gameplay GIF
start = ev("spawn")[0]
end = frames[-1][0]
step = 40  # sample at 25 fps of virtual time
gif, durations = [], []
t = start
while t <= end:
    im = frame_img(frame_at(frames, t))
    if gif and im.tobytes() == gif[-1].tobytes():
        durations[-1] += step
    else:
        gif.append(im)
        durations.append(step)
    t += step
gif.append(frame_img(frames[-1]))  # the game-over screen
durations.append(3000)
gif = [g.quantize(colors=16, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE) for g in gif]
gif[0].save(out / "gameplay.gif", save_all=True, append_images=gif[1:], duration=durations, loop=0, optimize=True)
print("gameplay.gif", len(gif), "frames", f"{sum(durations) / 1000:.1f}s")

# ------------------------------------------------------------- stills
font = ImageFont.load_default(size=15)
pause_t = ev("pause")[0]
stills = {
    "screen-playing.png": max(t for t in ev("spawn") if t < ev("lose")[0] - 1500),
    "screen-paused.png": pause_t + 1000,
    "screen-gameover.png": end,
}
for name, t in stills.items():
    frame_img(frame_at(frames, t), scale=10).save(out / name)
    print(name, "@", t)

# ------------------------------------------------------------- chain strip
WELL = (0, 0, 10, 17)  # walls + next-piece column, rows 0..16
S = 18


def board_img(cells, marked=(), piece=None):
    """Render a reconstructed board in the same pixel style as the display."""
    im = Image.new("RGB", (32, 32), (0, 0, 0))
    for x in range(1, 9):
        im.putpixel((x, 1), (0xD3,) * 3)
        im.putpixel((x, 15), (0xD3,) * 3)
    for y in range(1, 16):
        im.putpixel((1, y), (0xD3,) * 3)
        im.putpixel((8, y), (0xD3,) * 3)
    for (x, y), c in cells.items():
        im.putpixel((x, y), ((c >> 16) & 255, (c >> 8) & 255, c & 255))
    im = im.crop(WELL).resize(((WELL[2] - WELL[0]) * S, (WELL[3] - WELL[1]) * S), Image.NEAREST)
    d = ImageDraw.Draw(im)
    for x, y in marked:
        d.rectangle([x * S - 2, y * S - 2, (x + 1) * S + 1, (y + 1) * S + 1], outline=(255, 255, 255), width=3)
    return im


clears = [L for L in landings(run) if L["steps"]]
L = max(clears, key=lambda L: (len(L["steps"]), sum(len(m) for _, m in L["steps"]), -L["t"]))
tk = ticks(run)
high = max(2, L["land"] - 5)  # show the column a few rows above where it lands
fall_x, fall_y = next(((x, y) for t, (x, y, _) in sorted(tk.items(), reverse=True) if t <= L["t"] and y <= high),
                      (L["x"], L["y"]))
falling = dict(L["board"])
falling.update({(fall_x, fall_y + k): L["piece"][k] for k in range(3)})
panels = [
    (board_img(falling), "1. Column falls"),
    (board_img(L["steps"][0][0], L["steps"][0][1]), f"2. Lands: {len(L['steps'][0][1])} in a row"),
]
if len(L["steps"]) > 1:
    panels.append((board_img(L["steps"][1][0], L["steps"][1][1]), f"3. Gems drop: chain of {len(L['steps'][1][1])}"))
panels.append((board_img(L["final"]), f"{len(panels) + 1}. Settled, +{L['score_next'] - L['score']} points"))
pw, ph = panels[0][0].size
gap, cap = 46, 34
strip = Image.new("RGB", (len(panels) * pw + (len(panels) - 1) * gap + 32, ph + cap + 24), BG)
d = ImageDraw.Draw(strip)
for i, (im, text) in enumerate(panels):
    x0 = 16 + i * (pw + gap)
    strip.paste(im, (x0, 12))
    d.text((x0 + pw / 2, 12 + ph + 18), text, fill=FG, font=font, anchor="mm")
    if i:
        ax, ay = x0 - gap / 2, 12 + ph / 2
        d.line([ax - 12, ay, ax + 10, ay], fill=MUTED, width=3)
        d.polygon([(ax + 12, ay), (ax + 3, ay - 7), (ax + 3, ay + 7)], fill=MUTED)
strip.save(out / "chain-reaction.png")
print("chain-reaction.png @", L["t"], "steps", [len(m) for _, m in L["steps"]])

# ------------------------------------------------------------- display map (SVG)
f = frame_at(frames, stills["screen-playing.png"])
U = 16  # svg px per display unit
rows = 17
ox, oy = 24, 24
W = ox + 32 * U + 300
H = oy + rows * U + 120
rects = []
for y in range(rows):
    for x in range(32):
        c = px(f, x, y)
        if c:
            rects.append(f'<rect x="{ox + x * U}" y="{oy + y * U}" width="{U}" height="{U}" fill="#{c:06x}"/>')
grid = "".join(
    f'<line x1="{ox + i * U}" y1="{oy}" x2="{ox + i * U}" y2="{oy + rows * U}"/>' for i in range(33)
) + "".join(f'<line x1="{ox}" y1="{oy + j * U}" x2="{ox + 32 * U}" y2="{oy + j * U}"/>' for j in range(rows + 1))


def box(x0, y0, x1, y1, color):
    return (f'<rect x="{ox + x0 * U - 2}" y="{oy + y0 * U - 2}" width="{(x1 - x0) * U + 4}" '
            f'height="{(y1 - y0) * U + 4}" fill="none" stroke="{color}" stroke-width="2.5" stroke-dasharray="6 4" rx="3"/>')


notes = [
    # (box, colour, label lines)
    ((2, 2, 8, 15), "#58a6ff", ["Playfield 6 × 13", "x 2–7, y 2–14"]),
    ((1, 1, 9, 16), "#a5a5a5", ["Walls #D3D3D3", "x 1 / 8, y 1 / 15"]),
    ((10, 2, 11, 5), "#3fb950", ["Next piece", "x 10, y 2–4"]),
    ((15, 3, 23, 8), "#d29922", ["Score digits", "(15, 3) and (20, 3)"]),
]
label_x = ox + 32 * U + 28
parts = []
for i, ((x0, y0, x1, y1), col, lines) in enumerate(notes):
    parts.append(box(x0, y0, x1, y1, col))
    ly = oy + 18 + i * 62
    parts.append(f'<circle cx="{label_x}" cy="{ly - 5}" r="5" fill="{col}"/>')
    parts.append(f'<text x="{label_x + 14}" y="{ly}" class="t">{lines[0]}</text>')
    parts.append(f'<text x="{label_x + 14}" y="{ly + 20}" class="m">{lines[1]}</text>')
cap_y = oy + rows * U + 34
svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" role="img" aria-label="Bitmap display layout of the Columns game">
<style>
.t {{ font: 600 15px -apple-system, 'Segoe UI', Helvetica, Arial, sans-serif; fill: #e6edf3; }}
.m {{ font: 13px ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; fill: #8b949e; }}
</style>
<rect width="100%" height="100%" rx="10" fill="#0d1117"/>
<rect x="{ox}" y="{oy}" width="{32 * U}" height="{rows * U}" fill="#000"/>
{''.join(rects)}
<g stroke="#ffffff" stroke-opacity="0.07" stroke-width="1">{grid}</g>
{''.join(parts)}
<text x="{ox}" y="{cap_y}" class="t">32 × 32 unit bitmap at 0x10008000 (top 17 rows shown)</text>
<text x="{ox}" y="{cap_y + 22}" class="m">address = 0x10008000 + y·128 + x·4    (one 0xRRGGBB word per unit)</text>
<text x="{ox}" y="{cap_y + 44}" class="m">rows 16–31: PAUSED overlay · full screen: game-over art</text>
</svg>
"""
(out / "display-map.svg").write_text(svg)
print("display-map.svg")
