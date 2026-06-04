import SwiftUI

/// Public entry point for hosting LP-700 **out-of-process** as an ExtensionKit `.appex`.
///
/// The extension target is a separate module, so it can't see LP-700's `internal` views.
/// This factory hands it the same UI the in-process `LP700Plugin` shows, keeping every
/// other LP-700 type private. See `Xcode/Extension/LP700PluginExtension.swift`.
public enum LP700Extension {
    /// Build the LP-700 root view for an out-of-process host. `defaults` backs the app's
    /// `@AppStorage` (the extension's own sandboxed `UserDefaults`); pass an app-group
    /// suite if the container and extension should share connection settings.
    @MainActor
    public static func rootView(defaults: UserDefaults? = nil) -> AnyView {
        if let defaults { AppDefaults.store = defaults }
        // `embedded: true` renders the toolbar controls inline. A hosted .appex has no window
        // title bar, so SwiftUI `.toolbar` items never appear; the standalone app (embedded:
        // false) keeps its window toolbar.
        return AnyView(ContentView(vm: MeterViewModel(), embedded: true))
    }
}
