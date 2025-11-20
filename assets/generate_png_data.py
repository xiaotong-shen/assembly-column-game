from PIL import Image

# === SETTINGS ===
INPUT_IMAGE = "/Users/xiaotongshen/Desktop/github/assembly-column-game/assets/art/clearscreen.png"
OUTPUT_FILE = "pause_asset.s"       # MIPS output
SCREEN_WIDTH = 32                  # Saturn pixel width
WORD_SIZE = 4                       # bytes per pixel
BACKGROUND_COLOR = None             # (optional) only output changed pixels
# =================
# ===================


def rgb_to_hex(r, g, b):
    return (r << 16) | (g << 8) | b


def pixel_offset(x, y):
    return (y * SCREEN_WIDTH + x) * WORD_SIZE


def generate_entries():
    img = Image.open(INPUT_IMAGE).convert("RGB")
    img = img.resize((32, 32), Image.NEAREST)

    entries = []

    for y in range(32):
        for x in range(32):
            r, g, b = img.getpixel((x, y))

            if BACKGROUND_COLOR and (r, g, b) == BACKGROUND_COLOR:
                continue

            off = pixel_offset(x, y)
            col = rgb_to_hex(r, g, b)
            entries.append((off, col))

    return entries


def write_flat_asset(entries):
    with open(OUTPUT_FILE, "w") as f:
        # First: count in hex
        f.write(f"0x{len(entries):08x},\n")

        # Now each pair
        for off, col in entries:
            f.write(f"0x{off:08x}, 0x{col:06x}, ")
        f.write("\n")


if __name__ == "__main__":
    entries = generate_entries()
    write_flat_asset(entries)
    print("DONE. Count =", len(entries))