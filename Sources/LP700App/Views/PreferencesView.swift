import SwiftUI

struct PreferencesView: View {
    @ObservedObject var vm: MeterViewModel
    @AppStorage("alarmNotifications", store: AppDefaults.store) var alarmNotifications: Bool = true
    @AppStorage("menuBarItemEnabled", store: AppDefaults.store) var menuBarItemEnabled: Bool = true

    var body: some View {
        TabView {
            serverTab
                .tabItem { Label("Server", systemImage: "network") }
            notificationsTab
                .tabItem { Label("Notifications", systemImage: "bell") }
            displayTab
                .tabItem { Label("Display", systemImage: "display") }
            updatesTab
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
        }
        .frame(width: 500, height: 300)
    }

    private var serverTab: some View {
        Form {
            LabeledContent("Server URL") {
                Text(vm.serverURLString.isEmpty ? "Not configured" : vm.serverURLString)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(vm.serverURLString.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
            }

            LabeledContent("Status") {
                statusBadge
            }

            if let error = vm.lastConnectError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LabeledContent("Backend") {
                Text(vm.backend.uppercased())
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Change Server…") {
                    vm.connectionSheetOpen = true
                }
                .controlSize(.regular)

                if vm.connection == .connected {
                    Button("Disconnect") {
                        Task { await vm.disconnect() }
                    }
                } else if vm.hasConfiguredServer {
                    Button("Reconnect") {
                        if let url = URL(string: vm.serverURLString) {
                            Task { await vm.reconnect(serverURL: url) }
                        }
                    }
                }
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch vm.connection {
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .reconnecting:
            Label("Reconnecting…", systemImage: "arrow.clockwise.circle.fill")
                .foregroundStyle(.yellow)
        case .disconnected:
            Label("Offline", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private var notificationsTab: some View {
        Form {
            Toggle("Notify when alarm trips", isOn: $alarmNotifications)
            Text("macOS notification posted on the rising edge of `alarm_tripped`. Throttled to one per 30 s.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var displayTab: some View {
        Form {
            Toggle("Show menu-bar live readout", isOn: $menuBarItemEnabled)
            Text("Restart the app to apply menu-bar visibility changes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var updatesTab: some View {
        Form {
            UpdateChecker.AutomaticToggle()
            Text("About 10 seconds after launch, and then once a day while it keeps running, LP-700-App asks GitHub whether a newer release exists. Nothing is downloaded or installed — the dialog's Download button opens the release page. LP-700 ▸ Check for Updates… checks right away.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }
}
