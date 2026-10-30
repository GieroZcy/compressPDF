import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// TIFF 输出设置
struct TIFFOptions: Sendable {
    enum ColorMode: String, CaseIterable, Identifiable {
        case rgb, cmyk, gray
        var id: Self { self }
        var title: String {
            switch self {
            case .rgb: "RGB"
            case .cmyk: "CMYK"
            case .gray: "灰度"
            }
        }
    }

    /// rawValue 是 TIFF 的 Compression 标签值
    enum Compression: Int, CaseIterable, Identifiable {
        case lzw = 5, zip = 8, none = 1
        var id: Self { self }
        var title: String {
            switch self {
            case .lzw: "LZW"
            case .zip: "ZIP"
            case .none: "不压缩"
            }
        }
    }

    static let dpiChoices = [150, 300, 600, 1200]

    var dpi = 300
    var color = ColorMode.rgb
    var compression = Compression.lzw
}

/// 用 Quartz 把 PDF 每页渲染成点阵图（白底、无透明通道），写成一个多页 TIFF。
/// 输出是点阵图，不涉及 Quartz 重写 PDF 导致 Illustrator 无法编辑的问题。
enum TIFFConverter {
    static func convert(_ input: URL, options: TIFFOptions) async throws -> URL {
        let output = uniqueOutputURL(for: input, suffix: "", extension: "tif")
        try await Task.detached {
            guard let doc = CGPDFDocument(input as CFURL) else {
                throw CompressorError(errorDescription: "无法读取这个 PDF")
            }
            guard doc.isUnlocked else {
                throw CompressorError(errorDescription: "PDF 已加密，请先解锁")
            }
            guard let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.tiff.identifier as CFString, doc.numberOfPages, nil) else {
                throw CompressorError(errorDescription: "无法创建 TIFF 文件")
            }
            let properties = [
                kCGImagePropertyDPIWidth: options.dpi,
                kCGImagePropertyDPIHeight: options.dpi,
                kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: options.compression.rawValue],
            ] as CFDictionary

            for index in 1...doc.numberOfPages {
                guard let page = doc.page(at: index), let image = render(page, options: options) else {
                    throw CompressorError(errorDescription: "第 \(index) 页渲染失败（分辨率可能过高）")
                }
                CGImageDestinationAddImage(dest, image, properties)
            }
            guard CGImageDestinationFinalize(dest) else {
                try? FileManager.default.removeItem(at: output)
                throw CompressorError(errorDescription: "写入 TIFF 失败")
            }
        }.value
        return output
    }

    private static func render(_ page: CGPDFPage, options: TIFFOptions) -> CGImage? {
        let box = page.getBoxRect(.cropBox)  // 与阅读器显示的范围一致
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
        // /Rotate 是显示时顺时针旋转的角度
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
