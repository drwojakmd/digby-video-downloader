// swift-tools-version:5.9
//
// Digby Video Downloader
//
//   DigbyDesign         – design system: tokens, brand motif, controls. No app logic.
//   DigbyDownloadCore   – UI-independent core: media model, format catalogue and selection,
//                          plain-English explanations (later: engines, queue, history, dependencies).
//   DigbyDownloaderApp  – the SwiftUI macOS application.
//   digby-dl            – command-line front end to the core (end-to-end tests, scripting).
//   digby-dl-tests      – unit tests as a plain executable (Command Line Tools ship no XCTest).
//
import PackageDescription

let package = Package(
    name: "DigbyVideoDownloader",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DigbyDownloaderApp", targets: ["DigbyDownloaderApp"]),
        .executable(name: "digby-dl", targets: ["digby-dl"]),
        .library(name: "DigbyDownloadCore", targets: ["DigbyDownloadCore"]),
    ],
    targets: [
        .target(name: "DigbyDesign", path: "Sources/DigbyDesign"),
        .target(name: "DigbyDownloadCore", path: "Sources/DigbyDownloadCore"),
        .executableTarget(name: "DigbyDownloaderApp", dependencies: ["DigbyDesign", "DigbyDownloadCore"],
                          path: "Sources/DigbyDownloaderApp"),
        .executableTarget(name: "digby-dl", dependencies: ["DigbyDownloadCore"], path: "Sources/digby-dl"),
        .executableTarget(name: "digby-dl-tests", dependencies: ["DigbyDownloadCore"], path: "Sources/digby-dl-tests"),
    ]
)
