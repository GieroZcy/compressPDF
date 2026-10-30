import Foundation

/// PDF 壓縮規格；rawValue 與 compress.py 的等級名一致
enum Level: String, CaseIterable, Identifiable {
    case lossless, high, low, recommended, small, extreme, custom
    var id: Self { self }
    var title: String {
        switch self {
        case .lossless: String(localized: "無損")
        case .high: String(localized: "高畫質")
        case .low: String(localized: "輕度")
        case .recommended: String(localized: "推薦")
        case .small: String(localized: "小檔案")
        case .extreme: String(localized: "極限")
        case .custom: String(localized: "自定義")
        }
    }
    /// (目標 DPI, JPEG 品質)，與 compress.py 一致；無損和自定義為 nil
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
        case .lossless: String(localized: "只清理冗餘數據，不改動圖片")
        case .custom: String(localized: "自行設定圖片 DPI 和 JPEG 品質")
        default: settings.map { String(localized: "圖片 \($0.dpi) dpi · JPEG 品質 \($0.quality)") } ?? ""
        }
    }
}

struct CompressorError: LocalizedError {
    let errorDescription: String?
}

/// 用 app 內附帶的 Python 運行 compress.py（pikepdf 直接修改對象結構，未改動的部分原樣保留，
/// 所以輸出仍能被 Illustrator 正常編輯；PDFKit/Quartz 重寫會破壞字體編碼和漸變）。
enum Compressor {
    static func compress(_ input: URL, level: Level, customDPI: Int, customQuality: Int) async throws -> URL {
        guard let resources = Bundle.main.resourceURL else {
            throw CompressorError(errorDescription: String(localized: "找不到 app 資源目錄"))
        }
        let python = resources.appendingPathComponent("python/bin/python3")
        let script = resources.appendingPathComponent("compress.py")
        let output = uniqueOutputURL(for: input, suffix: "-compressed", extension: "pdf")

        try await Task.detached {
            let process = Process()
            process.executableURL = python
            // -I: 不受用戶環境變量和 site-packages 影響；-B: 不寫 __pycache__，以免破壞 app 簽名
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
                throw CompressorError(errorDescription: message ?? String(localized: "壓縮失敗"))
            }
            if fileSize(output) >= fileSize(input) {
                try? FileManager.default.removeItem(at: output)
                throw CompressorError(errorDescription: String(localized: "已是最優，無法進一步壓縮"))
            }
        }.value
        return output
    }
}

/// F1.pdf -> F1-compressed.pdf，已存在則 F1-compressed-2.pdf ...
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
