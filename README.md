# compressPDF

A high-quality PDF compressor. It only recompresses images and strips redundant data, leaving text and vector graphics untouched — so the compressed PDF **still opens and edits normally in Adobe Illustrator**.

Two ways to use it: the command-line script `compress.py`, or a macOS app with a Liquid Glass interface.

## What it does

1. **Strips editor private data**: the `/PieceInfo` that Illustrator saves with "Preserve Illustrator Editing Capabilities", page thumbnails, and XMP metadata. For PDFs exported from Illustrator, this is usually most of the file size.
2. **Downsamples images and re-encodes them as JPEG**: the pixel limit is derived from the page width, and an image is only replaced if the result is smaller. CMYK images are written inverted, following the Adobe convention.
3. **Optimizes structure**: recompresses all streams with Flate, generates object streams, and removes unreferenced resources.

| Level | Target DPI | JPEG quality |
|---|---|---|
| low | 200 | 85 |
| recommended (default) | 150 | 75 |
| extreme | 96 | 50 |

> **Why not PDFKit / Quartz?** PDFs rewritten by Quartz (including those edited in Preview) lose the fonts' `WinAnsiEncoding` and have their shading functions rewritten. In Illustrator, text then shows up as garbled characters and an "unknown shading type" warning appears. This tool uses [pikepdf](https://github.com/pikepdf/pikepdf) to modify the object structure directly, so everything it doesn't touch is preserved as-is.

## macOS app

Download `PDF-Compressor-1.0.0-macOS-arm64.zip` from [Releases](https://github.com/WenzyWong/compressPDF/releases) and unzip it. The first time you open it, right-click the app and choose **Open** (it is ad-hoc signed and not notarized).

- Drag PDFs into the window, click to choose files, or use **Open With** in Finder
- Output is saved next to the original as `xxx-compressed.pdf`
- Bundles its own standalone Python runtime — nothing else to install
- Requires macOS 26+ on Apple Silicon

### Building from source

```bash
PDFCompressor/build_app.sh   # outputs PDFCompressor/build/PDF 壓縮.app
```

Requires Xcode or the Command Line Tools (Swift 6.2+). The first build downloads [python-build-standalone](https://github.com/astral-sh/python-build-standalone) (verified by SHA-256) and installs pikepdf and Pillow into it.

## Command line

```bash
pip install pikepdf pillow
python compress.py in.pdf out.pdf [low|recommended|extreme]
```
