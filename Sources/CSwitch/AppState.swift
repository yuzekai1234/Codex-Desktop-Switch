import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var accounts: [AccountRecord] = []
    @Published var activeAccountId: UUID?
    @Published var isLoading = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var showRestartPrompt = false
    @Published var lastSwitchedLabel: String?
    @Published var loginInProgress = false

    @Published var remoteSettings: RemoteSettings = .defaults
    @Published var tunnelRunning = false
    @Published var tunnelLastError: String?
    @Published var isRemoteBusy = false
    @Published var tunnelPID: Int32?

    @Published var usageByAccountId: [UUID: AccountUsageState] = [:]
    @Published var isRefreshingUsage = false
    @Published var usageLastRefreshedAt: Date?

    private let store = AccountStore.shared
    private let remoteSettingsStore = RemoteSettingsStore.shared
    private let authRemoteSync = AuthRemoteSyncService()
    private let tunnelManager = SSHTunnelManager.shared
    private let switcher = AuthSwitcher()
    private let oauth = OAuthService()
    private let relauncher = CodexRelauncher()

    init() {
        remoteSettings = remoteSettingsStore.load()
        applyTunnelSnapshot(tunnelManager.snapshot())
        store.repairMissingTokenFiles()
        reload()
    }

    var tunnelStatusText: String {
        if tunnelRunning {
            return "Tunnel running"
        }
        if let tunnelLastError {
            return "Tunnel stopped: \(tunnelLastError)"
        }
        return "Tunnel stopped"
    }

    func reload() {
        store.repairMissingTokenFiles()
        do {
            let manifest = try store.loadManifest()
            // Keep stable list order (when added), not re-sort by last switch.
            accounts = manifest.accounts.sorted { $0.createdAt < $1.createdAt }
            activeAccountId = manifest.activeAccountId
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func commitRemoteSettings(_ settings: RemoteSettings) {
        do {
            let validated = try settings.validated()
            try remoteSettingsStore.save(validated)
            remoteSettings = validated
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshTunnelStatus() {
        applyTunnelSnapshot(tunnelManager.snapshot())
    }

    private func applyTunnelSnapshot(_ snapshot: TunnelSnapshot) {
        tunnelRunning = snapshot.isRunning
        tunnelPID = snapshot.pid
        tunnelLastError = snapshot.lastError
    }

    func startTunnel(using settings: RemoteSettings) {
        let snapshot = settings
        Task { @MainActor in
            await performStartTunnel(using: snapshot)
        }
    }

    func stopTunnel() {
        Task { @MainActor in
            await performStopTunnel()
        }
    }

    private func performStartTunnel(using settings: RemoteSettings) async {
        guard !isRemoteBusy else { return }
        isRemoteBusy = true
        defer { isRemoteBusy = false }

        await Task.yield()

        errorMessage = nil
        tunnelLastError = nil
        statusMessage = nil

        do {
            let validated = try settings.validated()
            try remoteSettingsStore.save(validated)

            try await Task.detached(priority: .userInitiated) {
                try SSHTunnelManager.shared.start(settings: validated)
            }.value

            remoteSettings = validated
            applyTunnelSnapshot(tunnelManager.snapshot())
            statusMessage = "Tunnel started"
        } catch {
            applyTunnelSnapshot(tunnelManager.snapshot())
            errorMessage = error.localizedDescription
        }
    }

    private func performStopTunnel() async {
        guard !isRemoteBusy else { return }
        isRemoteBusy = true
        defer { isRemoteBusy = false }

        await Task.yield()

        await Task.detached(priority: .userInitiated) {
            SSHTunnelManager.shared.stop()
        }.value

        applyTunnelSnapshot(tunnelManager.snapshot())
        statusMessage = "Tunnel stopped"
    }

    func syncAuthToRemote(using settings: RemoteSettings) {
        guard !isRemoteBusy else { return }
        isRemoteBusy = true
        errorMessage = nil

        Task { @MainActor in
            do {
                let validated = try settings.validated()
                try remoteSettingsStore.save(validated)
                remoteSettings = validated
                try authRemoteSync.sync(settings: validated)
                statusMessage = "Synced auth.json to \(validated.sshTarget):\(validated.remoteAuthPath)"
            } catch {
                errorMessage = error.localizedDescription
            }
            isRemoteBusy = false
        }
    }

    func shutdownRemoteServices() {
        tunnelManager.stopIfRunning()
        applyTunnelSnapshot(tunnelManager.snapshot())
    }

    func switchAccount(_ account: AccountRecord, restartAfter: Bool = false) {
        isLoading = true
        errorMessage = nil
        Task { @MainActor in
            do {
                try store.ensureCredentials(for: account)
                _ = try await switcher.switchToAccount(account)
                reload()
                lastSwitchedLabel = account.label
                showRestartPrompt = true
                statusMessage = "Switched to \(account.label)"
                if restartAfter {
                    restartCodex()
                }
            } catch {
                errorMessage = error.localizedDescription
                try? switcher.rollbackFromBackup()
            }
            isLoading = false
        }
    }

    func addAccountViaOAuth(setActive: Bool = true) {
        guard !loginInProgress else { return }
        loginInProgress = true
        errorMessage = nil
        statusMessage = "Complete login in your browser…"

        Task { @MainActor in
            do {
                let tokens = try await oauth.login()
                let email = JWTParser.email(from: tokens.idToken) ?? "New Account"
                let record = try store.upsertAccount(label: email, tokens: tokens)
                if setActive {
                    _ = try await switcher.switchToAccount(record)
                    lastSwitchedLabel = record.label
                    showRestartPrompt = true
                }
                reload()
                statusMessage = "Added \(record.label)"
            } catch {
                errorMessage = error.localizedDescription
            }
            loginInProgress = false
        }
    }

    func deleteAccount(_ account: AccountRecord) {
        Task { @MainActor in
            do {
                try store.deleteAccount(id: account.id)
                reload()
                statusMessage = "Deleted \(account.label)"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func renameAccount(_ account: AccountRecord, label: String) {
        Task { @MainActor in
            do {
                try store.renameAccount(id: account.id, label: label)
                reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func restartCodex() {
        showRestartPrompt = false
        statusMessage = "Restarting Codex Desktop…"
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try CodexRelauncher().restartCodex()
                }.value
                statusMessage = "Restarted Codex Desktop"
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = nil
            }
        }
    }

    func cancelLogin() {
        oauth.cancelLogin()
        loginInProgress = false
        statusMessage = nil
    }

    func openCodexDirectory() {
        NSWorkspace.shared.open(store.codexHome)
    }

    func quitApp() {
        shutdownRemoteServices()
        NSApplication.shared.terminate(nil)
    }

    func canSwitch(to account: AccountRecord) -> Bool {
        store.hasUsableCredentials(for: account)
    }

    func tokenStatus(for account: AccountRecord) -> String {
        if store.hasStoredCredentials(accountId: account.id),
           let tokens = try? store.loadTokens(accountId: account.id) {
            return JWTParser.isExpired(tokens.idToken) ? "Expired" : "Saved"
        }
        if store.canRestoreFromCurrentAuth(account) {
            return "Can pull from Codex"
        }
        return "Not saved"
    }

    func usageState(for account: AccountRecord) -> AccountUsageState {
        usageByAccountId[account.id] ?? .idle
    }

    func refreshAllUsage() {
        guard !isRefreshingUsage else { return }
        isRefreshingUsage = true

        let accountList = accounts
        for account in accountList {
            if store.hasStoredCredentials(accountId: account.id) {
                usageByAccountId[account.id] = .loading
            } else {
                usageByAccountId[account.id] = .failed("Sign in via browser to load usage")
            }
        }

        Task { @MainActor in
            let results = await withTaskGroup(of: (UUID, AccountUsageState).self) { group in
                for account in accountList {
                    guard store.hasStoredCredentials(accountId: account.id) else { continue }
                    let accountId = account.id
                    group.addTask {
                        await Self.loadUsageState(accountId: accountId)
                    }
                }

                var collected: [(UUID, AccountUsageState)] = []
                for await pair in group {
                    collected.append(pair)
                }
                return collected
            }

            for (id, state) in results {
                usageByAccountId[id] = state
            }

            reload()
            usageLastRefreshedAt = Date()
            isRefreshingUsage = false
        }
    }

    private nonisolated static func loadUsageState(accountId: UUID) async -> (UUID, AccountUsageState) {
        let store = AccountStore.shared
        let service = CodexUsageService()
        do {
            let tokens = try store.loadTokens(accountId: accountId)
            let (snapshot, refreshed) = try await service.fetchUsage(tokens: tokens)
            if refreshed != tokens {
                try store.saveTokens(refreshed, accountId: accountId)
            }
            if let plan = snapshot.displayPlan {
                try? store.updateAccountPlan(id: accountId, plan: plan)
            }
            return (accountId, .loaded(snapshot))
        } catch {
            return (accountId, .failed(error.localizedDescription))
        }
    }
}
