// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "thing-finder",
  platforms: [
    .iOS(.v16),
    .macOS(.v13),
  ],
  products: [
    .library(
      name: "thing-finder",
      targets: ["thing-finder"])
  ],
  dependencies: [],
  targets: [
    .target(
      name: "thing-finder",
      path: "thing-finder",
      exclude: ["Info.plist"]
    ),
    .testTarget(
      name: "thing-finderTests",
      dependencies: ["thing-finder"],
      path: "thing-finderTests"
    ),
  ],
  swiftLanguageVersions: [.v5]
)
