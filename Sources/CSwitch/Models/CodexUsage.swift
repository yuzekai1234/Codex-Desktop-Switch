import Foundation

struct CodexRateLimitWindow: Equatable, Sendable {
    var usedPercent: Int
    var resetAt: Date
    var limitWindowSeconds: Int

    var progressFraction: Double {
        min(max(Double(usedPercent) / 100.0, 0), 1)
    }

    var isOverLimit: Bool { usedPercent > 100 }

    var windowLabel: String {
        switch limitWindowSeconds {
        case 18_000: return "5 hours"
        case 604_800: return "7 days"
        default:
            let hours = limitWindowSeconds / 3600
            return hours >= 24 ? "\(hours / 24)d window" : "\(hours)h window"
        }
    }

    func resetDescription(relativeTo now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: resetAt, relativeTo: now)
    }
}

struct CodexUsageSnapshot: Equatable, Sendable {
    var planType: String?
    var primary: CodexRateLimitWindow
    var secondary: CodexRateLimitWindow
    var codeReview: CodexRateLimitWindow?
    var creditsBalance: Double?
    var creditsUnlimited: Bool
    var fetchedAt: Date

    var displayPlan: String? {
        planType?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

enum AccountUsageState: Equatable, Sendable {
    case idle
    case loading
    case loaded(CodexUsageSnapshot)
    case failed(String)
}

// MARK: - API response

struct CodexUsageAPIResponse: Decodable {
    var planType: String?
    var rateLimit: CodexUsageRateLimit?
    var codeReviewRateLimit: CodexUsageRateLimit?
    var credits: CodexUsageCredits?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case codeReviewRateLimit = "code_review_rate_limit"
        case credits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        planType = try container.decodeIfPresent(FlexibleString.self, forKey: .planType)?.value
        rateLimit = try container.decodeIfPresent(CodexUsageRateLimit.self, forKey: .rateLimit)
        codeReviewRateLimit = try container.decodeIfPresent(CodexUsageRateLimit.self, forKey: .codeReviewRateLimit)
        credits = try container.decodeIfPresent(CodexUsageCredits.self, forKey: .credits)
    }

    func toSnapshot(fetchedAt: Date = Date()) throws -> CodexUsageSnapshot {
        guard let rateLimit,
              let primary = rateLimit.primaryWindow?.toWindow(),
              let secondary = rateLimit.secondaryWindow?.toWindow()
        else {
            throw CodexUsageError.invalidResponse
        }

        return CodexUsageSnapshot(
            planType: planType,
            primary: primary,
            secondary: secondary,
            codeReview: codeReviewRateLimit?.primaryWindow?.toWindow(),
            creditsBalance: credits?.parsedBalance,
            creditsUnlimited: credits?.unlimited ?? false,
            fetchedAt: fetchedAt
        )
    }
}

struct CodexUsageRateLimit: Decodable {
    var primaryWindow: CodexUsageWindowJSON?
    var secondaryWindow: CodexUsageWindowJSON?

    enum CodingKeys: String, CodingKey {
        case allowed
        case limitReached = "limit_reached"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _ = try container.decodeIfPresent(Bool.self, forKey: .allowed)
        _ = try container.decodeIfPresent(Bool.self, forKey: .limitReached)
        primaryWindow = try container.decodeIfPresent(CodexUsageWindowJSON.self, forKey: .primaryWindow)
        secondaryWindow = try container.decodeIfPresent(CodexUsageWindowJSON.self, forKey: .secondaryWindow)
    }
}

struct CodexUsageWindowJSON: Decodable {
    var usedPercent: FlexibleInt?
    var resetAt: FlexibleTimestamp?
    var limitWindowSeconds: FlexibleInt?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetAt = "reset_at"
        case resetAfterSeconds = "reset_after_seconds"
        case limitWindowSeconds = "limit_window_seconds"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = try container.decodeIfPresent(FlexibleInt.self, forKey: .usedPercent)
        if let reset = try container.decodeIfPresent(FlexibleTimestamp.self, forKey: .resetAt) {
            resetAt = reset
        } else if let after = try container.decodeIfPresent(FlexibleInt.self, forKey: .resetAfterSeconds) {
            resetAt = FlexibleTimestamp(secondsSince1970: TimeInterval(after.value))
        } else {
            resetAt = nil
        }
        limitWindowSeconds = try container.decodeIfPresent(FlexibleInt.self, forKey: .limitWindowSeconds)
    }

    func toWindow() -> CodexRateLimitWindow? {
        guard let usedPercent, let resetAt, let limitWindowSeconds else { return nil }
        return CodexRateLimitWindow(
            usedPercent: usedPercent.value,
            resetAt: resetAt.date,
            limitWindowSeconds: limitWindowSeconds.value
        )
    }
}

struct CodexUsageCredits: Decodable {
    var hasCredits: Bool?
    var unlimited: Bool?
    private var balanceRaw: FlexibleDouble?

    var parsedBalance: Double? { balanceRaw?.value }

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCredits = try container.decodeIfPresent(Bool.self, forKey: .hasCredits)
        unlimited = try container.decodeIfPresent(Bool.self, forKey: .unlimited)
        balanceRaw = try container.decodeIfPresent(FlexibleDouble.self, forKey: .balance)
    }
}

// MARK: - Flexible JSON helpers

struct FlexibleInt: Decodable {
    let value: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = Int(doubleValue.rounded())
        } else if let stringValue = try? container.decode(String.self),
                  let parsed = Double(stringValue)
        {
            value = Int(parsed.rounded())
        } else {
            throw DecodingError.typeMismatch(
                Int.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected numeric used_percent")
            )
        }
    }
}

struct FlexibleDouble: Decodable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let intValue = try? container.decode(Int.self) {
            value = Double(intValue)
        } else if let stringValue = try? container.decode(String.self),
                  let parsed = Double(stringValue)
        {
            value = parsed
        } else {
            throw DecodingError.typeMismatch(
                Double.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected numeric balance")
            )
        }
    }
}

struct FlexibleString: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected string plan_type")
            )
        }
    }
}

struct FlexibleTimestamp: Decodable {
    let date: Date

    init(secondsSince1970: TimeInterval) {
        date = Date(timeIntervalSince1970: secondsSince1970)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let seconds: TimeInterval
        if let intValue = try? container.decode(Int.self) {
            seconds = TimeInterval(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            seconds = doubleValue
        } else if let stringValue = try? container.decode(String.self),
                  let parsed = Double(stringValue)
        {
            seconds = parsed
        } else {
            throw DecodingError.typeMismatch(
                Date.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected unix timestamp")
            )
        }
        // Milliseconds if value looks like ms since epoch (> year 2100 in seconds).
        if seconds > 4_000_000_000 {
            date = Date(timeIntervalSince1970: seconds / 1000.0)
        } else {
            date = Date(timeIntervalSince1970: seconds)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
