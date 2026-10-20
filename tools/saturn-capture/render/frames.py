import struct
N = 32*32*3
def load(run):
    data = open(f"{run}/frames.bin","rb").read()
    out=[]
    for i in range(0, len(data), 4+N):
        t = struct.unpack("<I", data[i:i+4])[0]
        out.append((t, data[i+4:i+4+N]))
    return out
def px(frame, x, y):
    o = (y*32+x)*3; b = frame[1]
    return (b[o]<<16)|(b[o+1]<<8)|b[o+2]
def well(frame):
    return {(x,y):px(frame,x,y) for x in range(2,8) for y in range(2,15) if px(frame,x,y)}

def ticks(run):
    out = {}
    for line in open(f"{run}/ticks.txt"):
        t, x, y, s = map(int, line.split())
        out[t] = (x, y, s)
    return out

def frame_at(frames, t):
    best = frames[0]
    for f in frames:
        if f[0] <= t: best = f
    return best

def split(frame, x, y):
    """board (dict of settled gems) and the falling piece colours"""
    b = well(frame)
    piece = [b.pop((x, y + k), 0) for k in range(3)]
    return b, piece

def top(b, x):
    return min([y for (cx, y) in b if cx == x] + [15])

def resolve(b):
    """Same rules as columns.asm: any 3-in-a-row (h/v/diagonals) clears, gems fall, repeat.
    Returns list of (board_before_clear, marked_cells) per chain step, and final board."""
    steps = []
    b = dict(b)
    while True:
        marked = set()
        for (x, y), c in b.items():
            for dx, dy in ((1,0),(0,1),(1,1),(-1,1)):
                if b.get((x+dx, y+dy)) == c and b.get((x+2*dx, y+2*dy)) == c:
                    marked |= {(x, y), (x+dx, y+dy), (x+2*dx, y+2*dy)}
        if not marked:
            return steps, b
        steps.append((dict(b), marked))
        nb = {}
        for x in range(2, 8):
            col = [b[(x, y)] for y in range(2, 15) if (x, y) in b and (x, y) not in marked]
            for i, c in enumerate(reversed(col)):
                nb[(x, 14 - i)] = c
        b = nb

def landings(run):
    fr, tk = load(run), ticks(run)
    ts = sorted(tk)
    for a, nxt in zip(ts, ts[1:]):
        (x, y, s), (_, y2, s2) = tk[a], tk[nxt]
        if y2 < y:  # piece landed between these ticks, a new one spawned
            f = frame_at(fr, a)
            board, piece = split(f, x, y)
            land = top(board, x) - 3
            placed = dict(board); placed.update({(x, land + k): piece[k] for k in range(3)})
            steps, final = resolve(placed)
            yield dict(t=a, t_next=nxt, x=x, y=y, land=land, board=board, piece=piece,
                       placed=placed, steps=steps, final=final, score=s, score_next=s2)
