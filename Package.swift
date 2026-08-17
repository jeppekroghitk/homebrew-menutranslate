// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MenuTranslate",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MenuTranslate",
            path: "Sources/MenuTranslate"
        )
    ]
)
