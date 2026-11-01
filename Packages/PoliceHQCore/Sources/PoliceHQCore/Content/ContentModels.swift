import Foundation

// MARK: - Jurisdiction

/// Legislative level. The Constitution is its own level and is never treated as an ordinary federal statute.
public enum LegislativeLevel: String, Codable, CaseIterable, Sendable {
    case constitutional, federal, provincial, municipal

    public var displayName: String {
        switch self {
        case .constitutional: return "Constitutional"
        case .federal: return "Federal"
        case .provincial: return "Provincial"
        case .municipal: return "Municipal"
        }
    }
}

/// Municipal bodies covered by the installed material.
public enum Municipality: String, Codable, CaseIterable, Sendable {
    case peel, brampton, mississauga

    public var displayName: String {
        switch self {
        case .peel: return "Peel Region"
        case .brampton: return "Brampton"
        case .mississauga: return "Mississauga"
        }
    }
}

/// The user's manual city selection (no GPS, no network).
public enum CitySelection: String, Codable, CaseIterable, Sendable {
    case notSelected, brampton, mississauga

    public var municipality: Municipality? {
        switch self {
        case .notSelected: return nil
        case .brampton: return .brampton
        case .mississauga: return .mississauga
        }
    }
}

// MARK: - Sources and provisions

public enum ExtractionQuality: String, Codable, Sendable {
    case automatedChecksPassed = "automated-checks-passed"
    case passedWithWarnings = "passed-with-warnings"
    case heuristicStructure = "heuristic-structure"
    case imageOnly = "image-only"
    case unusable

    public var label: String {
        switch self {
        case .automatedChecksPassed: return "Automated extraction checks passed"
        case .passedWithWarnings: return "Automated checks passed with warnings"
        case .heuristicStructure: return "Structure parsed heuristically — verify against original"
        case .imageOnly: return "Image content — view original"
        case .unusable: return "Unusable extraction"
        }
    }
}

/// Distinct editorial / legal-review states. Importing never creates reviewed guidance.
public enum ReviewStatus: String, Codable, CaseIterable, Sendable {
    case imported
    case extractionVerified = "extraction-verified"
    case interpretationDrafted = "interpretation-drafted"
    case legalReviewRecorded = "legal-review-recorded"
    case approved

    public var label: String {
        switch self {
        case .imported: return "Imported source"
        case .extractionVerified: return "Extraction verified"
        case .interpretationDrafted: return "Draft — review required"
        case .legalReviewRecorded: return "Qualified legal review recorded"
        case .approved: return "Approved for a defined operational scope"
        }
    }

    /// Only these states may be presented as operational guidance.
    public var isOperationallyApproved: Bool { self == .approved }
}

public enum ProvisionStatus: String, Codable, Sendable {
    case inForce = "in-force"
    case notYetInForce = "not-yet-in-force"
    case repealed
    case annotation
    case unknown

    public var label: String {
        switch self {
        case .inForce: return "In force (as consolidated)"
        case .notYetInForce: return "Not yet in force"
        case .repealed: return "Repealed"
        case .annotation: return "Editorial annotation"
        case .unknown: return "Status unknown"
        }
    }
}

public struct Source: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let title: String
    public let citation: String?
    public let abbreviations: [String]
    public let docType: String
    public let level: LegislativeLevel
    public let jurisdictionLabel: String
    public let municipality: Municipality?
    public let municipalityBasis: String?
    public let issuingAuthority: String?
    public let territorialApplication: String?
    public let enforcementResponsibility: String?
    public let officialURL: String?
    public let officialURLStatus: String
    public let originalFilename: String
    public let sha256: String
    public let originalPath: String?
    public let format: String
    public let pages: Int?
    public let consolidation: String?
    public let lastAmended: String?
    public let verificationStatus: String
    public let verificationDate: String?
    public let publisherStatus: String
    public let extractionMethod: String
    public let extractionQuality: ExtractionQuality
    public let qualityNotes: String?
    public let reviewStatus: ReviewStatus
    public let trustedForGuidance: Bool
    public let languageHandling: String?

    public var isReferenceConversion: Bool { publisherStatus.hasPrefix("reference conversion") }

    /// Notice required when reproducing legislation: copies in this app are never official versions.
    public var reproductionNotice: String {
        switch level {
        case .federal, .constitutional:
            return "Unofficial reproduction — not an official version. Federal enactments reproduced under the Reproduction of Federal Law Order (SI/97-5); accuracy is not guaranteed."
        case .provincial:
            return "Unofficial reproduction — not an official version. © King's Printer for Ontario (year of first publication as shown in the original)."
        case .municipal:
            return "Unofficial copy as supplied — not an official version. Redistribution rights for this by-law have not been established."
        }
    }

    /// Short currency line for document headers. Never says "current"; it reports what the document states.
    public var currencyLine: String {
        var parts: [String] = []
        if let c = consolidation, !c.isEmpty, c != "Unknown" { parts.append(c) } else { parts.append("Consolidation date unknown") }
        if let l = lastAmended, !l.isEmpty, l != "Unknown" { parts.append(l.hasPrefix("Last") ? l : "Last amended \(l)") }
        parts.append(verificationStatus == "Not verified" ? "Not verified against publisher" : "Publisher check: \(verificationStatus)")
        return parts.joined(separator: " · ")
    }
}

public struct Provision: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let sourceID: String
    public let parentID: String?
    public let kind: String
    public let number: String?
    public let path: String
    public let label: String
    public let heading: String?
    public let text: String?
    public let status: ProvisionStatus
    public let history: String?
    public let notes: [String]
    public let pageStart: Int?
    public let pageEnd: Int?
    public let ordinal: Int
    public let depth: Int

    public var isStructural: Bool { kind == "part" || kind == "schedule" || kind == "heading" }
}

public struct PageRecord: Hashable, Codable, Sendable {
    public let sourceID: String
    public let page: Int
    public let region: String?
    public let text: String
    public let isOCR: Bool
    public let isImageOnly: Bool
}

public struct Definition: Hashable, Sendable {
    public let sourceID: String
    public let term: String
    public let provisionID: String
}

public struct CoverageGap: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let category: String
    public let title: String
    public let description: String
    public let affects: [String]
    public let acquisition: String?
}

public struct PackageInfo: Hashable, Sendable {
    public let values: [String: String]
    public var packageVersion: String { values["package_version"] ?? "Unknown" }
    public var schemaVersion: Int { Int(values["schema_version"] ?? "") ?? 0 }
    public var publishedAt: String { values["package_published_at"] ?? "Unknown" }
    public var importDate: String { values["import_date"] ?? "Unknown" }
}

// MARK: - Guides

public enum GuideKind: String, Codable, CaseIterable, Sendable {
    case authority, right, caution, offence, checklist
}

/// The six authority categories, kept distinct.
public enum AuthorityCategory: String, Codable, CaseIterable, Sendable {
    case arrest, detention, search, seizure, entry, release

    public var title: String {
        switch self {
        case .arrest: return "Arrest"
        case .detention: return "Detention"
        case .search: return "Search"
        case .seizure: return "Seizure"
        case .entry: return "Entry"
        case .release: return "Release and post-action obligations"
        }
    }

    /// SF Symbol names; always shown with the text label (never colour alone).
    public var symbolName: String {
        switch self {
        case .arrest: return "figure.walk.motion"
        case .detention: return "hand.raised"
        case .search: return "magnifyingglass"
        case .seizure: return "shippingbox"
        case .entry: return "door.left.hand.open"
        case .release: return "arrow.uturn.right.circle"
        }
    }
}

/// Encounter stages used by the Rights hub and timeline.
public enum EncounterStage: String, Codable, CaseIterable, Sendable {
    case initialInteraction = "initial-interaction"
    case detention
    case arrest
    case questioning
    case searchSeizure = "search-seizure"
    case custodyRelease = "custody-release"

    public var title: String {
        switch self {
        case .initialInteraction: return "Initial interaction"
        case .detention: return "Detention"
        case .arrest: return "Arrest"
        case .questioning: return "Questioning or statement-taking"
        case .searchSeizure: return "Search or seizure"
        case .custodyRelease: return "Custody and release"
        }
    }
}

public struct GuideQuote: Codable, Hashable, Sendable {
    public let citation: Int
    public let label: String?
    public let text: String
}

public struct GuideSummaries: Codable, Hashable, Sendable {
    public let verySimple: String?
    public let plain: String?
    public let detailed: String?
}

public struct DeadlineRuleDef: Codable, Hashable, Sendable {
    public let trigger: String
    public let statutoryText: String
    public let validated: Bool
}

public struct OffenceMode: Codable, Hashable, Sendable {
    public let id: String
    public let label: String
}

public struct OffenceElementDef: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let text: String
    public let citation: Int?
    public let quote: String?
    public let general: Bool?
    public let basis: String?

    public var isGeneralFact: Bool { general ?? false }
}

public struct DefenceDef: Codable, Hashable, Sendable {
    public let text: String
    public let citation: Int
    public let quote: String
}

public struct ChecklistItemDef: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let requirement: String
    public let trigger: String
    public let applicability: String
    public let condition: String?
    public let citation: Int?
    public let quote: String?
    public let general: Bool?
    public let basis: String?
}

/// Union of the structured fields used by the different guide kinds. Unused fields are nil.
public struct GuideBody: Codable, Hashable, Sendable {
    // authority
    public var basisType: String?
    public var pathway: String?
    public var action: String?
    public var permits: String?
    public var who: String?
    public var territorialScope: String?
    public var quotes: [GuideQuote]?
    public var conditions: [String]?
    public var limits: [String]?
    public var judicialAuthorization: String?
    public var notAuthorityFor: [String]?
    public var linkedRights: [String]?
    public var linkedCautions: [String]?
    public var linkedChecklists: [String]?
    public var linkedAuthorities: [String]?
    public var documentation: [String]?
    public var followUp: [String]?
    public var gaps: [String]?
    public var summaries: GuideSummaries?
    public var deadlineRule: DeadlineRuleDef?
    // rights
    public var stages: [String]?
    public var youth: Bool?
    public var protects: String?
    public var triggers: String?
    public var officerObligations: [String]?
    public var timing: String?
    public var limitations: [String]?
    public var communication: [String]?
    // cautions
    public var approvedWording: String?
    public var missingMaterial: String?
    public var purpose: String?
    public var applicableCircumstances: String?
    public var approvingOrganization: String?
    public var accompanyingSteps: [String]?
    public var statutoryContentNote: String?
    // offences
    public var jurisdictionLabel: String?
    public var procedure: String?
    public var keywords: [String]?
    public var modes: [OffenceMode]?
    public var elements: [OffenceElementDef]?
    public var defences: [DefenceDef]?
    public var exculpatoryPrompts: [String]?
    public var lawfulQuestions: [String]?
    public var relatedAuthorities: [String]?
    public var municipalReferences: [String]?
    // checklists
    public var trigger: String?
    public var items: [ChecklistItemDef]?

    public init() {}
}

public struct GuideCitation: Hashable, Codable, Sendable, Identifiable {
    public var id: String { "\(entryID)#\(index)" }
    public let entryID: String
    public let index: Int
    public let role: String
    public let sourceID: String
    public let provisionID: String
    public let pinpoint: String
    /// Verbatim installed text of the cited provision subtree.
    public let excerpt: String
}

public struct GuideEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: GuideKind
    public let category: String?
    public let title: String
    public let reviewStatus: ReviewStatus
    public let version: String
    public let body: GuideBody
    public var citations: [GuideCitation]

    public var authorityCategory: AuthorityCategory? {
        kind == .authority ? category.flatMap(AuthorityCategory.init(rawValue:)) : nil
    }
}

// MARK: - Penalties

public enum PenaltyComponentKind: String, Codable, Sendable {
    case setFine = "set-fine"
    case victimFineSurcharge = "victim-fine-surcharge"
    case courtCosts = "court-costs"
    case otherCharge = "other-charge"
    case demeritPoints = "demerit-points"
    case statutoryRange = "statutory-range"
    case administrativePenalty = "administrative-penalty"
}

public enum PenaltyDataStatus: String, Codable, Sendable {
    case verifiedExtraction = "verified-extraction"
    case notInstalled = "not-installed"
    case notVerified = "not-verified"
    case notApplicable = "not-applicable"
}

public struct PenaltyComponentRecord: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let offenceEntryID: String?
    public let jurisdiction: String
    public let component: PenaltyComponentKind
    public let amountCents: Int?
    public let points: Int?
    public let rangeMinCents: Int?
    public let rangeMaxCents: Int?
    public let status: PenaltyDataStatus
    public let provisionID: String?
    public let excerpt: String?
    public let effectiveFrom: String?
    public let effectiveTo: String?
    public let dateTrigger: String?
    public let conditionsJSON: String?
    public let notes: String?

    public init(id: String, offenceEntryID: String?, jurisdiction: String, component: PenaltyComponentKind,
                amountCents: Int? = nil, points: Int? = nil, rangeMinCents: Int? = nil, rangeMaxCents: Int? = nil,
                status: PenaltyDataStatus, provisionID: String? = nil, excerpt: String? = nil,
                effectiveFrom: String? = nil, effectiveTo: String? = nil, dateTrigger: String? = nil,
                conditionsJSON: String? = nil, notes: String? = nil) {
        self.id = id
        self.offenceEntryID = offenceEntryID
        self.jurisdiction = jurisdiction
        self.component = component
        self.amountCents = amountCents
        self.points = points
        self.rangeMinCents = rangeMinCents
        self.rangeMaxCents = rangeMaxCents
        self.status = status
        self.provisionID = provisionID
        self.excerpt = excerpt
        self.effectiveFrom = effectiveFrom
        self.effectiveTo = effectiveTo
        self.dateTrigger = dateTrigger
        self.conditionsJSON = conditionsJSON
        self.notes = notes
    }
}
