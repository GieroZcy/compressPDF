import SwiftUI
import UniformTypeIdentifiers

@main
struct PDFCompressorApp: App {
    var body: some Scene {
        Window("PDF Compressor", id: "main") {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

enum Mode: String, CaseIterable, Identifiable {
    case compress, tiff
    var id: Self { self }
    var title: String {
        switch self {
        case .compress: String(localized: "壓縮 PDF")
        case .tiff: String(localized: "轉為 TIFF")
        }
    }
}

@MainActor @Observable
final class Job: Identifiable {
    enum State {
        case running
        case done(output: URL, before: Int64, after: Int64)
        case failed(String)
    }

    let id = UUID()
    let input: URL
    let mode: Mode
    var state = State.running

    init(input: URL, mode: Mode) {
        self.input = input
        self.mode = mode
    }
}

struct ContentView: View {
    @AppStorage("mode") private var mode = Mode.compress
    @AppStorage("level") private var level = Level.recommended
    @AppStorage("customDPI") private var customDPI = 200
    @AppStorage("customQuality") private var customQuality = 80
    @AppStorage("tiffDPI") private var tiffDPI = 300
    @AppStorage("tiffColor") private var tiffColor = TIFFOptions.ColorMode.rgb
    @AppStorage("tiffCompression") private var tiffCompression = TIFFOptions.Compression.lzw
    @State private var jobs: [Job] = []
    @State private var isTargeted = false
    @State private var showImporter = false

    var body: some View {
        VStack(spacing: 16) {
            Picker("模式", selection: $mode.animation(.snappy)) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)

            dropZone
            optionsPanel

            if !jobs.isEmpty {
                VStack(spacing: 0) {
                    ForEach(jobs) { job in
                        JobRow(job: job)
                        if job.id != jobs.last?.id { Divider().padding(.leading, 44) }
                    }
                }
                .padding(.vertical, 4)
                .background(.fill.quaternary, in: .rect(cornerRadius: 16))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 36)  // 留出紅綠燈按鈕的位置
        .padding(.bottom, 20)
        .frame(width: 460)
        .windowBackground()
        .ignoresSafeArea()
        // 整個窗口都可接收拖放；用 NSItemProvider 讀取 Finder 的 file URL，比 dropDestination(for: URL.self) 可靠
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.pathExtension.lowercased() == "pdf" else { return }
                    Task { @MainActor in start([url]) }
                }
            }
            return true
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: true) {
            if case .success(let urls) = $0 { start(urls) }
        }
        .onOpenURL { start([$0]) }  // Finder「打開方式」或拖到 Dock 圖標
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: mode == .compress ? "arrow.down.document" : "photo.badge.arrow.down")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                .symbolEffect(.bounce, value: isTargeted)
                .contentTransition(.symbolEffect(.replace))
            Text("拖入 PDF 文件")
                .font(.headline)
            Text(mode == .compress ? LocalizedStringKey("或點擊選擇，壓縮後保存在原文件旁") : "或點擊選擇，轉換為 TIFF 保存在原文件旁")
                .font(.callout)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(isTargeted ? Color.accentColor : .secondary.opacity(0.35),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .fill(isTargeted ? Color.accentColor.opacity(0.08) : .clear)
        }
        .contentShape(.rect(cornerRadius: 20))
        .onTapGesture { showImporter = true }
        .animation(.snappy, value: isTargeted)
    }

    private var optionsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch mode {
            case .compress:
                OptionRow("規格") {
                    Picker("規格", selection: $level.animation(.snappy)) {
                        ForEach(Level.allCases) { level in
                            Text(level.title).tag(level)
                            if level == .extreme { Divider() }  // 「自定義」單獨一組
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if level == .custom {
                    OptionRow("圖片 DPI") { ValueSlider(value: $customDPI, range: 72...600, step: 6) }
                    OptionRow("JPEG 品質") { ValueSlider(value: $customQuality, range: 30...95, step: 1) }
                }
                Text(level.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .tiff:
                OptionRow("解析度") {
                    Picker("解析度", selection: $tiffDPI) {
                        ForEach(TIFFOptions.dpiChoices, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                OptionRow("色彩") {
                    Picker("色彩", selection: $tiffColor) {
                        ForEach(TIFFOptions.ColorMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                OptionRow("壓縮") {
                    Picker("壓縮", selection: $tiffCompression) {
                        ForEach(TIFFOptions.Compression.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Text("LZW 與 ZIP 均為無損壓縮：ZIP 通常更小，LZW 兼容性最好。多頁 PDF 會輸出為多頁 TIFF。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: .rect(cornerRadius: 16))
    }

    private func start(_ urls: [URL]) {
        // 在開始時拷貝當前設定，之後切換設定不影響進行中的任務
        let mode = mode, level = level, customDPI = customDPI, customQuality = customQuality
        let tiffOptions = TIFFOptions(dpi: tiffDPI, color: tiffColor, compression: tiffCompression)
        for url in urls {
            let job = Job(input: url, mode: mode)
            withAnimation { jobs.insert(job, at: 0) }
            Task {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    let output = switch mode {
                    case .compress:
                        try await Compressor.compress(url, level: level, customDPI: customDPI, customQuality: customQuality)
                    case .tiff:
                        try await TIFFConverter.convert(url, options: tiffOptions)
                    }
                    withAnimation { job.state = .done(output: output, before: fileSize(url), after: fileSize(output)) }
                } catch {
                    withAnimation { job.state = .failed(error.localizedDescription) }
                }
            }
        }
    }
}

/// 選項面板中的一行：左側標籤固定寬度，右側控件
struct OptionRow<Content: View>: View {
    let label: LocalizedStringKey
    @ViewBuilder let content: Content

    init(_ label: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: 72, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
    }
}

extension View {
    /// macOS 26 起窗口本身透明，整個窗口是一塊液態玻璃；更早的系統用普通窗口背景色
    @ViewBuilder func windowBackground() -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: .rect(cornerRadius: 26))
                .containerBackground(.clear, for: .window)
        } else {
            background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

/// 整數滑桿 + 右側數值
struct ValueSlider: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        Slider(value: Binding(get: { Double(value) }, set: { value = Int($0) }),
               in: Double(range.lowerBound)...Double(range.upperBound), step: Double(step))
        Text("\(value)")
            .font(.callout.monospacedDigit())
            .frame(width: 34, alignment: .trailing)
    }
}

struct JobRow: View {
    let job: Job

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: job.mode == .compress ? "doc.richtext.fill" : "photo.fill")
                .font(.title2)
                .foregroundStyle(job.mode == .compress ? AnyShapeStyle(.red.gradient) : AnyShapeStyle(.blue.gradient))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.input.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                detail
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var detail: some View {
        switch job.state {
        case .running:
            Text(job.mode == .compress ? LocalizedStringKey("壓縮中…") : "轉換中…")
        case let .done(output, before, after):
            Text("\(format(before)) → \(output.pathExtension.uppercased()) \(format(after))")
        case let .failed(message):
            Text(message).foregroundStyle(.red).lineLimit(2)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch job.state {
        case .running:
            ProgressView().controlSize(.small)
        case let .done(output, before, after):
            if before > 0, after < before {
                Text("−\(Int((1 - Double(after) / Double(before)) * 100))%")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.green)
            }
            Button("在 Finder 中顯示", systemImage: "magnifyingglass") {
                NSWorkspace.shared.activateFileViewerSelecting([output])
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        }
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
