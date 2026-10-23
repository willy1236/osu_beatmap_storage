"""產生 app icon 的母圖與各平台尺寸。執行：uv run --with pillow python assets/icon/generate_icon.py"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SS = 4  # supersampling 倍率，縮小時取得平滑邊緣
N = 1024 * SS


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def draw_master() -> Image.Image:
    # 對角漸層底：osu! 粉 → 紫
    top, bottom = (255, 102, 170), (122, 77, 255)
    grad = Image.new("RGB", (N, N))
    gd = ImageDraw.Draw(grad)
    for i in range(0, 2 * N, SS):
        gd.line([(i, 0), (0, i)], fill=lerp(top, bottom, i / (2 * N)), width=SS * 2)

    # 在 RGB 底圖上畫才會做 alpha blending，最後再套圓角遮罩
    d = ImageDraw.Draw(grad, "RGBA")
    c = N // 2

    def ring(r, w, fill):
        d.ellipse([c - r, c - r, c + r, c + r], outline=fill, width=w)

    # approach circle 與 hit circle
    ring(370 * SS, 18 * SS, (255, 255, 255, 110))
    d.ellipse([c - 290 * SS, c - 290 * SS, c + 290 * SS, c + 290 * SS], fill=(255, 255, 255, 45))
    ring(290 * SS, 46 * SS, (255, 255, 255, 255))

    # 下載箭頭 + 收納盤
    white = (255, 255, 255, 255)
    s = SS
    d.rounded_rectangle([c - 30 * s, c - 160 * s, c + 30 * s, c + 40 * s], radius=30 * s, fill=white)
    d.polygon([(c - 110 * s, c + 0 * s), (c + 110 * s, c + 0 * s), (c, c + 110 * s)], fill=white)
    w = 22 * s  # 收納盤線條半寬
    tray_y = c + 150 * s
    for x in (c - 150 * s, c + 150 * s):
        d.rounded_rectangle([x - w, c + 60 * s, x + w, tray_y + w], radius=w, fill=white)
    d.rounded_rectangle([c - 150 * s - w, tray_y - w, c + 150 * s + w, tray_y + w], radius=w, fill=white)

    margin = 56 * SS
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [margin, margin, N - margin, N - margin], radius=200 * SS, fill=255
    )
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    img.paste(grad, (0, 0), mask)
    return img.resize((1024, 1024), Image.LANCZOS)


def main():
    master = draw_master()
    master.save(ROOT / "assets/icon/app_icon.png")

    mac = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for size in (16, 32, 64, 128, 256, 512, 1024):
        master.resize((size, size), Image.LANCZOS).save(mac / f"app_icon_{size}.png")

    master.save(
        ROOT / "windows/runner/resources/app_icon.ico",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )


if __name__ == "__main__":
    main()
