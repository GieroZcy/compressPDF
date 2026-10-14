import Foundation

enum Level: String, CaseIterable, Identifiable {
    case low, recommended, extreme
    var id: Self { self }
    var title: String {
        switch self {
        case .low: "低"
        case .recommended: "推薦"
        case .extreme: "極限"
        }
    }
}

struct CompressorError: LocalizedError {
    let errorDescription: String?
}

/// 用 app 內附帶的 Python 運行 compress.py（pikepdf 直接修改對象結構，未改動的部分原樣保留，
/// 所以輸出仍能被 Illustrator 正常編輯；PDFKit/Quartz 重寫會破壞字體編碼和漸變）。
enum Compressor {
    static func compress(_ input: URL, level: Level) async throws -> URL {
        guard let resources = Bundle.main.resourceURL else {
            throw CompressorError(errorDescription: "找不到 app 資源目錄")
        }
        let python = resources.appendingPathComponent("python/bin/python3")
        let script = resources.appendingPathComponent("compress.py")
        let output = uniqueOutputURL(for: input)

        try await Task.detached {
            let process = Process()
            process.executableURL = python
            // -I: 不受用戶環境變量和 site-packages 影響；-B: 不寫 __pycache__，以免破壞 app 簽名
            process.arguments = ["-I", "-B", script.path, input.path, output.path, level.rawValue]
            let stderr = Pipe()
            process.standardError = stderr
            process.standardOutput = FileHandle.nullDevice
            try process.run()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                try? FileManager.default.removeItem(at: output)
                let message = String(decoding: errData, as: UTF8.self).split(separator: "\n").last.map(String.init)
                throw CompressorError(errorDescription: message ?? "壓縮失敗")
            }
            if fileSize(output) >= fileSize(input) {
                try? FileManager.default.removeItem(at: output)
                throw CompressorError(errorDescription: "已是最優，無法進一步壓縮")
            }
        }.value
        return output
    }

    /// F1.pdf -> F1-compressed.pdf，已存在則 F1-compressed-2.pdf ...
    private static func uniqueOutputURL(for input: URL) -> URL {
        let dir = input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent + "-compressed"
        var url = dir.appendingPathComponent(base + ".pdf")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base)-\(n).pdf")
            n += 1
        }
        return url
    }
}

func fileSize(_ url: URL) -> Int64 {
    (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
}
