// swift-tools-version: 5.8

// Projeto de app do Swift Playgrounds (abre no iPad e também no Xcode no Mac).
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Caça ao Orc",
    platforms: [
        .iOS("16.0")
    ],
    products: [
        .iOSApplication(
            name: "Caça ao Orc",
            targets: ["AppModule"],
            bundleIdentifier: "br.com.worldgis.cacaaoorc",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .leaf),
            accentColor: .presetColor(.orange),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            capabilities: [
                .camera(purposeString: "A câmera é usada para escanear o chão e mostrar o orc no seu ambiente.")
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
