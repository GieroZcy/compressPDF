import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// TIFF 輸出設定
struct TIFFOptions: Sendable {
    enum ColorMode: String, CaseIterable, Identifiable {
        case rgb, cmyk, gray
        var id: Self { self }
        var title: String {
            switch self {
            case .rgb: "RGB"
            case .cmyk: "CMYK"
            case .gray: String(localized: "灰度")
            }
        }
    }

    /// rawValue 是 TIFF 的 Compression 標籤值
    enum Compression: Int, CaseIterable, Identifiable {
        case lzw = 5, zip = 8, none = 1
        var id: Self { self }
        var title: String {
            switch self {
            case .lzw: "LZW"
            case .zip: "ZIP"
            case .none: String(localized: "不壓縮")
            }
        }
    }

    static let dpiChoices = [150, 300, 600, 1200]

    var dpi = 300
    var color = ColorMode.rgb
    var compression = Compression.lzw
}

/// 用 Quartz 把 PDF 每頁渲染成點陣圖（白底、無透明通道），寫成一個多頁 TIFF。
/// 輸出是點陣圖，不涉及 Quartz 重寫 PDF 導致 Illustrator 無法編輯的問題。
enum TIFFConverter {
    static func convert(_ input: URL, options: TIFFOptions) async throws -> URL {
        let output = uniqueOutputURL(for: input, suffix: "", extension: "tif")
        try await Task.detached {
            guard let doc = CGPDFDocument(input as CFURL) else {
                throw CompressorError(errorDescription: String(localized: "無法讀取這個 PDF"))
            }
            guard doc.isUnlocked else {
                throw CompressorError(errorDescription: String(localized: "PDF 已加密，請先解鎖"))
            }
            guard let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.tiff.identifier as CFString, doc.numberOfPages, nil) else {
                throw CompressorError(errorDescription: String(localized: "無法創建 TIFF 文件"))
            }
            let properties = [
                kCGImagePropertyDPIWidth: options.dpi,
                kCGImagePropertyDPIHeight: options.dpi,
                kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: options.compression.rawValue],
            ] as CFDictionary

            for index in 1...doc.numberOfPages {
                guard let page = doc.page(at: index), let image = render(page, options: options) else {
                    throw CompressorError(errorDescription: String(localized: "第 \(index) 頁渲染失敗（分辨率可能過高）"))
                }
                CGImageDestinationAddImage(dest, image, properties)
            }
            guard CGImageDestinationFinalize(dest) else {
                try? FileManager.default.removeItem(at: output)
                throw CompressorError(errorDescription: String(localized: "寫入 TIFF 失敗"))
            }
        }.value
        return output
    }

    private static func render(_ page: CGPDFPage, options: TIFFOptions) -> CGImage? {
        let box = page.getBoxRect(.cropBox)  // 與閱讀器顯示的範圍一致
        let angle = (page.rotationAngle % 360 + 360) % 360
        let size = angle % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
        let scale = CGFloat(options.dpi) / 72
        let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())

        let (space, alpha): (CGColorSpace?, CGImageAlphaInfo) = switch options.color {
        case .rgb: (CGColorSpace(name: CGColorSpace.sRGB), .noneSkipLast)
        case .cmyk: (CGColorSpace(name: CGColorSpace.genericCMYK), .none)
        case .gray: (CGColorSpace(name: CGColorSpace.genericGrayGamma2_2), .none)
        }
        guard let space, let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: space, bitmapInfo: alpha.rawValue) else { return nil }

        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: scale, y: scale)
        // /Rotate 是顯示時順時針旋轉的角度
        switch angle {
        case 90: ctx.translateBy(x: 0, y: box.width); ctx.rotate(by: -.pi / 2)
        case 180: ctx.translateBy(x: box.width, y: box.height); ctx.rotate(by: .pi)
        case 270: ctx.translateBy(x: box.height, y: 0); ctx.rotate(by: .pi / 2)
        default: break
        }
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.clip(to: box)
        ctx.drawPDFPage(page)
        return ctx.makeImage()
    }
}
