// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "AirPulse",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "SMCKit", targets: ["SMCKit"]),
    .library(name: "FanKit", targets: ["FanKit"]),
    .library(name: "AirPulseProtocol", targets: ["AirPulseProtocol"]),
    .executable(name: "airpulse-cli", targets: ["AirPulseCLI"]),
    .executable(name: "AirPulseHelper", targets: ["AirPulseHelper"]),
    .executable(name: "AirPulse", targets: ["AirPulseApp"]),
  ],
  targets: [
    .target(name: "SMCKit", path: "Sources/SMCKit"),
    .target(name: "FanKit", dependencies: ["SMCKit"], path: "Sources/FanKit"),
    .target(name: "AirPulseProtocol", path: "Sources/AirPulseProtocol"),
    .executableTarget(
      name: "AirPulseCLI",
      dependencies: ["SMCKit", "FanKit", "AirPulseProtocol"],
      path: "Sources/AirPulseCLI"
    ),
    .executableTarget(
      name: "AirPulseHelper",
      dependencies: ["SMCKit", "FanKit", "AirPulseProtocol"],
      path: "Sources/AirPulseHelper"
    ),
    .executableTarget(
      name: "AirPulseApp",
      dependencies: ["FanKit", "AirPulseProtocol", "SMCKit"],
      path: "Sources/AirPulseApp"
    ),
  ]
)
