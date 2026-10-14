"""PDF 壓縮：清除編輯器私有數據 + 圖片降採樣/JPEG 重編碼 + 結構優化。

用法: python compress.py in.pdf out.pdf [low|recommended|extreme]
"""
import io
import sys

import pikepdf
from pikepdf import Name, PdfImage
from PIL import Image, ImageChops

# 等級 -> (目標 DPI, JPEG 品質)
LEVELS = {"low": (200, 85), "recommended": (150, 75), "extreme": (96, 50)}

# 閱讀器不需要的鍵：編輯器私有數據（Illustrator/Photoshop 的 PieceInfo）、頁面縮略圖
JUNK_KEYS = ("/PieceInfo", "/Thumb")


def strip_junk(pdf, keep_metadata):
    for obj in [pdf.Root, *(p.obj for p in pdf.pages)]:
        for key in JUNK_KEYS:
            if key in obj:
                del obj[key]
    if not keep_metadata and "/Metadata" in pdf.Root:
        del pdf.Root["/Metadata"]


def recompress_image(raw, max_width, quality):
    """把一個圖片 XObject 重新編碼為 JPEG；只在變小時替換。"""
    if raw.get("/ImageMask") or raw.get("/BitsPerComponent", 8) != 8 or "/Decode" in raw:
        return 0  # 遮罩、非 8 位、自定義 Decode：不碰
    try:
        img = PdfImage(raw).as_pil_image()
    except Exception:
        return 0  # pikepdf 無法解碼的格式（如 JBIG2、特殊色彩空間）
    if img.mode not in ("RGB", "L", "CMYK"):
        return 0  # 調色板等模式轉 JPEG 容易失真
    if img.width > max_width:
        img = img.resize((max_width, round(img.height * max_width / img.width)), Image.LANCZOS)

    # PDF 閱讀器按 Adobe 約定把 CMYK JPEG 當作反相數據讀取，Pillow 寫入的是正常值，需先反相
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


def compress(src, dst, level="recommended", keep_metadata=False):
    dpi, quality = LEVELS[level]
    with pikepdf.open(src) as pdf:
        strip_junk(pdf, keep_metadata)
        pdf.remove_unreferenced_resources()

        # 以最寬頁面估算像素上限；圖片實際顯示通常更小，所以這是保守估計
        page_w_in = max(float(p.mediabox[2] - p.mediabox[0]) for p in pdf.pages) / 72
        max_width = int(page_w_in * dpi)
        # 遍歷所有對象，連 Form XObject 裡嵌套的圖片也能處理，且共享圖片只處理一次
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
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    import os

    src, dst = sys.argv[1], sys.argv[2]
    level = sys.argv[3] if len(sys.argv) > 3 else "recommended"
    compress(src, dst, level)
    a, b = os.path.getsize(src), os.path.getsize(dst)
    print(f"{src}: {a / 1e6:.2f} MB -> {dst}: {b / 1e6:.2f} MB  (-{(1 - b / a) * 100:.1f}%)")
