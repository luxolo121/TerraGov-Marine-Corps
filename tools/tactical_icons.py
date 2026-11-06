"""Rebuild pixel-native tactical HUD/overlay sprites; no generated raster artwork.

Run from the repository root with tools/bootstrap/python tools/tactical_icons.py.
HUD silhouettes leave rows 0..8 and 25..31 empty for binding text. World states
are neutral white for tinting. zone_N is a connected N/S/E/W edge mask with one
subtle, tile-seamless scanline fill, including zone_0 for a large-room interior.
"""

from pathlib import Path

from PIL import Image, ImageDraw
from PIL.PngImagePlugin import PngInfo

ROOT = Path(__file__).resolve().parents[1]
WHITE = (235, 250, 255, 255)
CYAN = (85, 215, 240, 255)
GOLD = (255, 198, 92, 255)
GREEN = (130, 239, 150, 255)
RED = (255, 126, 116, 255)
VIOLET = (204, 164, 255, 255)
UI_STATES = (
    "command", "orders", "designate", "overlay", "room", "rectangle", "patrol",
    "entrance_tool", "choke_tool", "save", "undo", "cancel", "guard",
    "fallback", "retreat", "tools", "back", "deselect",
)
WORLD_STATES = ("entrance", "choke", "waypoint", "selected", "route")


def sprite(state):
    image = Image.new("RGBA", (32, 32))
    d = ImageDraw.Draw(image)
    if state == "command":
        d.rectangle((5, 9, 26, 22), outline=CYAN, width=2)
        d.line((11, 24, 21, 24), fill=CYAN)
        d.line((16, 12, 16, 19), fill=WHITE)
        d.line((12, 16, 20, 16), fill=WHITE)
        d.rectangle((8, 12, 9, 13), fill=GOLD)
    elif state == "orders":
        d.line((8, 24, 8, 9, 23, 9, 20, 14, 8, 14), fill=GOLD, width=2)
        d.line((11, 20, 21, 20), fill=WHITE, width=2)
        d.line((18, 17, 21, 20, 18, 23), fill=WHITE, width=2)
    elif state == "designate":
        d.line((6, 14, 6, 10, 11, 10), fill=CYAN, width=2)
        d.line((21, 10, 26, 10, 26, 14), fill=CYAN, width=2)
        d.line((6, 20, 6, 24, 11, 24), fill=CYAN, width=2)
        d.line((21, 24, 26, 24, 26, 20), fill=CYAN, width=2)
        d.line((12, 17, 20, 17), fill=WHITE, width=2)
        d.line((16, 13, 16, 21), fill=WHITE, width=2)
    elif state == "overlay":
        d.line((4, 17, 10, 12, 21, 12, 27, 17, 21, 22, 10, 22, 4, 17), fill=CYAN, width=2)
        d.ellipse((12, 13, 19, 20), fill=WHITE)
        d.rectangle((15, 15, 17, 18), fill=(22, 51, 67, 255))
    elif state == "room":
        d.line((5, 23, 5, 10, 15, 10, 15, 15, 26, 15, 26, 23, 21, 23), fill=CYAN, width=2)
        d.line((5, 23, 12, 23), fill=CYAN, width=2)
        d.line((12, 23, 12, 18, 17, 23), fill=WHITE)
    elif state == "rectangle":
        d.rectangle((5, 10, 26, 23), outline=VIOLET, width=2)
        for x, y in ((4, 9), (24, 21)):
            d.rectangle((x, y, x + 3, y + 3), fill=WHITE)
        d.line((10, 19, 21, 14), fill=VIOLET)
    elif state == "patrol":
        d.line((6, 21, 15, 11, 25, 21, 6, 21), fill=GOLD, width=2)
        for x, y in ((6, 21), (15, 11), (25, 21)):
            d.ellipse((x - 2, y - 2, x + 2, y + 2), fill=WHITE)
    elif state == "entrance_tool":
        d.line((6, 23, 6, 9, 17, 9, 17, 13), fill=CYAN, width=2)
        d.line((10, 18, 27, 18, 23, 14), fill=WHITE, width=2)
        d.line((27, 18, 23, 22), fill=WHITE, width=2)
    elif state == "choke_tool":
        d.line((4, 10, 11, 15, 11, 19, 4, 24), fill=GOLD, width=2)
        d.line((27, 10, 20, 15, 20, 19, 27, 24), fill=GOLD, width=2)
        d.line((15, 11, 15, 22), fill=WHITE, width=2)
    elif state == "save":
        d.line((6, 17, 13, 23, 26, 10), fill=GREEN, width=3)
    elif state == "undo":
        d.line((6, 14, 20, 14, 24, 18, 24, 22, 17, 24), fill=GOLD, width=2)
        d.line((11, 9, 6, 14, 11, 19), fill=GOLD, width=2)
    elif state == "cancel":
        d.line((9, 10, 23, 24), fill=RED, width=3)
        d.line((23, 10, 9, 24), fill=RED, width=3)
    elif state == "guard":
        d.polygon(((7, 10), (16, 9), (25, 10), (23, 18), (16, 24), (9, 18)), outline=CYAN, width=2)
        d.line((16, 12, 16, 19), fill=WHITE, width=2)
    elif state == "fallback":
        d.line((8, 24, 8, 9, 25, 9, 20, 14, 8, 14), fill=VIOLET, width=2)
        d.line((18, 17, 13, 21, 18, 24), fill=WHITE, width=2)
        d.line((13, 21, 26, 21), fill=WHITE, width=2)
    elif state == "retreat":
        for x in (6, 16):
            d.line((x + 7, 10, x, 17, x + 7, 24), fill=RED, width=3)
    elif state == "tools":
        d.line((9, 23, 22, 10), fill=CYAN, width=4)
        d.line((18, 9, 18, 14, 23, 14, 26, 11), fill=CYAN, width=2)
        d.ellipse((6, 20, 11, 25), fill=CYAN)
        # Keep the bottom text-safe row clear.
        d.rectangle((0, 25, 31, 31), fill=(0, 0, 0, 0))
    elif state == "back":
        d.line((8, 17, 24, 17), fill=WHITE, width=3)
        d.line((15, 10, 8, 17, 15, 24), fill=WHITE, width=2)
    elif state == "deselect":
        d.ellipse((13, 9, 19, 15), outline=WHITE, width=2)
        d.line((9, 24, 9, 20, 12, 17, 20, 17, 23, 20, 23, 24), fill=WHITE, width=2)
        d.line((7, 24, 25, 9), fill=RED, width=2)
    elif state == "entrance":
        d.line((7, 20, 7, 7, 24, 7, 24, 20), fill=WHITE, width=2)
        d.line((15, 12, 15, 27), fill=WHITE, width=2)
        d.line((10, 22, 15, 27, 20, 22), fill=WHITE, width=2)
    elif state == "choke":
        d.line((4, 6, 11, 12, 11, 19, 4, 25), fill=WHITE, width=2)
        d.line((27, 6, 20, 12, 20, 19, 27, 25), fill=WHITE, width=2)
        d.line((15, 8, 15, 25), fill=WHITE)
        d.line((12, 22, 15, 25, 18, 22), fill=WHITE)
    elif state == "waypoint":
        d.ellipse((9, 9, 22, 22), outline=WHITE, width=2)
        d.ellipse((14, 14, 17, 17), fill=WHITE)
    elif state == "selected":
        for x, y, dx, dy in ((2, 2, 1, 1), (29, 2, -1, 1), (2, 29, 1, -1), (29, 29, -1, -1)):
            d.line((x, y + dy * 6, x, y, x + dx * 6, y), fill=WHITE, width=2)
    elif state == "route":
        pass  # Runtime-local, clipped arbitrary-slope raster; never an axial sprite.
    elif state.startswith("zone_"):
        mask = int(state[5:])
        d.rectangle((0, 0, 31, 31), fill=(255, 255, 255, 12))
        for y in range(1, 32, 4):
            d.line((0, y, 31, y), fill=(255, 255, 255, 34))
        for x, y in ((6, 5), (22, 13), (14, 21), (30, 29)):
            d.point((x, y), fill=(255, 255, 255, 45))
        # BYOND directions NORTH=1, SOUTH=2, EAST=4, WEST=8.
        if mask & 1:
            d.line((0, 0, 31, 0), fill=WHITE)
        if mask & 2:
            d.line((0, 31, 31, 31), fill=WHITE)
        if mask & 4:
            d.line((31, 0, 31, 31), fill=WHITE)
        if mask & 8:
            d.line((0, 0, 0, 31), fill=WHITE)
    else:
        raise ValueError(state)
    if state in UI_STATES:
        d.rectangle((0, 0, 31, 8), fill=(0, 0, 0, 0))
        d.rectangle((0, 25, 31, 31), fill=(0, 0, 0, 0))
    return image


def main():
    states = UI_STATES + WORLD_STATES + tuple(f"zone_{mask}" for mask in range(16))
    directional = {"entrance", "choke"}
    frames = []
    metadata = ["# BEGIN DMI", "version = 4.0", "\twidth = 32", "\theight = 32"]
    for name in states:
        base = sprite(name)
        if name in UI_STATES:
            assert base.crop((0, 0, 32, 9)).getbbox() is None, name
            assert base.crop((0, 25, 32, 32)).getbbox() is None, name
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
