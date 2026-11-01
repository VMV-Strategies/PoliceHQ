import Foundation

public enum ExplanationLevel: String, Codable, CaseIterable, Sendable, Identifiable {
    case verySimple = "very-simple"
    case plainLanguage = "plain-language"
    case detailed
    case legalAnalysis = "legal-analysis"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .verySimple: return "Very simple"
        case .plainLanguage: return "Plain language"
        case .detailed: return "Detailed"
        case .legalAnalysis: return "Legal analysis"
        }
    }
}

/// The parts of a guide that never change with the explanation level.
public struct InvariantContent: Equatable, Sendable {
    public let quotes: [GuideQuote]
    public let conditions: [String]
    public let limits: [String]
    public let citations: [GuideCitation]
    public let gaps: [String]
    public let reviewStatus: ReviewStatus
}

/// A guide rendered at a level. Only `summary` and `showFullExcerpts` vary.
public struct ExplainedGuide: Sendable {
    public let invariant: InvariantContent
    /// Drafted plain-language aid (labelled), or nil — in which case supported wording is shown instead.
    public let summary: String?
    public let summaryLabel: String
    public let showFullExcerpts: Bool
}

public enum ExplanationRenderer {
    public static func render(_ entry: GuideEntry, level: ExplanationLevel) -> ExplainedGuide {
        let b = entry.body
        let invariant = InvariantContent(
            quotes: b.quotes ?? [],
            conditions: b.conditions ?? [],
            limits: (b.limits ?? []) + (b.limitations ?? []),
            citations: entry.citations,
            gaps: b.gaps ?? [],
            reviewStatus: entry.reviewStatus)
        let s: String?
        switch level {
        case .verySimple: s = b.summaries?.verySimple
        case .plainLanguage: s = b.summaries?.plain
        case .detailed: s = b.summaries?.detailed
        case .legalAnalysis: s = nil
        }
        let label: String
        if s == nil {
            label = level == .legalAnalysis
                ? "Legal analysis: full installed text of each cited provision."
                : "No reviewed simplification is installed for this guide. The supported wording is shown instead."
        } else {
            label = entry.reviewStatus == .approved
                ? "Reviewed explanation (\(level.title.lowercased()))."
                : "Draft explanation (\(level.title.lowercased())) — not reviewed. The quoted legal wording below governs."
        }
        return ExplainedGuide(invariant: invariant, summary: s, summaryLabel: label,
                              showFullExcerpts: level == .legalAnalysis || level == .detailed || s == nil)
    }
}

/// Caution presentation. Approved wording is shown exactly as installed, at every level;
/// when none is installed, the app says so and never substitutes generated text.
public enum CautionPresentation: Equatable, Sendable {
    case approvedWording(text: String, organization: String, version: String)
    case approvedWordingNotInstalled(missing: String)

    public static func make(for entry: GuideEntry, level: ExplanationLevel) -> CautionPresentation {
        // `level` is accepted deliberately and ignored: explanation settings never alter wording.
        _ = level
        if let w = entry.body.approvedWording, !w.isEmpty, entry.reviewStatus == .approved,
           let org = entry.body.approvingOrganization, !org.isEmpty {
            return .approvedWording(text: w, organization: org, version: entry.version)
        }
        return .approvedWordingNotInstalled(missing: entry.body.missingMaterial ?? "Approved wording and its approval record.")
    }

    public static let notInstalledTitle = "Approved wording not installed."
}
