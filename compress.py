"""PDF 压缩：清除编辑器私有数据 + 图片降采样/JPEG 重编码 + 结构优化。

用法: python compress.py in.pdf out.pdf [等级] [--dpi N] [--quality N]
等级: lossless | high | low | recommended | small | extreme（默认 recommended）
"""
import argparse
import io
import os

import pikepdf
from pikepdf import Name, PdfImage
from PIL import Image, ImageChops

# 等级 -> (目标 DPI, JPEG 质量)；lossless 只清理数据和优化结构，不动图片
LEVELS = {
    "lossless": (None, None),
    "high": (300, 90),
    "low": (200, 85),
    "recommended": (150, 75),
    "small": (120, 60),
    "extreme": (96, 50),
}

# 阅读器不需要的键：编辑器私有数据（Illustrator/Photoshop 的 PieceInfo）、页面缩略图
JUNK_KEYS = ("/PieceInfo", "/Thumb")


def strip_junk(pdf, keep_metadata):
    for obj in [pdf.Root, *(p.obj for p in pdf.pages)]:
        for key in JUNK_KEYS:
            if key in obj:
                del obj[key]
    if not keep_metadata and "/Metadata" in pdf.Root:
        del pdf.Root["/Metadata"]


def recompress_image(raw, max_width, quality):
    """把一个图片 XObject 重新编码为 JPEG；只在变小时替换。"""
    if raw.get("/ImageMask") or raw.get("/BitsPerComponent", 8) != 8 or "/Decode" in raw:
        return 0  # 遮罩、非 8 位、自定义 Decode：不碰
    try:
        img = PdfImage(raw).as_pil_image()
    except Exception:
        return 0  # pikepdf 无法解码的格式（如 JBIG2、特殊色彩空间）
    if img.mode not in ("RGB", "L", "CMYK"):
        return 0  # 调色板等模式转 JPEG 容易失真
    if img.width > max_width:
        img = img.resize((max_width, round(img.height * max_width / img.width)), Image.LANCZOS)

    # PDF 阅读器按 Adobe 约定把 CMYK JPEG 当作反相数据读取，Pillow 写入的是正常值，需先反相
    out = ImageChops.invert(img) if img.mode == "CMYK" else img
    buf = io.BytesIO()
    out.save(buf, "JPEG", quality=quality, optimize=True)
    old_size = len(raw.read_raw_bytes())
    if buf.tell() >= old_size:
        return 0

    raw.write(buf.getvalue(), filter=Name.DCTDecode)
    raw.Width, raw.Height = img.width, img.height
    raw.ColorSpace = {"RGB": Name.DeviceRGB, "L": Name.DeviceGray, "CMYK": Name.DeviceCMYK}[img.mode]
    if "/DecodeParms" in raw:
        del raw["/DecodeParms"]
    return old_size - buf.tell()


def compress(src, dst, level="recommended", keep_metadata=False, dpi=None, quality=None):
    """dpi / quality 传入时覆盖等级的预设值。"""
    level_dpi, level_quality = LEVELS[level]
    dpi, quality = dpi or level_dpi, quality or level_quality
    saved = 0
    with pikepdf.open(src) as pdf:
        strip_junk(pdf, keep_metadata)
        pdf.remove_unreferenced_resources()

        if dpi and quality:
            # 以最宽页面估算像素上限；图片实际显示通常更小，所以这是保守估计
            page_w_in = max(float(p.mediabox[2] - p.mediabox[0]) for p in pdf.pages) / 72
            max_width = int(page_w_in * dpi)
            # 遍历所有对象，连 Form XObject 里嵌套的图片也能处理，且共享图片只处理一次
            saved = sum(
                recompress_image(obj, max_width, quality)
                for obj in pdf.objects
                if isinstance(obj, pikepdf.Stream) and obj.get("/Subtype") == Name.Image
            )

        pdf.save(
            dst,
            compress_streams=True,
            recompress_flate=True,
            object_stream_mode=pikepdf.ObjectStreamMode.generate,
        )
    return saved


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("src")
    parser.add_argument("dst")
    parser.add_argument("level", nargs="?", default="recommended", choices=LEVELS)
    parser.add_argument("--dpi", type=int, help="图片目标 DPI（覆盖等级预设）")
    parser.add_argument("--quality", type=int, help="JPEG 质量 1-95（覆盖等级预设）")
    args = parser.parse_args()
    if (args.dpi is None) != (args.quality is None) and args.level == "lossless":
        parser.error("lossless 等级下需同时指定 --dpi 和 --quality")

    compress(args.src, args.dst, args.level, dpi=args.dpi, quality=args.quality)
    a, b = os.path.getsize(args.src), os.path.getsize(args.dst)
    print(f"{args.src}: {a / 1e6:.2f} MB -> {args.dst}: {b / 1e6:.2f} MB  (-{(1 - b / a) * 100:.1f}%)")
