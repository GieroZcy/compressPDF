import Foundation

/// PDF 压缩规格；rawValue 与 compress.py 的等级名一致
enum Level: String, CaseIterable, Identifiable {
    case lossless, high, low, recommended, small, extreme, custom
    var id: Self { self }
    var title: String {
        switch self {
        case .lossless: "无损"
        case .high: "高画质"
        case .low: "轻度"
        case .recommended: "推荐"
        case .small: "小文件"
        case .extreme: "极限"
        case .custom: "自定义"
        }
    }
    /// (目标 DPI, JPEG 质量)，与 compress.py 一致；无损和自定义为 nil
    var settings: (dpi: Int, quality: Int)? {
        switch self {
        case .high: (300, 90)
        case .low: (200, 85)
        case .recommended: (150, 75)
        case .small: (120, 60)
        case .extreme: (96, 50)
        case .lossless, .custom: nil
        }
    }
    var summary: String {
        switch self {
        case .lossless: "只清理冗余数据，不改动图片"
        case .custom: "自行设置图片 DPI 和 JPEG 质量"
        default: settings.map { "图片 \($0.dpi) dpi · JPEG 质量 \($0.quality)" } ?? ""
        }
    }
}

struct CompressorError: LocalizedError {
    let errorDescription: String?
}

/// 用 app 内附带的 Python 运行 compress.py（pikepdf 直接修改对象结构，未改动的部分原样保留，
/// 所以输出仍能被 Illustrator 正常编辑；PDFKit/Quartz 重写会破坏字体编码和渐变）。
enum Compressor {
    static func compress(_ input: URL, level: Level, customDPI: Int, customQuality: Int) async throws -> URL {
        guard let resources = Bundle.main.resourceURL else {
            throw CompressorError(errorDescription: "找不到 app 资源目录")
        }
        let python = resources.appendingPathComponent("python/bin/python3")
        let script = resources.appendingPathComponent("compress.py")
        let output = uniqueOutputURL(for: input, suffix: "-compressed", extension: "pdf")

        try await Task.detached {
            let process = Process()
            process.executableURL = python
            // -I: 不受用户环境变量和 site-packages 影响；-B: 不写 __pycache__，以免破坏 app 签名
            var arguments = ["-I", "-B", script.path, input.path, output.path]
            if level == .custom {
                arguments += ["recommended", "--dpi", "\(customDPI)", "--quality", "\(customQuality)"]
            } else {
                arguments.append(level.rawValue)
            }
            process.arguments = arguments
            let stderr = Pipe()
            process.standardError = stderr
            process.standardOutput = FileHandle.nullDevice
            try process.run()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                try? FileManager.default.removeItem(at: output)
                let message = String(decoding: errData, as: UTF8.self).split(separator: "\n").last.map(String.init)
                throw CompressorError(errorDescription: message ?? "压缩失败")
            }
            if fileSize(output) >= fileSize(input) {
                try? FileManager.default.removeItem(at: output)
                throw CompressorError(errorDescription: "已是最优，无法进一步压缩")
            }
        }.value
        return output
    }
}

/// F1.pdf -> F1-compressed.pdf，已存在则 F1-compressed-2.pdf ...
func uniqueOutputURL(for input: URL, suffix: String, extension ext: String) -> URL {
    let dir = input.deletingLastPathComponent()
    let base = input.deletingPathExtension().lastPathComponent + suffix
    var url = dir.appendingPathComponent("\(base).\(ext)")
    var n = 2
    while FileManager.default.fileExists(atPath: url.path) {
        url = dir.appendingPathComponent("\(base)-\(n).\(ext)")
        n += 1
    }
    return url
}

func fileSize(_ url: URL) -> Int64 {
    (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
}
