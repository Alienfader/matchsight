// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "CopaHUDCore",
  platforms: [.iOS(.v17), .macOS(.v13)],
  products: [.library(name: "CopaHUDCore", targets: ["CopaHUDCore"])],
  targets: [
    .target(name: "CopaHUDCore", resources: [.process("Resources")]),
    .testTarget(
      name: "CopaHUDCoreTests",
      dependencies: ["CopaHUDCore"],
      resources: [.process("Resources")]
    ),
  ]
)
