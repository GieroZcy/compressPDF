import SwiftUI
import UniformTypeIdentifiers

@main
struct PDFCompressorApp: App {
    var body: some Scene {
        Window("PDF 壓縮", id: "main") {
            ContentView()
                .containerBackground(.clear, for: .window)  // 窗口本身透明，只留玻璃面板
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
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
    var state = State.running

    init(input: URL) { self.input = input }
}

struct ContentView: View {
    @AppStorage("level") private var level = Level.recommended
    @State private var jobs: [Job] = []
    @State private var isTargeted = false
    @State private var showImporter = false

    var body: some View {
        VStack(spacing: 16) {
            dropZone
            Picker("壓縮等級", selection: $level) {
                ForEach(Level.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

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
        .frame(width: 440)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))  // 整個窗口是一塊液態玻璃
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
            Image(systemName: "arrow.down.document")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                .symbolEffect(.bounce, value: isTargeted)
            Text("拖入 PDF 文件")
                .font(.headline)
            Text("或點擊選擇，壓縮後保存在原文件旁")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 170)
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

    private func start(_ urls: [URL]) {
        for url in urls {
            let job = Job(input: url)
            withAnimation { jobs.insert(job, at: 0) }
            Task {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    let output = try await Compressor.compress(url, level: level)
                    withAnimation { job.state = .done(output: output, before: fileSize(url), after: fileSize(output)) }
                } catch {
                    withAnimation { job.state = .failed(error.localizedDescription) }
                }
            }
        }
    }
}

struct JobRow: View {
    let job: Job

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.richtext.fill")
                .font(.title2)
                .foregroundStyle(.red.gradient)
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
            Text("壓縮中…")
        case let .done(_, before, after):
            Text("\(format(before)) → \(format(after))")
        case let .failed(message):
            Text(message).foregroundStyle(.red).lineLimit(2)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch job.state {
        case .running:
            ProgressView().controlSize(.small)
        case let .done(output, before, after):
            Text(before > 0 ? "−\(Int((1 - Double(after) / Double(before)) * 100))%" : "")
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(.green)
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

