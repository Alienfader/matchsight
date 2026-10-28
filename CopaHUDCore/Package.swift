// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "CopaHUDCore",
  platforms: [.iOS(.v17), .macOS(.v13)],
  products: [.library(name: "CopaHUDCore", targets: ["CopaHUDCore"])],
  targets: [
    .target(name: "CopaHUDCore", resources: [.process("Resources")]),
    // Mac-side tool for the reliability run: `swift run reliability-report <log>`.
    .executableTarget(name: "reliability-report", dependencies: ["CopaHUDCore"]),
    .testTarget(
      name: "CopaHUDCoreTests",
      dependencies: ["CopaHUDCore"],
      resources: [.process("Resources")]
    ),
  ]
)
