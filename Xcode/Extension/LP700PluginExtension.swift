import SwiftUI
import ExtensionFoundation
import ExtensionKit
import LP700App

/// LP-700 as a sandboxed, crash-isolated ExtensionKit `.appex` for the Amateur Radio Suite.
/// It declares the suite's extension point (see Info.plist) and vends LP-700's real UI via
/// `LP700Extension.rootView()`; the suite embeds it with `EXHostViewController`.
///
/// SwiftPM cannot build `.appex` bundles — this target is built by the Xcode project
/// (`Xcode/project.yml`). The standalone `LP-700-App` and the in-process `LP700Plugin`
/// are unchanged.
@main
struct LP700PluginExtension: AppExtension {
    var configuration: AppExtensionSceneConfiguration {
        AppExtensionSceneConfiguration(
            PrimitiveAppExtensionScene(id: "primary") {
                LP700Extension.rootView()
            }
        )
    }
}
