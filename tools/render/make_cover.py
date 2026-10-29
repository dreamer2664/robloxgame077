#!/usr/bin/env python3
"""Builds screenshots/00_cover.png: a contact sheet of the shipping renders."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
SHOTS = ROOT / "screenshots"


def font(size, bold=False):
    for directory in ("/usr/share/fonts/truetype/dejavu", "/usr/share/fonts/truetype/liberation"):
        name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
        p = Path(directory) / name
        if p.exists():
            return ImageFont.truetype(str(p), size)
    return ImageFont.load_default()


W, H = 1920, 1080
cover = Image.new("RGB", (W, H), (4, 10, 16))

hero = Image.open(SHOTS / "01_reef_nave.png").convert("RGB")
hero = hero.resize((W, int(W * hero.height / hero.width)))
cover.paste(hero.crop((0, 0, W, H)), (0, 0))

# darken for legibility
shade = Image.new("RGBA", (W, H), (2, 8, 14, 150))
cover = Image.alpha_composite(cover.convert("RGBA"), shade)

thumbs = ["05_hub_island.png", "02_reef_chancel.png", "07_pulse_and_flare.png", "11_ui_ledger_panel.png"]
tw, th = 430, 242
gap = 18
x0 = W - (tw * 2 + gap) - 44
y0 = H - (th * 2 + gap) - 44
for i, name in enumerate(thumbs):
    img = Image.open(SHOTS / name).convert("RGB")
    img = img.resize((tw, th))
    cx = x0 + (i % 2) * (tw + gap)
    cy = y0 + (i // 2) * (th + gap)
    cover.paste(img, (cx, cy))
    d = ImageDraw.Draw(cover, "RGBA")
    d.rectangle([cx, cy, cx + tw, cy + th], outline=(47, 216, 200, 130), width=2)

d = ImageDraw.Draw(cover, "RGBA")
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse([60, 250, 900, 700], fill=(40, 160, 160, 46))
glow = glow.filter(ImageFilter.GaussianBlur(120))
cover = Image.alpha_composite(cover, glow)
d = ImageDraw.Draw(cover, "RGBA")

d.text((86, 300), "ECHOWAKE", font=font(132, True), fill=(226, 242, 248, 255))
d.text((92, 452), "Rekindle the drowned city.", font=font(34), fill=(155, 246, 216, 255))
lines = [
    "A co-op light-management dive through a flooded cathedral-reef.",
    "",
    "Your lantern is your health, your ammunition and your only way to see.",
    "The pulse that reveals what is hunting you also calls it to your side.",
    "Relight three beacons before the tide turns \u2014 or lose half of what you carry.",
]
y = 540
for line in lines:
    d.text((92, y), line, font=font(26), fill=(198, 220, 232, 235))
    y += 40

d.text((92, 800), "1\u20136 players  \u00b7  5-minute tides  \u00b7  5 upgrades  \u00b7  3 Gloam archetypes", font=font(24), fill=(126, 150, 166, 255))
d.text((92, 1030), "Renders generated from the shipped layout data (tools/render)",
       font=font(19), fill=(110, 132, 148, 220))

cover.convert("RGB").save(SHOTS / "00_cover.png", quality=93)
print("wrote screenshots/00_cover.png")
