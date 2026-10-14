// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PDFCompressor",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "PDFCompressor")
    ]
)
