import SwiftUI

struct RemoteToolsView: View {
    @EnvironmentObject private var appState: AppState
    let onBack: () -> Void

    @State private var draftSettings = RemoteSettings.defaults
    @State private var showAdvanced = false

    @State private var displayTunnelRunning = false
    @State private var displayTunnelPID: Int32?
    @State private var displayTunnelStatus = "Tunnel stopped"

    var body: some View {
        MenuPanelScaffold(title: "Remote & Tunnel", onBack: backAndSave) {
            VStack(alignment: .leading, spacing: 16) {
                Form {
                    Section("Server") {
                        TextField("Host", text: $draftSettings.host, prompt: Text("your.server.example"))
                        TextField("Username", text: $draftSettings.username, prompt: Text("your-username"))
                    }

                    Section("Proxy tunnel") {
                        portField("Local proxy port", value: $draftSettings.localProxyPort, placeholder: "7890")
                        portField("Remote bind port", value: $draftSettings.remoteBindPort, placeholder: "18080")
                    }

                    Section {
                        DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                            TextField("Remote auth path", text: $draftSettings.remoteAuthPath, prompt: Text("~/.codex/auth.json"))
                            portField("SSH port", value: $draftSettings.sshPort, placeholder: "22")
                        }
                    }

                    Section("Tunnel") {
                        HStack {
                            Circle()
                                .fill(displayTunnelRunning ? Color.green : Color.secondary.opacity(0.4))
                                .frame(width: 8, height: 8)
                            Text(displayTunnelStatus)
                                .font(.subheadline)
                            Spacer()
                            if let pid = displayTunnelPID {
                                Text("PID \(pid)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if appState.isRemoteBusy {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }

                        Button(displayTunnelRunning ? "Stop tunnel" : "Start tunnel") {
                            let settings = draftSettings
                            if displayTunnelRunning {
                                appState.stopTunnel()
                            } else {
                                appState.startTunnel(using: settings)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appState.isRemoteBusy)
                    }

                    Section("Auth sync") {
                        Button {
                            let settings = draftSettings
                            appState.commitRemoteSettings(settings)
                            appState.syncAuthToRemote(using: settings)
                        } label: {
                            Label("Sync auth.json to server", systemImage: "arrow.up.doc")
                        }
                        .buttonStyle(.bordered)
                        .disabled(appState.isRemoteBusy)

                        Text("Uploads local ~/.codex/auth.json to the remote path above.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Command preview") {
                        Text(draftSettings.tunnelCommandPreview())
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)

                statusFooter
            }
        }
        .onAppear {
            draftSettings = appState.remoteSettings
            syncTunnelDisplayFromAppState()
        }
        .onChange(of: appState.tunnelRunning) { _, _ in
            syncTunnelDisplayFromAppState()
        }
        .onChange(of: appState.tunnelPID) { _, _ in
            syncTunnelDisplayFromAppState()
        }
        .onChange(of: appState.tunnelLastError) { _, _ in
            syncTunnelDisplayFromAppState()
        }
        .onChange(of: appState.isRemoteBusy) { _, busy in
            if !busy {
                syncTunnelDisplayFromAppState()
            }
        }
    }

    private func backAndSave() {
        appState.commitRemoteSettings(draftSettings)
        onBack()
    }

    private func syncTunnelDisplayFromAppState() {
        displayTunnelRunning = appState.tunnelRunning
        displayTunnelPID = appState.tunnelPID
        displayTunnelStatus = appState.tunnelStatusText
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = appState.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func portField(_ title: String, value: Binding<Int>, placeholder: String) -> some View {
        TextField(title, text: Binding(
            get: { String(value.wrappedValue) },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                if let parsed = Int(digits), !digits.isEmpty {
                    value.wrappedValue = parsed
                }
            }
        ), prompt: Text(placeholder))
        .textFieldStyle(.roundedBorder)
    }
}
