import SwiftUI
import AppKit

// First-launch / reconfiguration sheet. Shown automatically when no
// server URL is configured, and on demand from the toolbar shield button.
struct ConnectionSheet: View {
    @ObservedObject var vm: MeterViewModel
    /// Offer Quit while nothing is configured yet. Only the standalone app may: hosted in the
    /// Suite, `NSApplication.terminate` would kill the Suite or the extension process.
    var canQuit: Bool = true
    @AppStorage("serverURL", store: AppDefaults.store) private var persistedURL: String = ""

    @State private var urlString: String = ""
    @State private var testStatus: TestStatus = .idle
    @State private var testTask: Task<Void, Never>?
    // Proxy login. The stored password is never read back into the UI: the field only
    // ever holds what the operator types, and is cleared once saved.
    @State private var proxyUser: String = "operator"
    @State private var proxyPassword: String = ""
    @State private var proxyAccount: String?    // username of the stored login, nil = none
    @State private var proxyMessage: String?
    var onDismiss: () -> Void

    enum TestStatus: Equatable {
        case idle
        case running
        case ok
        case failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                fieldSection
                proxySection
                hintSection
            }
            .padding(20)

            Divider()

            footer
        }
        .frame(width: 480)
        .onAppear {
            urlString = vm.serverURLString.nilIfEmpty
                ?? persistedURL.nilIfEmpty
                ?? "http://localhost:8089"
            proxyAccount = vm.storedProxyAccount
            if let proxyAccount { proxyUser = proxyAccount }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("Connect to LP-700 Server")
                    .font(.headline)
                Text("Enter the URL of your LP-500 / LP-700 WebSocket bridge.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var fieldSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Server URL")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // No onCommit: on macOS it also fires when the field loses focus, so clicking the
            // username / password field connected and closed the sheet. Return still connects
            // through the Connect button's .defaultAction shortcut.
            TextField("http://host:8089", text: $urlString)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .onChange(of: urlString) { _ in testStatus = .idle }

            HStack(spacing: 8) {
                Button(action: test) {
                    HStack(spacing: 4) {
                        if testStatus == .running {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "wave.3.right")
                                .foregroundStyle(.secondary)
                        }
                        Text("Test connection")
                    }
                }
                .disabled(testStatus == .running || urlString.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()

                statusLabel
            }
        }
    }

    private var proxySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Proxy login")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let proxyAccount {
                    Label("Stored for \(proxyAccount)", systemImage: "key.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("No login stored")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                TextField("Username", text: $proxyUser)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                    .frame(width: 140)
                SecureField(proxyAccount == nil ? "Password" : "New password", text: $proxyPassword)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                Button("Save to Keychain", action: saveProxyLogin)
                    .disabled(!canSaveProxyLogin)
                Button("Remove", action: removeProxyLogin)
                    .disabled(proxyAccount == nil)
                Spacer()
                if let proxyMessage {
                    Text(proxyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            if let error = vm.lastConnectError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("For a server behind the shack's TLS proxy (https://…). Sent as HTTP Basic auth over https/wss only, never over plain http. Kept in the login Keychain as \"\(ProxyKeychain.service)\".")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var hintSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tip")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text("On the server host: `lp700-server` listens on port 8089 by default (LP-100A-Server uses 8088). Use http://localhost:8089 if running on this Mac, or http://raspberrypi.local:8089 for a Pi on the LAN. Behind the shack's TLS proxy use https://host:8089 and save the proxy login.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var footer: some View {
        HStack {
            if !canQuit || vm.connection != .disconnected || vm.hasConfiguredServer {
                Button("Cancel", action: onDismiss)
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            Spacer()
            Button(action: connect) {
                Text("Connect")
                    .frame(minWidth: 80)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(urlString.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch testStatus {
        case .idle: EmptyView()
        case .running:
            Text("Probing…").font(.caption).foregroundStyle(.secondary)
        case .ok:
            Label("Reachable", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failure(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(2)
                .help(msg)
        }
    }

    private func test() {
        testTask?.cancel()
        testStatus = .running
        let candidate = urlString
        let model = vm
        testTask = Task { @MainActor in
            let result = await model.testConnection(urlString: candidate)
            switch result {
            case .ok: testStatus = .ok
            case .failure(let msg): testStatus = .failure(msg)
            }
        }
    }

    private var canSaveProxyLogin: Bool {
        let user = proxyUser.trimmingCharacters(in: .whitespaces)
        // RFC 7617: the user-id cannot contain a colon.
        return !user.isEmpty && !user.contains(":") && !proxyPassword.isEmpty
    }

    private func saveProxyLogin() {
        let login = ProxyCredentials(username: proxyUser.trimmingCharacters(in: .whitespaces),
                                     password: proxyPassword)
        let model = vm
        Task { @MainActor in
            do {
                try await model.saveProxyLogin(login)
                proxyPassword = ""
                proxyAccount = login.username
                proxyMessage = "Saved. The next connection uses it."
            } catch {
                proxyMessage = error.localizedDescription
            }
        }
    }

    private func removeProxyLogin() {
        let model = vm
        Task { @MainActor in
            do {
                try await model.removeProxyLogin()
                proxyAccount = nil
                proxyMessage = "Removed from the Keychain."
            } catch {
                proxyMessage = error.localizedDescription
            }
        }
    }

    private func connect() {
        let trimmed = urlString.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), url.host?.isEmpty == false else {
            testStatus = .failure("Invalid URL")
            return
        }
        persistedURL = trimmed
        Task {
            await vm.reconnect(serverURL: url)
            onDismiss()
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
