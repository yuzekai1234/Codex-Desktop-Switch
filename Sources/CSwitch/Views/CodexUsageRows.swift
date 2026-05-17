import SwiftUI

struct CodexUsageRows: View {
    let state: AccountUsageState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch state {
            case .idle:
                Text("Tap Refresh usage above to load quota")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading usage…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            case .loaded(let snapshot):
                usageContent(snapshot)
            }
        }
    }

    @ViewBuilder
    private func usageContent(_ snapshot: CodexUsageSnapshot) -> some View {
        if let plan = snapshot.displayPlan {
            Label(plan.capitalized, systemImage: "creditcard")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        usageWindowRow(title: "5 hours", window: snapshot.primary)
        usageWindowRow(title: "7 days", window: snapshot.secondary)

        if let codeReview = snapshot.codeReview {
            usageWindowRow(title: "Code review", window: codeReview)
        }

        if snapshot.creditsUnlimited {
            Label("Credits unlimited", systemImage: "infinity")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let balance = snapshot.creditsBalance {
            Label(String(format: "Credits: %.2f", balance), systemImage: "dollarsign.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func usageWindowRow(title: String, window: CodexRateLimitWindow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
                Spacer()
                Text("\(window.usedPercent)% used")
                    .font(.caption)
                    .foregroundStyle(window.isOverLimit ? .red : .secondary)
            }
            ProgressView(value: window.progressFraction)
                .tint(window.isOverLimit ? .red : .accentColor)
            Text("Resets \(window.resetDescription())")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
