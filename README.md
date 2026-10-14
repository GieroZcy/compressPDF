# compressPDF

高質量 PDF 壓縮工具，思路類似 iLovePDF：只壓縮圖片和清除冗餘數據，不改動文字與向量，壓縮後的 PDF **仍可在 Adobe Illustrator 中正常打開編輯**。

提供兩種用法：命令行腳本 `compress.py`，以及帶液態玻璃界面的 macOS app。

## 壓縮做了什麼

1. **清除編輯器私有數據**：Illustrator「保留編輯功能」存下的 `/PieceInfo`、頁面縮略圖、XMP 元數據。對 Illustrator 導出的 PDF，這通常是體積的大頭。
2. **圖片降採樣 + JPEG 重編碼**：按頁寬換算像素上限，只在變小時才替換；CMYK 圖片按 Adobe 約定反相寫入。
3. **結構優化**：重新 Flate 壓縮所有流、生成對象流、刪除未引用資源。

| 等級 | 目標 DPI | JPEG 品質 |
|---|---|---|
| low | 200 | 85 |
| recommended（默認） | 150 | 75 |
| extreme | 96 | 50 |

> 為什麼不用 PDFKit / Quartz？經 Quartz 重寫的 PDF（包括「預覽」編輯過的）會丟失字體的 `WinAnsiEncoding`、改寫漸變函數，在 Illustrator 中會變成亂碼並提示「未知的陰影類型」。本工具用 [pikepdf](https://github.com/pikepdf/pikepdf) 直接修改對象結構，未改動的部分原樣保留。

## macOS app

從 [Releases](https://github.com/WenzyWong/compressPDF/releases) 下載 `PDF-Compressor-1.0.0-macOS-arm64.zip`，解壓後首次打開請右鍵選擇「打開」（ad-hoc 簽名，未公證）。

- 把 PDF 拖進窗口、點擊選擇，或在 Finder 中用「打開方式」
- 壓縮結果保存在原文件旁：`xxx-compressed.pdf`
- 內置獨立 Python 運行環境，無需另外安裝任何東西
- 需要 macOS 26+、Apple Silicon

### 從源碼構建

```bash
PDFCompressor/build_app.sh   # 輸出 PDFCompressor/build/PDF 壓縮.app
```

需要 Xcode 或 Command Line Tools（Swift 6.2+）。首次構建會下載 [python-build-standalone](https://github.com/astral-sh/python-build-standalone)（校驗 SHA-256）並安裝 pikepdf、Pillow。

## 命令行

```bash
pip install pikepdf pillow
python compress.py in.pdf out.pdf [low|recommended|extreme]
```
