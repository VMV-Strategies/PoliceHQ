import Foundation

/// Where a piece of information came from. Provenance is never upgraded automatically:
/// an allegation stays an allegation; unknown stays unknown.
public enum FactProvenance: String, Codable, CaseIterable, Sendable {
    case officerObservation = "officer-observation"
    case witnessAccount = "witness-account"
    case documentary
    case allegation
    case userInference = "user-inference"
    case unknown

    public var title: String {
        switch self {
        case .officerObservation: return "Officer observation"
        case .witnessAccount: return "Witness account"
        case .documentary: return "Documentary information"
        case .allegation: return "Allegation"
        case .userInference: return "User inference"
        case .unknown: return "Unknown"
        }
    }
}

/// Facts proposed by the on-device model are held separately until the user confirms them.
public enum FactOrigin: String, Codable, Sendable {
    case userEntered = "user-entered"
    case modelProposedConfirmed = "model-proposed-confirmed"
}

public struct Fact: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var text: String
    public var provenance: FactProvenance
    public var origin: FactOrigin
    public var source: String?          // e.g. witness name/role or document reference (user-entered)
    public let createdAt: Date
    public var supersededBy: UUID?      // later correction; original retained

    public init(id: UUID = UUID(), text: String, provenance: FactProvenance, origin: FactOrigin = .userEntered,
                source: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.provenance = provenance
        self.origin = origin
        self.source = source
        self.createdAt = createdAt
    }
}

/// A model proposal awaiting confirmation. It never feeds analysis until confirmed.
public struct ProposedFact: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var text: String
    public var suggestedProvenance: FactProvenance
    public let generatedAt: Date

    public init(id: UUID = UUID(), text: String, suggestedProvenance: FactProvenance, generatedAt: Date = Date()) {
        self.id = id
        self.text = text
        self.suggestedProvenance = suggestedProvenance
        self.generatedAt = generatedAt
    }
}

public struct NarrativeCorrection: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let text: String
    public let createdAt: Date

    public init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

/// Element status is always set by the user. The default is `.unknown`.
public enum ElementStatus: String, Codable, CaseIterable, Sendable {
    case unknown
    case supported
    case disputed
    case notEstablished = "not-established"

    public var title: String {
        switch self {
        case .unknown: return "Unknown"
        case .supported: return "Supported by supplied information"
        case .disputed: return "Disputed"
        case .notEstablished: return "Not established"
        }
    }
}

public struct ElementAssessment: Codable, Hashable, Sendable {
    public var status: ElementStatus
    public var supportingFactIDs: [UUID]
    public var contradictingFactIDs: [UUID]
    public var note: String?

    public init(status: ElementStatus = .unknown, supportingFactIDs: [UUID] = [], contradictingFactIDs: [UUID] = [], note: String? = nil) {
        self.status = status
        self.supportingFactIDs = supportingFactIDs
        self.contradictingFactIDs = contradictingFactIDs
        self.note = note
    }
}

// MARK: Evidence

public struct ContinuityEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var at: Date
    public var custodian: String
    public var location: String
    public var action: String

    public init(id: UUID = UUID(), at: Date, custodian: String, location: String, action: String) {
        self.id = id
        self.at = at
        self.custodian = custodian
        self.location = location
        self.action = action
    }
}

public struct EvidenceItem: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var description: String
    public var provenance: FactProvenance
    public var isOriginal: Bool
    public var workingCopyOf: UUID?
    public var collectionAuthorityEntryID: String?   // authority card relied on, if any
    public var collectionAuthorityUnresolved: Bool
    public var preservationNotes: String
    public var disclosureNotes: String
    public var contradicts: [UUID]                   // fact ids
    public var continuity: [ContinuityEntry]

    public init(id: UUID = UUID(), description: String, provenance: FactProvenance, isOriginal: Bool = true,
                workingCopyOf: UUID? = nil, collectionAuthorityEntryID: String? = nil,
                collectionAuthorityUnresolved: Bool = true, preservationNotes: String = "", disclosureNotes: String = "",
                contradicts: [UUID] = [], continuity: [ContinuityEntry] = []) {
        self.id = id
        self.description = description
        self.provenance = provenance
        self.isOriginal = isOriginal
        self.workingCopyOf = workingCopyOf
        self.collectionAuthorityEntryID = collectionAuthorityEntryID
        self.collectionAuthorityUnresolved = collectionAuthorityUnresolved
        self.preservationNotes = preservationNotes
        self.disclosureNotes = disclosureNotes
        self.contradicts = contradicts
        self.continuity = continuity
    }
}

// MARK: Checklists

/// A checklist item's status can only change through an explicit user action.
public enum ChecklistItemStatus: Codable, Hashable, Sendable {
    case notStarted
    case recordedComplete(by: String, at: Date, note: String)
    case notApplicable(reason: String, by: String, at: Date)

    public var label: String {
        switch self {
        case .notStarted: return "Not recorded"
        case .recordedComplete: return "Recorded complete"
        case .notApplicable: return "Not applicable"
        }
    }
}

// MARK: Cautions and timeline

/// What was communicated. Deliberately has NO field for "understood", "waived" or "compliant":
/// recording that wording was read never establishes those things.
public struct CautionRecord: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var cautionEntryID: String
    public var wordingVersion: String?       // nil when approved wording is not installed
    public var whatWasCommunicated: String   // user's own record
    public var at: Date
    public var language: String
    public var interpreter: String?
    public var personResponse: String
    public var subsequentSteps: String

    public init(id: UUID = UUID(), cautionEntryID: String, wordingVersion: String?, whatWasCommunicated: String, at: Date,
                language: String, interpreter: String?, personResponse: String, subsequentSteps: String) {
        self.id = id
        self.cautionEntryID = cautionEntryID
        self.wordingVersion = wordingVersion
        self.whatWasCommunicated = whatWasCommunicated
        self.at = at
        self.language = language
        self.interpreter = interpreter
        self.personResponse = personResponse
        self.subsequentSteps = subsequentSteps
    }
}

public struct TimelineEvent: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case stageChange = "stage-change"
        case rightsCommunicated = "rights-communicated"
        case cautionRecorded = "caution-recorded"
        case evidenceAction = "evidence-action"
        case note
    }

    public let id: UUID
    public var at: Date
    public var kind: Kind
    public var stage: EncounterStage?
    public var text: String
    public var cautionRecordID: UUID?

    public init(id: UUID = UUID(), at: Date, kind: Kind, stage: EncounterStage? = nil, text: String, cautionRecordID: UUID? = nil) {
        self.id = id
        self.at = at
        self.kind = kind
        self.stage = stage
        self.text = text
        self.cautionRecordID = cautionRecordID
    }
}

public struct Hypothesis: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var statement: String
    public var supportingFactIDs: [UUID]
    public var contradictingFactIDs: [UUID]
    public var openQuestions: [String]

    public init(id: UUID = UUID(), statement: String, supportingFactIDs: [UUID] = [], contradictingFactIDs: [UUID] = [], openQuestions: [String] = []) {
        self.id = id
        self.statement = statement
        self.supportingFactIDs = supportingFactIDs
        self.contradictingFactIDs = contradictingFactIDs
        self.openQuestions = openQuestions
    }
}

/// Text produced by the on-device model. Stored separately from user facts and from
/// deterministic results, and always labelled as generated.
public struct GeneratedExplanation: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let text: String
    public let citedProvisionIDs: [String]
    public let modelDescription: String
    public let generatedAt: Date
}

/// Package and rule versions that informed an analysis. Later updates never rewrite this.
public struct ContentProvenance: Codable, Hashable, Sendable {
    public var packageVersion: String
    public var packagePublishedAt: String
    public var sourceVersions: [String: String]   // source_id -> consolidation / sha256 summary
    public var guideVersions: [String: String]    // entry_id -> version@review_status
    public var recordedAt: Date

    public init(packageVersion: String, packagePublishedAt: String, sourceVersions: [String: String] = [:],
                guideVersions: [String: String] = [:], recordedAt: Date = Date()) {
        self.packageVersion = packageVersion
        self.packagePublishedAt = packagePublishedAt
        self.sourceVersions = sourceVersions
        self.guideVersions = guideVersions
        self.recordedAt = recordedAt
    }
}

public struct AuditEntry: Codable, Hashable, Sendable {
    public let at: Date
    public let action: String
}

// MARK: Scenario

public struct Scenario: Identifiable, Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int = Scenario.currentSchemaVersion
    public let id: UUID
    public var title: String
    public let createdAt: Date
    public var updatedAt: Date
    public var isTraining: Bool
    public var incidentDate: Date?
    public var city: CitySelection
    public var stage: EncounterStage?
    public var personIsYoungPerson: Bool?   // nil = unknown
    /// The narrative as first entered. Never edited; corrections are appended.
    public let originalNarrative: String
    public var corrections: [NarrativeCorrection]
    public var facts: [Fact]
    public var pendingProposals: [ProposedFact]
    public var selectedOffenceIDs: [String]
    public var elementAssessments: [String: ElementAssessment]   // "<offenceID>#<elementID>"
    public var evidence: [EvidenceItem]
    public var checklistStatus: [String: ChecklistItemStatus]    // "<checklistID>#<itemID>"
    public var cautionRecords: [CautionRecord]
    public var timeline: [TimelineEvent]
    public var hypotheses: [Hypothesis]
    public var unresolvedQuestions: [String]
    public var generatedExplanations: [GeneratedExplanation]
    public var provenance: ContentProvenance?
    public var audit: [AuditEntry]

    public init(id: UUID = UUID(), title: String, narrative: String, isTraining: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.isTraining = isTraining
        self.incidentDate = nil
        self.city = .notSelected
        self.stage = nil
        self.personIsYoungPerson = nil
        self.originalNarrative = narrative
        self.corrections = []
        self.facts = []
        self.pendingProposals = []
        self.selectedOffenceIDs = []
        self.elementAssessments = [:]
        self.evidence = []
        self.checklistStatus = [:]
        self.cautionRecords = []
        self.timeline = []
        self.hypotheses = []
        self.unresolvedQuestions = []
        self.generatedExplanations = []
        self.provenance = nil
        self.audit = [AuditEntry(at: createdAt, action: "created")]
    }

    public static func elementKey(offenceID: String, elementID: String) -> String { "\(offenceID)#\(elementID)" }
    public static func checklistKey(checklistID: String, itemID: String) -> String { "\(checklistID)#\(itemID)" }

    /// Facts that feed analysis: user-entered or model proposals the user confirmed; superseded facts excluded.
    public var activeFacts: [Fact] { facts.filter { $0.supersededBy == nil } }

    public func elementStatus(offenceID: String, elementID: String) -> ElementStatus {
        elementAssessments[Scenario.elementKey(offenceID: offenceID, elementID: elementID)]?.status ?? .unknown
    }

    public func checklistItemStatus(checklistID: String, itemID: String) -> ChecklistItemStatus {
        checklistStatus[Scenario.checklistKey(checklistID: checklistID, itemID: itemID)] ?? .notStarted
    }

    // MARK: Explicit user actions (the only ways state changes)

    public mutating func addCorrection(_ text: String, at: Date = Date()) {
        corrections.append(NarrativeCorrection(text: text, createdAt: at))
        touch("narrative correction added", at: at)
    }

    public mutating func confirmProposal(_ id: UUID, provenance: FactProvenance, editedText: String? = nil, at: Date = Date()) {
        guard let idx = pendingProposals.firstIndex(where: { $0.id == id }) else { return }
        let p = pendingProposals.remove(at: idx)
        facts.append(Fact(text: editedText ?? p.text, provenance: provenance, origin: .modelProposedConfirmed, createdAt: at))
        touch("model proposal confirmed by user", at: at)
    }

    public mutating func rejectProposal(_ id: UUID, at: Date = Date()) {
        pendingProposals.removeAll { $0.id == id }
        touch("model proposal rejected by user", at: at)
    }

    public mutating func correctFact(_ id: UUID, newText: String, provenance: FactProvenance, at: Date = Date()) {
        guard let idx = facts.firstIndex(where: { $0.id == id }) else { return }
        let replacement = Fact(text: newText, provenance: provenance, origin: .userEntered, createdAt: at)
        facts[idx].supersededBy = replacement.id
        facts.append(replacement)
        touch("fact corrected (original retained)", at: at)
    }

    public mutating func setElement(offenceID: String, elementID: String, assessment: ElementAssessment, at: Date = Date()) {
        elementAssessments[Scenario.elementKey(offenceID: offenceID, elementID: elementID)] = assessment
        touch("element assessment set by user", at: at)
    }

    public enum ChecklistError: Error, Equatable {
        case reasonRequired
        case recorderRequired
    }

    public mutating func recordChecklistComplete(checklistID: String, itemID: String, by: String, note: String, at: Date = Date()) throws {
        guard !by.trimmingCharacters(in: .whitespaces).isEmpty else { throw ChecklistError.recorderRequired }
        checklistStatus[Scenario.checklistKey(checklistID: checklistID, itemID: itemID)] = .recordedComplete(by: by, at: at, note: note)
        touch("checklist item recorded complete by user", at: at)
    }

    public mutating func markChecklistNotApplicable(checklistID: String, itemID: String, reason: String, by: String, at: Date = Date()) throws {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ChecklistError.reasonRequired }
        guard !by.trimmingCharacters(in: .whitespaces).isEmpty else { throw ChecklistError.recorderRequired }
        checklistStatus[Scenario.checklistKey(checklistID: checklistID, itemID: itemID)] = .notApplicable(reason: reason, by: by, at: at)
        touch("checklist item marked not applicable by user", at: at)
    }

    public mutating func resetChecklistItem(checklistID: String, itemID: String, at: Date = Date()) {
        checklistStatus[Scenario.checklistKey(checklistID: checklistID, itemID: itemID)] = .notStarted
        touch("checklist item reset by user", at: at)
    }

    /// Records what was communicated. Does not change any checklist item, right or compliance state.
    public mutating func recordCaution(_ record: CautionRecord) {
        cautionRecords.append(record)
        timeline.append(TimelineEvent(at: record.at, kind: .cautionRecorded, stage: stage,
                                      text: "Communication recorded (\(record.cautionEntryID))", cautionRecordID: record.id))
        touch("caution communication recorded", at: record.at)
    }

    public mutating func changeStage(to newStage: EncounterStage, at: Date = Date()) {
        stage = newStage
        timeline.append(TimelineEvent(at: at, kind: .stageChange, stage: newStage, text: "Stage changed to \(newStage.title). Reassess rights."))
        touch("stage changed", at: at)
    }

    mutating func touch(_ action: String, at: Date) {
        updatedAt = at
        audit.append(AuditEntry(at: at, action: action))
    }
}
