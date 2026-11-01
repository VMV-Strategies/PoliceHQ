import Foundation

/// Findings vocabulary. Absence of an authority is never presented as proof that none exists.
public enum Finding: Hashable, Sendable {
    case insufficientInformation(String)
    case elementUnsupported(offenceID: String, elementID: String)
    case conflictingInformation(String)
    case relevantSourceNotInstalled(gapID: String, title: String)
    case noApplicableAuthorityIdentified(category: AuthorityCategory)
    case legalReviewRequired(entryID: String)
    case versionWarning(sourceID: String, note: String)

    public var text: String {
        switch self {
        case .insufficientInformation(let s): return "Insufficient information: \(s)"
        case .elementUnsupported(_, let e): return "This element is unsupported by the information supplied (\(e))."
        case .conflictingInformation(let s): return "Conflicting information requires clarification: \(s)"
        case .relevantSourceNotInstalled(_, let t): return "Relevant source not installed: \(t)"
        case .noApplicableAuthorityIdentified(let c): return "No applicable \(c.title.lowercased()) authority identified in the installed material. This does not mean none exists."
        case .legalReviewRequired: return "Legal review or consultation required: this guide is an unreviewed draft."
        case .versionWarning(_, let n): return n
        }
    }
}

public struct ClarificationQuestion: Identifiable, Hashable, Sendable {
    public let id: String
    public let question: String
    public let why: String
}

public struct ElementRow: Identifiable, Hashable, Sendable {
    public var id: String { element.id }
    public let element: OffenceElementDef
    public let citation: GuideCitation?
    public let status: ElementStatus
    public let supportingFacts: [Fact]
    public let contradictingFacts: [Fact]
}

public struct OffenceCandidate: Identifiable, Hashable, Sendable {
    public var id: String { entry.id }
    public let entry: GuideEntry
    /// Why this guide is shown. Keyword matching is not legal reasoning.
    public let matchedTerms: [String]
    public let rows: [ElementRow]
    public let defences: [DefenceDef]
    public let exculpatoryPrompts: [String]
    public let remainingQuestions: [String]
    public let findings: [Finding]
}

public struct AuthorityReference: Identifiable, Hashable, Sendable {
    public var id: String { entry.id }
    public let entry: GuideEntry
    /// Descriptive reference only; the card's conditions must be assessed by the user.
    public let note: String
}

public struct ScenarioAnalysis: Sendable {
    public let clarifications: [ClarificationQuestion]
    public let candidates: [OffenceCandidate]
    public let authorityReferences: [AuthorityCategory: [AuthorityReference]]
    public let findings: [Finding]
    public let provenance: ContentProvenance
    public let basisStatement: String
}

/// Deterministic, explainable analysis. It never infers guilt, never upgrades a fact's
/// provenance, never sets element statuses, and never derives a power from an offence.
public struct ScenarioAnalyzer {
    public let store: ContentStore

    public init(store: ContentStore) {
        self.store = store
    }

    public func analyze(_ scenario: Scenario) throws -> ScenarioAnalysis {
        let offences = try store.guideEntries(kind: .offence)
        let authorities = try store.guideEntries(kind: .authority)
        let gaps = Dictionary(uniqueKeysWithValues: try store.coverageGaps().map { ($0.id, $0) })
        let info = try store.packageInfo()

        var clarifications = baseClarifications(scenario)
        var findings: [Finding] = []

        // Candidate offences: user-selected, plus guides whose curated keywords appear in confirmed facts or narrative.
        let haystack = ([scenario.originalNarrative] + scenario.corrections.map(\.text) + scenario.activeFacts.map(\.text))
            .joined(separator: " \n ").lowercased()
        var candidates: [OffenceCandidate] = []
        for entry in offences {
            let terms = (entry.body.keywords ?? []).filter { haystack.contains($0.lowercased()) }
            guard scenario.selectedOffenceIDs.contains(entry.id) || !terms.isEmpty else { continue }
            candidates.append(candidate(entry, scenario: scenario, matched: terms, gaps: gaps))
        }

        // Authorities: reference cards organized by category; filtered by encounter stage, never by offence alone.
        var refs: [AuthorityCategory: [AuthorityReference]] = [:]
        for cat in AuthorityCategory.allCases {
            let inCat = authorities.filter { $0.authorityCategory == cat }
            let relevant = inCat.filter { stageRelevant(cat, stage: scenario.stage) }
            refs[cat] = relevant.map {
                AuthorityReference(entry: $0, note: "Reference description of a power. Whether its conditions are met on your facts is for you to assess; nothing here establishes that they are.")
            }
            if relevant.isEmpty && stageRelevant(cat, stage: scenario.stage) {
                findings.append(.noApplicableAuthorityIdentified(category: cat))
            }
        }

        // Version checks for every source cited by candidate guides.
        var checked = Set<String>()
        for c in candidates {
            for cit in c.entry.citations where !checked.contains(cit.sourceID) {
                checked.insert(cit.sourceID)
                if let src = try store.source(id: cit.sourceID) {
                    let v = VersionSelector.assess(source: src, incidentDate: scenario.incidentDate)
                    if !v.isUsableWithoutWarning {
                        findings.append(.versionWarning(sourceID: src.id, note: "\(src.title): \(v.note)"))
                    }
                }
            }
        }
        if candidates.isEmpty {
            findings.append(.insufficientInformation("No offence guide matched the information supplied. Use Search or the Statutes browser; the installed guides cover a limited set of offences."))
        }
        if let gap = gaps["gap-case-law"] { findings.append(.relevantSourceNotInstalled(gapID: gap.id, title: gap.title)) }

        for c in candidates {
            for q in c.remainingQuestions.prefix(2) {
                clarifications.append(ClarificationQuestion(id: "\(c.id)#\(q.hashValue)", question: q, why: "Could change whether the elements of \(c.entry.title) are supported."))
            }
        }

        let provenance = try makeProvenance(info: info, entries: candidates.map(\.entry) + authorities)
        return ScenarioAnalysis(
            clarifications: clarifications,
            candidates: candidates,
            authorityReferences: refs,
            findings: findings,
            provenance: provenance,
            basisStatement: "Here are potentially relevant provisions, their requirements, the information you supplied, what remains unresolved and the sources to review. Matching is based on curated keywords and your selections, not legal reasoning."
        )
    }

    func baseClarifications(_ s: Scenario) -> [ClarificationQuestion] {
        var q: [ClarificationQuestion] = []
        if s.incidentDate == nil {
            q.append(ClarificationQuestion(id: "incident-date", question: "What is the incident date?", why: "Determines which version of each law and penalty applies."))
        }
        if s.city == .notSelected {
            q.append(ClarificationQuestion(id: "city", question: "Did this occur in Brampton or Mississauga (or elsewhere)?", why: "Municipal by-laws differ by city; one city's by-laws are never applied to the other."))
        }
        if s.stage == nil {
            q.append(ClarificationQuestion(id: "stage", question: "What is the current encounter stage (initial interaction, detention, arrest, questioning, search or seizure, custody and release)?", why: "Rights and obligations change with the stage."))
        }
        if s.personIsYoungPerson == nil {
            q.append(ClarificationQuestion(id: "youth", question: "Is the person's age known?", why: "Youth Criminal Justice Act safeguards apply to young persons."))
        }
        let unknownProvenance = s.activeFacts.filter { $0.provenance == .unknown }
        if !unknownProvenance.isEmpty {
            q.append(ClarificationQuestion(id: "provenance", question: "Where did \(unknownProvenance.count) piece(s) of information come from?", why: "Observation, witness account, document, allegation and inference carry different weight."))
        }
        return q
    }

    func candidate(_ entry: GuideEntry, scenario: Scenario, matched: [String], gaps: [String: CoverageGap]) -> OffenceCandidate {
        var rows: [ElementRow] = []
        var findings: [Finding] = []
        let factsByID = Dictionary(uniqueKeysWithValues: scenario.facts.map { ($0.id, $0) })
        for el in entry.body.elements ?? [] {
            let a = scenario.elementAssessments[Scenario.elementKey(offenceID: entry.id, elementID: el.id)] ?? ElementAssessment()
            let sup = a.supportingFactIDs.compactMap { factsByID[$0] }.filter { $0.supersededBy == nil }
            let con = a.contradictingFactIDs.compactMap { factsByID[$0] }.filter { $0.supersededBy == nil }
            let cit = el.citation.flatMap { idx in entry.citations.indices.contains(idx) ? entry.citations[idx] : nil }
            rows.append(ElementRow(element: el, citation: cit, status: a.status, supportingFacts: sup, contradictingFacts: con))
            if a.status == .unknown || a.status == .notEstablished {
                findings.append(.elementUnsupported(offenceID: entry.id, elementID: el.id))
            }
            if !sup.isEmpty && !con.isEmpty {
                findings.append(.conflictingInformation("\(el.text): information both supports and contradicts this element."))
            }
            if a.status == .supported && sup.allSatisfy({ $0.provenance == .allegation || $0.provenance == .userInference }) && !sup.isEmpty {
                findings.append(.conflictingInformation("\(el.text): marked supported, but only by allegation or inference."))
            }
        }
        for g in entry.body.gaps ?? [] {
            if let gap = gaps[g] { findings.append(.relevantSourceNotInstalled(gapID: gap.id, title: gap.title)) }
        }
        if !entry.reviewStatus.isOperationallyApproved {
            findings.append(.legalReviewRequired(entryID: entry.id))
        }
        return OffenceCandidate(entry: entry, matchedTerms: matched, rows: rows, defences: entry.body.defences ?? [],
                                exculpatoryPrompts: entry.body.exculpatoryPrompts ?? [],
                                remainingQuestions: entry.body.lawfulQuestions ?? [], findings: findings)
    }

    func stageRelevant(_ cat: AuthorityCategory, stage: EncounterStage?) -> Bool {
        guard let stage = stage else { return true }
        switch stage {
        case .initialInteraction: return [.detention, .arrest, .search, .entry].contains(cat)
        case .detention: return [.detention, .arrest, .search, .seizure, .release].contains(cat)
        case .arrest: return [.arrest, .entry, .search, .seizure, .release].contains(cat)
        case .questioning: return [.detention, .arrest, .release].contains(cat)
        case .searchSeizure: return [.search, .seizure, .entry].contains(cat)
        case .custodyRelease: return [.release].contains(cat)
        }
    }

    func makeProvenance(info: PackageInfo, entries: [GuideEntry]) throws -> ContentProvenance {
        var sources: [String: String] = [:]
        var guides: [String: String] = [:]
        for e in entries {
            guides[e.id] = "\(e.version)@\(e.reviewStatus.rawValue)"
            for c in e.citations where sources[c.sourceID] == nil {
                if let s = try store.source(id: c.sourceID) {
                    sources[s.id] = "\(s.consolidation ?? "Unknown") | sha256:\(s.sha256.prefix(12))"
                }
            }
        }
        return ContentProvenance(packageVersion: info.packageVersion, packagePublishedAt: info.publishedAt,
                                 sourceVersions: sources, guideVersions: guides)
    }
}

/// Deadlines are calculated only from rules that have been validated by a recorded review.
public enum DeadlineResult: Equatable, Sendable {
    case calculated(Date)
    case notCalculated(reason: String)
}

public enum DeadlineCalculator {
    public static func deadline(rule: DeadlineRuleDef?, reviewStatus: ReviewStatus, triggerTime: Date?, hours: Int?) -> DeadlineResult {
        guard let rule = rule else { return .notCalculated(reason: "No deadline rule is installed for this requirement.") }
        guard rule.validated, reviewStatus.isOperationallyApproved else {
            return .notCalculated(reason: "The requirement is shown with its statutory wording (\"\(rule.statutoryText)\"). No reviewed rule with its triggers and exceptions is installed, so no deadline is calculated.")
        }
        guard let t = triggerTime, let h = hours else {
            return .notCalculated(reason: "The trigger time (\(rule.trigger)) has not been recorded.")
        }
        return .calculated(t.addingTimeInterval(TimeInterval(h * 3600)))
    }
}
