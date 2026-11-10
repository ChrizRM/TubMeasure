// swift-tools-version:5.9
// This package exists only so the platform-independent measurement engine in
// TubMeasure/Core can be unit-tested with `swift test` (on macOS or Linux).
// The iOS app itself is built from TubMeasure.xcodeproj.
import PackageDescription

let package = Package(
    name: "TubMeasureCore",
    targets: [
        .target(name: "TubMeasureCore", path: "TubMeasure/Core"),
        .testTarget(name: "TubMeasureCoreTests", dependencies: ["TubMeasureCore"], path: "Tests/TubMeasureCoreTests"),
    ]
)
