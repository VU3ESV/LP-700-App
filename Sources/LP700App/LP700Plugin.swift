import SwiftUI
import RadioPluginKit

/// Plugin adapter for the Amateur Radio Suite container. Lives inside the
/// `LP700App` module so it has internal access to `ContentView` / `MeterViewModel`
/// while keeping the suite's public surface to just this one type.
@MainActor
public final class LP700Plugin: RadioPlugin {
    public static let metadata = PluginMetadata(
        id: "lp700",
        title: "LP-700",
        systemImage: "gauge.with.dots.needle.bottom.50percent",
        version: "1.0"
    )

    private let host: PluginHost
    private let vm: MeterViewModel
    private var started = false

    public init(host: PluginHost) {
        self.host = host
        // Point this module's @AppStorage at a per-plugin suite BEFORE building
        // any view, so "serverURL" etc. don't collide with other plugins.
        AppDefaults.store = host.defaults(for: Self.metadata.id)
        self.vm = MeterViewModel()
    }

    public func makeRootView() -> AnyView {
        AnyView(ContentView(vm: vm))
    }

    public func activate() {
        guard !started else { vm.resync(); return }
        started = true
        // Per-plugin defaults — `UserDefaults.standard` would collide with the
        // other plugins sharing the container's process.
        let store = host.defaults(for: Self.metadata.id)
        if let s = store.string(forKey: "serverURL"),
           let url = URL(string: s), url.host?.isEmpty == false {
            Task { await vm.start(serverURL: url) }
        } else {
            vm.connectionSheetOpen = true
        }
    }

    public var menuCommands: [PluginCommand] {
        [
            PluginCommand(id: "lp700.resync", title: "Resync LP-700",
                          shortcut: KeyboardShortcut("y", modifiers: .command)) { [vm] in vm.resync() },
            PluginCommand(id: "lp700.range", title: "Step Range",
                          shortcut: KeyboardShortcut("r", modifiers: .command)) { [vm] in vm.sendRangeStep() },
            PluginCommand(id: "lp700.alarm", title: "Toggle Alarm",
                          shortcut: KeyboardShortcut("a", modifiers: .command)) { [vm] in vm.sendAlarmToggle() },
        ]
    }
}
