"""Rebuild the small pixel-native tactical HUD/overlay sprite sheet.

Run from the repository root with tools/bootstrap/python tools/tactical_icons.py.
Overlay states are neutral white so the game can tint them per plan/selection.
"""

from pathlib import Path

from PIL import Image, ImageDraw
from PIL.PngImagePlugin import PngInfo


ROOT = Path(__file__).resolve().parents[1]
WHITE = (235, 250, 255, 255)
CYAN = (85, 215, 240, 255)
DARK = (16, 38, 52, 255)
GOLD = (255, 198, 92, 255)


def sprite(state):
    image = Image.new("RGBA", (32, 32))
    d = ImageDraw.Draw(image)
    if state == "command":
        # Command board and three unit chevrons, deliberately not a terrain map.
        d.rectangle((4, 4, 27, 26), fill=DARK, outline=CYAN, width=2)
        d.line((7, 10, 24, 10), fill=WHITE)
        for x, y in ((10, 16), (20, 16), (15, 23)):
            d.line((x - 3, y, x, y - 3, x + 3, y), fill=GOLD, width=2)
        d.line((15, 12, 15, 18), fill=CYAN)
    elif state == "orders":
        for y in (10, 17, 24):
            d.line((7, y, 15, y - 5, 24, y), fill=GOLD, width=2)
    elif state == "designate":
        d.polygon(((16, 4), (27, 15), (16, 26), (5, 15)), outline=CYAN, width=2)
        d.line((16, 9, 16, 21), fill=WHITE, width=2)
        d.line((10, 15, 22, 15), fill=WHITE, width=2)
    elif state == "overlay":
        for y in (21, 16, 11):
            d.line((4, y, 15, y + 6, 27, y, 15, y - 6, 4, y), fill=CYAN, width=2)
    elif state == "zone":
        d.rectangle((2, 2, 29, 29), outline=WHITE)
        for x, y, dx, dy in ((2, 2, 1, 1), (29, 2, -1, 1), (2, 29, 1, -1), (29, 29, -1, -1)):
            d.line((x, y + dy * 5, x, y, x + dx * 5, y), fill=WHITE, width=2)
    elif state == "entrance":
        # South-facing doorway and approach arrow; directional variants rotate.
        d.line((7, 20, 7, 7, 24, 7, 24, 20), fill=WHITE, width=2)
        d.line((15, 12, 15, 27), fill=WHITE, width=2)
        d.line((10, 22, 15, 27, 20, 22), fill=WHITE, width=2)
    elif state == "choke":
        d.line((4, 6, 11, 12, 11, 19, 4, 25), fill=WHITE, width=2)
        d.line((27, 6, 20, 12, 20, 19, 27, 25), fill=WHITE, width=2)
        d.line((15, 8, 15, 25), fill=WHITE)
        d.line((12, 22, 15, 25, 18, 22), fill=WHITE)
    elif state == "waypoint":
        d.ellipse((8, 8, 23, 23), outline=WHITE, width=2)
        d.ellipse((14, 14, 17, 17), fill=WHITE)
    elif state == "selected":
        for x, y, dx, dy in ((2, 2, 1, 1), (29, 2, -1, 1), (2, 29, 1, -1), (29, 29, -1, -1)):
            d.line((x, y + dy * 6, x, y, x + dx * 6, y), fill=WHITE, width=2)
    elif state == "boundary":
        d.line((1, 30, 30, 30), fill=WHITE, width=2)
        d.line((2, 27, 2, 30, 29, 30, 29, 27), fill=WHITE)
    elif state == "route":
        for y in range(1, 32, 7):
            d.line((15, y, 15, min(y + 3, 31)), fill=WHITE, width=2)
    else:
        raise ValueError(state)
    return image


def main():
    states = ("command", "orders", "designate", "overlay", "zone", "entrance", "choke", "waypoint", "selected", "boundary", "route")
    directional = {"entrance", "choke", "boundary", "route"}
    frames = []
    metadata = ["# BEGIN DMI", "version = 4.0", "\twidth = 32", "\theight = 32"]
    for name in states:
        base = sprite(name)
        metadata += [f'state = "{name}"', f'\tdirs = {4 if name in directional else 1}', "\tframes = 1"]
        # BYOND DMI cardinal order: SOUTH, NORTH, EAST, WEST.
        frames += [base.rotate(angle) for angle in ((0, 180, 90, 270) if name in directional else (0,))]
    metadata.append("# END DMI")
    sheet = Image.new("RGBA", (32 * 8, 32 * ((len(frames) + 7) // 8)))
    for index, frame in enumerate(frames):
        sheet.paste(frame, ((index % 8) * 32, (index // 8) * 32))
    pnginfo = PngInfo()
    pnginfo.add_text("Description", "\n".join(metadata) + "\n")
    path = ROOT / "icons/mob/tactical_command.dmi"
    sheet.save(path, format="PNG", pnginfo=pnginfo)
    print(f"Wrote {path.relative_to(ROOT)}: {len(states)} states, {len(frames)} frames")


if __name__ == "__main__":
    main()
