import Foundation

/// Decides which municipal material is shown for a manual city selection.
/// Rules: the selected city's by-laws are included; the other city's are never
/// included; Peel Region material is included as *regional* material whose own
/// terms define where it applies (the app does not decide road ownership or
/// street-level jurisdiction).
public struct MunicipalApplicability: Sendable {
    public enum Relevance: Equatable, Sendable {
        case selectedCity
        case regional(note: String)
        case otherCity
        case notMunicipal
        case cityNotSelected
    }

    public let selection: CitySelection

    public init(selection: CitySelection) {
        self.selection = selection
    }

    public func relevance(of source: Source) -> Relevance {
        guard source.level == .municipal else { return .notMunicipal }
        guard let muni = source.municipality else { return .cityNotSelected }
        if muni == .peel {
            return .regional(note: "Regional by-law. Where it applies (for example regional roads) depends on the by-law's own terms; the app does not determine road jurisdiction.")
        }
        guard let city = selection.municipality else { return .cityNotSelected }
        return muni == city ? .selectedCity : .otherCity
    }

    /// Sources applicable to the selection. The other city's by-laws are excluded, never substituted.
    public func applicable(_ sources: [Source]) -> [Source] {
        sources.filter {
            switch relevance(of: $0) {
            case .selectedCity, .regional, .notMunicipal: return true
            case .otherCity, .cityNotSelected: return false
            }
        }
    }
}

/// What can be said about the installed text for a given incident date.
public enum VersionAssessment: Equatable, Sendable {
    /// Incident date is on or after the consolidation start and the source states no later amendment.
    case installedVersionCovers(note: String)
    /// Incident date precedes the installed consolidation (or a later amendment): historical text not installed.
    case historicalVersionNotInstalled(note: String)
    /// Incident date is after the date the installed text is stated to be current to.
    case afterInstalledCurrency(note: String)
    /// No usable dates are recorded for the source.
    case unknown(note: String)
    /// No incident date has been entered.
    case incidentDateMissing

    public var note: String {
        switch self {
        case .installedVersionCovers(let n), .historicalVersionNotInstalled(let n), .afterInstalledCurrency(let n), .unknown(let n):
            return n
        case .incidentDateMissing:
            return "Enter the incident date to check which version of the law applies."
        }
    }

    /// True only when the installed text can be used for the incident date without a version warning.
    public var isUsableWithoutWarning: Bool {
        if case .installedVersionCovers = self { return true }
        return false
    }
}

public enum VersionSelector {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/Toronto")
        f.dateFormat = "MMMM d, yyyy"
        return f
    }()

    static func firstDate(in text: String?, after marker: String) -> Date? {
        guard let text = text, let r = text.range(of: marker) else { return nil }
        let tail = text[r.upperBound...]
        let pattern = "[A-Z][a-z]+ \\d{1,2}, \\d{4}"
        guard let m = tail.range(of: pattern, options: .regularExpression) else { return nil }
        return formatter.date(from: String(tail[m]))
    }

    static func anyDate(in text: String?) -> Date? {
        guard let text = text,
              let m = text.range(of: "[A-Z][a-z]+ \\d{1,2}, \\d{4}", options: .regularExpression) else { return nil }
        return formatter.date(from: String(text[m]))
    }

    /// Never treats "imported today" as "current today". Uses only dates printed in the source.
    public static func assess(source: Source, incidentDate: Date?) -> VersionAssessment {
        guard let incident = incidentDate else { return .incidentDateMissing }
        let currentTo = firstDate(in: source.consolidation, after: "Current to")
        let periodFrom = firstDate(in: source.consolidation, after: "From")
        let lastAmended = anyDate(in: source.lastAmended)
        if let from = periodFrom {
            if incident < from {
                return .historicalVersionNotInstalled(note: "The installed consolidation starts \(formatter.string(from: from)). The version in force on the incident date is not installed.")
            }
            return .installedVersionCovers(note: "The incident date falls within the installed consolidation period (from \(formatter.string(from: from))). Currency after the export date is not verified.")
        }
        if let to = currentTo {
            if incident > to {
                return .afterInstalledCurrency(note: "The installed text is stated to be current to \(formatter.string(from: to)). Changes after that date are not reflected.")
            }
            if let la = lastAmended, incident < la {
                return .historicalVersionNotInstalled(note: "The source was last amended \(formatter.string(from: la)), after the incident date. The point-in-time version for the incident date is not installed.")
            }
            if lastAmended == nil && source.level != .constitutional {
                return .unknown(note: "The installed text is current to \(formatter.string(from: to)), but the date of its last amendment is not recorded, so applicability on the incident date cannot be confirmed.")
            }
            return .installedVersionCovers(note: "No amendment after the incident date is indicated by the installed consolidation (current to \(formatter.string(from: to))).")
        }
        return .unknown(note: "No consolidation dates are recorded for this source. Applicability on the incident date cannot be confirmed.")
    }
}
