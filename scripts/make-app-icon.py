#!/usr/bin/env python3
"""生成探境的 App 图标与 App 内 Logo（原创绘制，无水印、无第三方素材）。

几何与配色是从上一版图标上实测拟合的（外半径 381、内半径 270、环宽 111、纯色背景 #081136、
沿环一圈 24 段采样色、内圈下缘的窄辉光与针状亮芯），中心列亮度与原图平均偏差约 5%。
观感与原来一致，但每个像素都是脚本新画的，不再带 AI 生成工具的水印。

用法：
    python3 scripts/make-app-icon.py                 # 只写预览图到桌面，不动任何文件
    python3 scripts/make-app-icon.py --install        # 用脚本绘制并替换图标集与 App 内 logo
    python3 scripts/make-app-icon.py --from 成品图.png --install
                                                      # 用外部成品图（≥1024 最佳）切片替换
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
ROOT = Path(__file__).resolve().parent.parent
ICON_SET = ROOT / "mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset"
LOGO = ROOT / "mobile/assets/logo.png"
PREVIEW = Path.home() / "Desktop/探境-图标预览.png"

BG = (0x08, 0x11, 0x36)      # 背景：实测为纯色
RING_OUTER = 381             # 外半径（实测）
RING_INNER = 270             # 内半径（实测），环宽 111
CENTER = (SIZE / 2, SIZE / 2)

# 沿环一圈的实测采样色（正上方起顺时针，每 15°；180° 那段被光柱污染，用相邻两色插值补上）
RING_PALETTE = [
    (0x74, 0xCF, 0xEC), (0x6C, 0xC0, 0xE5), (0x64, 0xAF, 0xE1), (0x5C, 0x97, 0xDA),
    (0x5C, 0x86, 0xD5), (0x66, 0x75, 0xD4), (0x72, 0x6C, 0xCC), (0x7E, 0x66, 0xCB),
    (0x86, 0x64, 0xC6), (0x8B, 0x61, 0xC7), (0x86, 0x5B, 0xC6), (0x7B, 0x58, 0xC3),
    (0x6A, 0x55, 0xC4), (0x59, 0x52, 0xC4), (0x4B, 0x5C, 0xC8), (0x42, 0x6C, 0xCB),
    (0x45, 0x84, 0xD0), (0x53, 0x9F, 0xDB), (0x60, 0xB3, 0xDF), (0x70, 0xCA, 0xE5),
    (0x7B, 0xDA, 0xEC), (0x80, 0xDD, 0xEA), (0x80, 0xDD, 0xEE), (0x7C, 0xD7, 0xEC),
]
BEAM = (0xDC, 0xD6, 0xF9)    # 光柱色（实测）


def _ring_gradient() -> Image.Image:
    """沿环一圈的角向渐变（先算小图再放大，保证平滑）。"""
    n = 512
    yy, xx = np.mgrid[0:n, 0:n]
    # 0 = 正上方，顺时针增大
    angle = (np.arctan2(xx - (n - 1) / 2, (n - 1) / 2 - yy) / (2 * np.pi)) % 1.0

    stops = np.linspace(0, 1, len(RING_PALETTE) + 1)  # 首尾同色，保证闭合
    colors = np.array([*RING_PALETTE, RING_PALETTE[0]], dtype=float)
    out = np.zeros((n, n, 3))
    for c in range(3):
        out[..., c] = np.interp(angle, stops, colors[:, c])
    return Image.fromarray(out.astype(np.uint8)).resize((SIZE, SIZE), Image.BICUBIC)


def _radial(size: int, center, radius: float) -> Image.Image:
    """白色径向遮罩：中心 255、边缘 0。"""
    yy, xx = np.mgrid[0:size, 0:size]
    d = np.sqrt((xx - center[0]) ** 2 + (yy - center[1]) ** 2) / radius
    return Image.fromarray((np.clip(1 - d, 0, 1) ** 2 * 255).astype(np.uint8))


def _blend(base: np.ndarray, alpha: np.ndarray, tint: np.ndarray) -> np.ndarray:
    """按逐像素 alpha 把 tint 叠到 base 上（都是 0~255 的浮点数组）。"""
    a = alpha[..., None]
    return base * (1 - a) + tint * a


def build_icon() -> Image.Image:
    cx, cy = CENTER
    icon = Image.new("RGB", (SIZE, SIZE), BG)

    # 圆环：外圆减内圆，填角向渐变
    mask = Image.new("L", (SIZE, SIZE), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((cx - RING_OUTER, cy - RING_OUTER, cx + RING_OUTER, cy + RING_OUTER), fill=255)
    draw.ellipse((cx - RING_INNER, cy - RING_INNER, cx + RING_INNER, cy + RING_INNER), fill=0)
    ring = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
    ring.paste(_ring_gradient(), (0, 0), mask)
    icon = Image.composite(ring, icon, mask)

    apex_y = cy + RING_INNER              # 内圈下缘

    # 1) 辉光：一根偏青的窄光柱。实测横向约 ±60px（高斯 σ≈38），
    #    纵向从内圈下缘往上约 230px 渐隐，颜色自上而下由深青蓝转为浅青白。
    xs = np.arange(SIZE)
    ys = np.arange(SIZE)
    horizontal = np.exp(-((xs - cx) ** 2) / (2 * 26.0 ** 2))
    rising = np.clip((ys - (apex_y - 205)) / 205.0, 0, 1) ** 1.5   # 向上渐隐
    cut = np.clip(((apex_y + 26) - ys) / 36.0, 0, 1)              # 顶点以下迅速收住，不能一路亮到底部
    vertical = np.minimum(rising, cut)
    halo_alpha = np.clip(np.outer(vertical, horizontal) * 1.28, 0, 1)
    glow_low = np.array([30, 70, 140], dtype=float)      # 上端：深青蓝
    glow_high = np.array([214, 246, 252], dtype=float)   # 下端：浅青白
    glow_tint = glow_low + (glow_high - glow_low) * vertical[:, None, None]
    icon = Image.fromarray(
        _blend(np.array(icon, dtype=float), halo_alpha, glow_tint).astype(np.uint8)
    )

    # 2) 针状亮芯：内圈里是近白色，进环带起转为淡紫并在环下渐隐
    needle_mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(needle_mask).rectangle((cx - 3, apex_y - 26, cx + 3, cy + RING_OUTER + 4), fill=255)
    needle_mask = np.array(needle_mask.filter(ImageFilter.GaussianBlur(2.5)), dtype=float) / 255.0
    taper = np.clip(((cy + RING_OUTER + 8) - ys) / 26.0, 0, 1)      # 实测在环下约 10px 内迅速消失
    rise = np.clip((ys - (apex_y - 30)) / 50.0, 0, 1)                # 实测最亮处在内圈下缘再往下 20px
    needle_alpha = np.outer(np.minimum(taper, rise), np.ones(SIZE)) * needle_mask * 0.95
    needle_white = np.array([255, 255, 255], dtype=float)
    needle_violet = np.array([154, 140, 225], dtype=float)
    mix = np.clip((ys - (apex_y - 26)) / float(RING_OUTER + 60), 0, 1)[:, None, None]
    needle_tint = needle_white + (needle_violet - needle_white) * mix
    icon = Image.fromarray(
        _blend(np.array(icon, dtype=float), needle_alpha, needle_tint).astype(np.uint8)
    )

    return icon


def main() -> None:
    source: Path | None = None
    if "--from" in sys.argv:
        source = Path(sys.argv[sys.argv.index("--from") + 1]).expanduser()
        if not source.is_file():
            raise SystemExit(f"找不到成品图：{source}")

    if source is not None:
        # 外部成品图：以它为准切全套尺寸（源图小于 1024 时放大，会有轻微变软）
        master = Image.open(source).convert("RGB")
        print(f"成品图 {source.name}：{master.width}×{master.height}")
        if master.width != master.height:
            raise SystemExit("成品图必须是正方形")
        if master.width < 1024:
            print(f"注意：源图只有 {master.width}px，1024 图标会由放大得到（建议提供 1024 原图）")
        icon = master.resize((SIZE, SIZE), Image.LANCZOS) if master.width != SIZE else master
    else:
        icon = build_icon().convert("RGB")  # App Store 图标不允许带 alpha 通道

    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    icon.save(PREVIEW)
    print(f"预览已写入 {PREVIEW}")

    if "--install" not in sys.argv:
        print("未替换任何文件；确认效果后加 --install 重新运行")
        return

    sizes = {
        "Icon-App-20x20@1x.png": 20, "Icon-App-20x20@2x.png": 40, "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29, "Icon-App-29x29@2x.png": 58, "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40, "Icon-App-40x40@2x.png": 80, "Icon-App-40x40@3x.png": 120,
        "Icon-App-60x60@2x.png": 120, "Icon-App-60x60@3x.png": 180,
        "Icon-App-76x76@1x.png": 76, "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167, "Icon-App-1024x1024@1x.png": 1024,
    }
    for name, px in sizes.items():
        # 比源图小的尺寸直接从源图缩，避免「先放大再缩小」损失细节
        base = master if source is not None else icon
        if source is not None and px <= base.width:
            base.resize((px, px), Image.LANCZOS).save(ICON_SET / name)
        else:
            icon.resize((px, px), Image.LANCZOS).save(ICON_SET / name)
    print(f"已替换 {len(sizes)} 个图标尺寸 -> {ICON_SET}")

    icon.resize((512, 512), Image.LANCZOS).save(LOGO)
    print(f"已替换 App 内 logo -> {LOGO}")


if __name__ == "__main__":
    main()
