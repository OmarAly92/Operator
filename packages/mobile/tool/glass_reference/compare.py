import sys
from PIL import Image, ImageChops, ImageDraw, ImageStat

STRIP = 450


def label(img, text):
    draw = ImageDraw.Draw(img)
    draw.rectangle([0, 0, 300, 64], fill=(0, 0, 0))
    draw.text((14, 12), text, fill=(255, 255, 255), font_size=40)
    return img


def mad(a, b):
    return sum(ImageStat.Stat(ImageChops.difference(a, b)).mean) / 3


def main(native_path, lab_path, out_path):
    native = Image.open(native_path).convert("RGB")
    lab = Image.open(lab_path).convert("RGB").resize(native.size)
    w, h = native.size
    diff = ImageChops.difference(native, lab).point(lambda v: min(255, v * 4))
    sheet = Image.new("RGB", (w * 3, h), (128, 128, 128))
    for i, panel in enumerate([label(native.copy(), "native"), label(lab.copy(), "lab"), label(diff, "diff x4")]):
        sheet.paste(panel, (i * w, 0))
    sheet.resize((w * 3 // 2, h // 2)).save(out_path)
    zoom = Image.new("RGB", (w * 2, STRIP * 2), (128, 128, 128))
    for i, img in enumerate([native, lab]):
        zoom.paste(img.crop((0, 0, w, STRIP)), (i * w, 0))
        zoom.paste(img.crop((0, h - STRIP, w, h)), (i * w, STRIP))
    zoom.save(out_path.replace(".png", "_zoom.png"))
    top = mad(native.crop((0, 0, w, STRIP)), lab.crop((0, 0, w, STRIP)))
    bottom = mad(native.crop((0, h - STRIP, w, h)), lab.crop((0, h - STRIP, w, h)))
    print(f"top_mad={top:.2f} bottom_mad={bottom:.2f}")


if __name__ == "__main__":
    main(*sys.argv[1:4])
