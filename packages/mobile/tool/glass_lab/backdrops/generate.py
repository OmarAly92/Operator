import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

WIDTH = 1206
HEIGHT = 2622
STRIPES = [0xE5484D, 0xE89527, 0xF0B45C, 0x1ACB64, 0x47BFFF, 0x8E6CF0]
WORDS = (
    "agent session branch terminal glass render commit merge review desktop pairing tunnel "
    "prompt model harness spawn build test layer shader spring detent sheet toolbar capsule "
    "lens refraction blur tint shadow scroll edge motion frame pixel native measure"
).split()
FONT = Path(__file__).resolve().parents[3] / "assets/fonts/anthropic_sans/AnthropicSansText-400.otf"


def rgb(value):
    return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)


def stripes():
    image = Image.new("RGB", (WIDTH, HEIGHT))
    draw = ImageDraw.Draw(image)
    band = WIDTH / len(STRIPES)
    for index, color in enumerate(STRIPES):
        draw.rectangle([round(index * band), 0, round((index + 1) * band) - 1, HEIGHT], fill=rgb(color))
    return image


def photo(height=HEIGHT, seed=7):
    rng = np.random.default_rng(seed)
    y, x = np.mgrid[0:height, 0:WIDTH].astype(np.float32)
    top = np.array([40, 70, 140], np.float32)
    bottom = np.array([230, 150, 90], np.float32)
    t = (y / height)[..., None]
    canvas = top * (1 - t) + bottom * t
    for _ in range(14):
        cx, cy = rng.uniform(0, WIDTH), rng.uniform(0, height)
        radius = rng.uniform(140, 520)
        color = rng.uniform(0, 255, 3).astype(np.float32)
        weight = np.exp(-(((x - cx) ** 2 + (y - cy) ** 2) / (2 * radius**2)))[..., None] * rng.uniform(0.5, 0.9)
        canvas = canvas * (1 - weight) + color * weight
    canvas += rng.normal(0, 6, canvas.shape).astype(np.float32)
    image = Image.fromarray(np.clip(canvas, 0, 255).astype(np.uint8))
    draw = ImageDraw.Draw(image)
    for index in range(28):
        cx, cy = rng.uniform(0, WIDTH), rng.uniform(0, height)
        w, h = rng.uniform(40, 260), rng.uniform(40, 260)
        color = tuple(int(c) for c in rng.uniform(0, 255, 3))
        box = [cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2]
        if index % 2:
            draw.ellipse(box, fill=color)
        else:
            draw.rectangle(box, fill=color)
    return image


def flat(color, height=HEIGHT):
    return Image.new("RGB", (WIDTH, height), color)


def text(height=HEIGHT, seed=11):
    rng = np.random.default_rng(seed)
    image = Image.new("RGB", (WIDTH, height), (255, 255, 255))
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(str(FONT), 51)
    margin, line, y = 48, 66, 150
    while y < height - line:
        words, x = [], margin
        while True:
            word = WORDS[rng.integers(len(WORDS))]
            width = draw.textlength(word + " ", font=font)
            if x + width > WIDTH - margin:
                break
            words.append(word)
            x += width
        draw.text((margin, y), " ".join(words), fill=(0, 0, 0), font=font)
        y += line
        if rng.random() < 0.18:
            y += line
    return image


def scroll():
    image = Image.new("RGB", (WIDTH, HEIGHT * 3))
    image.paste(text(), (0, 0))
    image.paste(photo(), (0, HEIGHT))
    image.paste(flat((255, 255, 255), HEIGHT // 2), (0, HEIGHT * 2))
    image.paste(flat((0, 0, 0), HEIGHT - HEIGHT // 2), (0, HEIGHT * 2 + HEIGHT // 2))
    return image


def main(out):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    backdrops = {
        "stripes": stripes(),
        "photo": photo(),
        "white": flat((255, 255, 255)),
        "black": flat((0, 0, 0)),
        "text": text(),
        "scroll": scroll(),
    }
    for name, image in backdrops.items():
        image.save(out / f"{name}.png", optimize=True)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent)
