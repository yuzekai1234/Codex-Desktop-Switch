import SwiftUI

private enum MenuScreen: Equatable {
    case home
    case manageAccounts
    case remoteTunnel
}

struct MenuContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var screen: MenuScreen = .home

    var body: some View {
        Group {
            switch screen {
            case .home:
                homeContent
            case .manageAccounts:
                ManageAccountsView { screen = .home }
            case .remoteTunnel:
                RemoteToolsView { screen = .home }
            }
        }
        .frame(width: MenuPanelMetrics.width)
        .frame(height: screen == .home ? nil : MenuPanelMetrics.subpageHeight)
        .fixedSize(horizontal: false, vertical: screen == .home)
        .menuBarPanelChrome()
        .animation(.easeInOut(duration: 0.18), value: screen)
        .onAppear {
            appState.reload()
            appState.refreshTunnelStatus()
        }
    }

    // MARK: - Home

    private var homeContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 10)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                accountSection
                actionsSection
                statusFooter
            }
            .padding(14)
        }
    }

    private var accountListMaxHeight: CGFloat {
        3 * 50 + 2 * 8
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("C-Switch")
                        .font(.headline)
                    if appState.tunnelRunning {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                            .help("SSH tunnel running")
                    }
                }
                Text("Codex Desktop accounts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if appState.isLoading || appState.loginInProgress {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Accounts")

            if appState.accounts.isEmpty {
                Text("No accounts yet. Use Add account, or sign in with Codex and reopen C-Switch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if appState.accounts.count > 3 {
                ScrollView(.vertical, showsIndicators: true) {
                    accountRows
                }
                .frame(maxHeight: accountListMaxHeight)
            } else {
                accountRows
            }
        }
    }

    private var accountRows: some View {
        VStack(spacing: 6) {
            ForEach(appState.accounts) { account in
                Button {
                    appState.switchAccount(account)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: appState.activeAccountId == account.id
                            ? "largecircle.fill.circle"
                            : "circle")
                            .foregroundStyle(appState.activeAccountId == account.id
                                ? Color.accentColor
                                : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.label)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if let email = account.email, email != account.label {
                                Text(email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 4)
                        if let plan = account.plan {
                            Text(plan.capitalized)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(appState.isLoading || appState.loginInProgress || !appState.canSwitch(to: account))
            }
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Actions")

            VStack(spacing: 5) {
                MenuActionRow("Add account (browser login)", systemImage: "person.badge.plus", disabled: appState.loginInProgress) {
                    appState.addAccountViaOAuth()
                }

                if appState.loginInProgress {
                    MenuActionRow("Cancel login", systemImage: "xmark.circle", role: .cancel) {
                        appState.cancelLogin()
                    }
                }

                MenuActionRow("Manage accounts", systemImage: "gearshape") {
                    screen = .manageAccounts
                }

                MenuActionRow("Remote & Tunnel", systemImage: "server.rack") {
                    screen = .remoteTunnel
                }

                MenuActionRow("Restart Codex Desktop", systemImage: "arrow.clockwise") {
                    appState.restartCodex()
                }

                MenuActionRow("Quit C-Switch", systemImage: "power", role: .destructive) {
                    appState.quitApp()
                }
            }
        }
    }

    @ViewBuilder
    private var statusFooter: some View {
        if let error = appState.errorMessage {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        if appState.showRestartPrompt {
            restartBanner
        }
    }

    private var restartBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label = appState.lastSwitchedLabel {
                Text("Switched to \(label). Restart Codex to apply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Restart Codex") {
                    appState.restartCodex()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("Later") {
                    appState.showRestartPrompt = false
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

/// Sub-page: back row + scrollable body.
struct MenuPanelScaffold<Content: View>: View {
    let title: String
    let onBack: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(.quaternary.opacity(0.8), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help("Back")

                Text(title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }
    }
}

struct MenuAccountCard: View {
    let account: AccountRecord
    let isActive: Bool
    let tokenStatus: String
    let usageState: AccountUsageState
    let canSwitch: Bool
    let onSwitch: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.label)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    if let email = account.email, email != account.label {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if isActive {
                    Text("Active")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor, in: Capsule())
                }
            }

            HStack(spacing: 14) {
                Label(tokenStatus, systemImage: "key")
                if case .loaded = usageState {
                    EmptyView()
                } else if let plan = account.plan {
                    Label(plan.capitalized, systemImage: "creditcard")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            CodexUsageRows(state: usageState)

            HStack(spacing: 8) {
                Button("Switch", action: onSwitch)
                    .disabled(!canSwitch)
                Button("Rename", action: onRename)
                Button("Delete", role: .destructive, action: onDelete)
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct MenuActionRow: View {
    let title: String
    let systemImage: String
    let role: ButtonRole?
    let disabled: Bool
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.disabled = disabled
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }
}
