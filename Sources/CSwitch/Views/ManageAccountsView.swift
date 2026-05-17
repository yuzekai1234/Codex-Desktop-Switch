import SwiftUI

struct ManageAccountsView: View {
    @EnvironmentObject private var appState: AppState
    let onBack: () -> Void

    @State private var renamingAccount: AccountRecord?
    @State private var renameText = ""

    private static let lastRefreshFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    var body: some View {
        MenuPanelScaffold(title: "Manage Accounts", onBack: onBack) {
            VStack(alignment: .leading, spacing: 12) {
                usageRefreshBar

                if appState.accounts.isEmpty {
                    ContentUnavailableView(
                        "No Accounts",
                        systemImage: "person.2",
                        description: Text("Add an account from the home screen.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    ForEach(appState.accounts) { account in
                        MenuAccountCard(
                            account: account,
                            isActive: appState.activeAccountId == account.id,
                            tokenStatus: appState.tokenStatus(for: account),
                            usageState: appState.usageState(for: account),
                            canSwitch: appState.canSwitch(to: account),
                            onSwitch: { appState.switchAccount(account, restartAfter: false) },
                            onRename: {
                                renameText = account.label
                                renamingAccount = account
                            },
                            onDelete: { appState.deleteAccount(account) }
                        )
                    }
                }

                Button {
                    appState.openCodexDirectory()
                } label: {
                    Label("Open ~/.codex folder", systemImage: "folder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .onAppear { appState.reload() }
        .sheet(item: $renamingAccount) { account in
            renameSheet(account)
        }
    }

    private var usageRefreshBar: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Codex usage")
                    .font(.subheadline.weight(.semibold))
                Text(lastRefreshText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                appState.refreshAllUsage()
            } label: {
                if appState.isRefreshingUsage {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Label("Refresh usage", systemImage: "arrow.clockwise")
                }
            }
            .disabled(appState.isRefreshingUsage || appState.accounts.isEmpty)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var lastRefreshText: String {
        if let date = appState.usageLastRefreshedAt {
            return "Last updated \(Self.lastRefreshFormatter.string(from: date))"
        }
        return "Not refreshed yet"
    }

    private func renameSheet(_ account: AccountRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Account")
                .font(.headline)
            TextField("Label", text: $renameText)
            HStack {
                Spacer()
                Button("Cancel") { renamingAccount = nil }
                Button("Save") {
                    let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        appState.renameAccount(account, label: trimmed)
                    }
                    renamingAccount = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
