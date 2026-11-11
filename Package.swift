// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LangSale",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "LangSaleCore", targets: ["LangSaleCore"]),
    ],
    targets: [
        .target(name: "LangSaleCore"),
        .testTarget(name: "LangSaleCoreTests", dependencies: ["LangSaleCore"]),
    ]
)
