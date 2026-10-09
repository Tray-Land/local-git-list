// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalGitList",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LocalGitList", targets: ["LocalGitList"]),
    ],
    targets: [
        // Platform-free logic: scanning, .git parsing, remote → web URL, list ordering, git output parsing.
        .target(name: "LocalGitListCore"),
        .executableTarget(name: "LocalGitList", dependencies: ["LocalGitListCore"]),
        .testTarget(name: "LocalGitListCoreTests", dependencies: ["LocalGitListCore"]),
    ]
)
