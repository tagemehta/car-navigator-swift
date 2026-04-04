// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "thing-finder",
  platforms: [
    .iOS(.v16),
    .macOS(.v13),
  ],
  products: [
    // Products define the executables and libraries a package produces, making them visible to other packages.
    .library(
      name: "ThingFinder",
      targets: ["ThingFinder"])
  ],
  dependencies: [
    // Dependencies declare other packages that this package depends on.
    // COMMENTED OUT FOR APP STORE SUBMISSION - Meta SDK requires Bluetooth permissions
    // .package(url: "https://github.com/facebook/meta-wearables-dat-ios", from: "0.5.0")
  ],
  targets: [
    // Targets are the basic building blocks of a package, defining a module or a test suite.
    .target(
      name: "ThingFinder",
      dependencies: [
        // COMMENTED OUT FOR APP STORE SUBMISSION - Meta SDK requires Bluetooth permissions
        // .product(name: "MWDATCore", package: "meta-wearables-dat-ios"),
        // .product(name: "MWDATCamera", package: "meta-wearables-dat-ios"),
      ],
      path: "thing-finder",
      resources: [
        .process("Assets.xcassets"),
        .process("Sounds"),
      ]
    ),
    .testTarget(
      name: "ThingFinderTests",
      dependencies: ["ThingFinder"],
      path: "thing-finderTests"
    ),
  ]
)
