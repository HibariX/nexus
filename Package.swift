// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Nexus",
    // 15.2：SCScreenshotManager.captureImage(in:) 的最低要求
    platforms: [.macOS("15.2")],
    targets: [
        .executableTarget(
            name: "Nexus",
            swiftSettings: [
                // 全模块默认 @MainActor（SE-0466）：本应用几乎全是 UI 与主线程系统 API
                .defaultIsolation(MainActor.self)
            ]
        ),
        .testTarget(
            name: "NexusTests",
            dependencies: ["Nexus"],
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        )
    ]
)
