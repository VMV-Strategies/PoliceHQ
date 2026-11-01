import SwiftUI
import PoliceHQCore

/// The situation workspace: clarification first, then possible offences, authorities,
/// rights, next steps, evidence and investigator tools. Limitations stay visible.
struct ScenarioWorkspaceView: View {
    let scenarioID: UUID
    @Environment(AppModel.self) private var model
    @State private var scenario: Scenario?
    @State private var analysis: ScenarioAnalysis?
    @State private var showAddFact = false
    @State private var showCorrection = false
    @State private var showCaution = false
    @State private var showEvidence = false
    @State private var showExport = false
    @State private var proposing = false
    @State private var newQuestion = ""
    @State private var newHypothesis = ""

    var body: some View {
        Group {
            if let s = scenario, let store = model.store {
                content(s, store: store)
            } else if model.store == nil {
                NoContentView()
            } else {
                ProgressView()
            }
        }
        .navigationTitle(scenario?.title ?? "Situation")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Export…", systemImage: "square.and.arrow.up") { showExport = true }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        if let s = scenario { model.delete(s); scenario = nil }
                    }
                } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("More") }
            }
        }
        .sheet(isPresented: $showAddFact) { AddFactSheet { fact in mutate { $0.facts.append(fact) } } }
        .sheet(isPresented: $showCorrection) { TextEntrySheet(title: "Add correction", prompt: "Correction") { t in mutate { $0.addCorrection(t) } } }
        .sheet(isPresented: $showCaution) { CautionRecordSheet { rec in mutate { $0.recordCaution(rec) } } }
        .sheet(isPresented: $showEvidence) { EvidenceEditorSheet { item in mutate { $0.evidence.append(item) } } }
        .sheet(isPresented: $showExport) { if let s = scenario { ExportScenarioSheet(scenario: s) } }
    }

    // MARK: Layout

    @ViewBuilder
    private func content(_ s: Scenario, store: ContentStore) -> some View {
        List {
            if s.isTraining {
                Section { Label("Training mode — fictional scenario", systemImage: "graduationcap").foregroundStyle(.purple) }
            }
            detailsSection(s)
            if let a = analysis {
                clarificationSection(a)
                limitationsSection(a)
            }
            narrativeSection(s)
            factsSection(s)
            if let a = analysis {
                offencesSection(a, s)
                authoritiesSection(a)
            }
            rightsSection(s, store: store)
            checklistsSection(s, store: store)
            evidenceSection(s)
            investigatorSection(s)
            provenanceSection(s)
        }
        .listStyle(.insetGrouped)
        .privacySensitive()
    }

    private func detailsSection(_ s: Scenario) -> some View {
        Section("Details") {
            DatePicker("Incident date", selection: Binding(get: { s.incidentDate ?? Date() }, set: { d in mutate { $0.incidentDate = d } }),
                       displayedComponents: [.date, .hourAndMinute])
            if s.incidentDate == nil {
                HStack { StatusBadge(label: .informationMissing); Spacer(); Button("Set to now") { mutate { $0.incidentDate = Date() } } }
            }
            Picker("City", selection: Binding(get: { s.city }, set: { c in mutate { $0.city = c } })) {
                Text("Not selected").tag(CitySelection.notSelected)
                Text("Brampton").tag(CitySelection.brampton)
                Text("Mississauga").tag(CitySelection.mississauga)
            }
            Picker("Encounter stage", selection: Binding(get: { s.stage }, set: { st in if let st { mutate { $0.changeStage(to: st) } } })) {
                Text("Not set").tag(EncounterStage?.none)
                ForEach(EncounterStage.allCases, id: \.self) { Text($0.title).tag(EncounterStage?.some($0)) }
            }
            Picker("Young person (under 18)?", selection: Binding(get: { s.personIsYoungPerson }, set: { v in mutate { $0.personIsYoungPerson = v } })) {
                Text("Unknown").tag(Bool?.none)
                Text("Yes").tag(Bool?.some(true))
                Text("No").tag(Bool?.some(false))
            }
        }
    }

    private func clarificationSection(_ a: ScenarioAnalysis) -> some View {
        Section {
            if a.clarifications.isEmpty {
                Text("No open clarification questions from the installed guides.").foregroundStyle(.secondary)
            }
            ForEach(a.clarifications) { q in
                VStack(alignment: .leading, spacing: 4) {
                    Text(q.question).font(.body.weight(.medium))
                    Text(q.why).font(.footnote).foregroundStyle(.secondary)
                }
            }
        } header: {
            SectionHeader(title: "What needs clarification", systemImage: "questionmark.bubble")
        }
    }

    private func limitationsSection(_ a: ScenarioAnalysis) -> some View {
        Section {
            LimitationBanner(title: "Limits of this analysis",
                             lines: [a.basisStatement] + uniqueFindings(a).map(\.text))
        }
    }

    private func uniqueFindings(_ a: ScenarioAnalysis) -> [Finding] {
        var seen = Set<String>()
        var out: [Finding] = []
        for f in a.findings + a.candidates.flatMap(\.findings) {
            if case .elementUnsupported = f { continue }
            if seen.insert(f.text).inserted { out.append(f) }
        }
        return out
    }

    private func narrativeSection(_ s: Scenario) -> some View {
        Section("Narrative") {
            Text(s.originalNarrative).textSelection(.enabled)
            ForEach(s.corrections) { c in
                VStack(alignment: .leading) {
                    Text("Correction · \(c.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    Text(c.text)
                }
            }
            Button("Add correction", systemImage: "plus") { showCorrection = true }
        }
    }

    private func factsSection(_ s: Scenario) -> some View {
        Section {
            ForEach(s.activeFacts) { f in
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.text)
                    Text(f.provenance.title + (f.origin == .modelProposedConfirmed ? " · proposed by on-device model, confirmed by you" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Button("Add information", systemImage: "plus") { showAddFact = true }
            if model.assistant.availability.isAvailable {
                Button {
                    Task { await propose() }
                } label: {
                    Label(proposing ? "Proposing…" : "Propose facts from narrative (on-device)", systemImage: "sparkles")
                }
                .disabled(proposing)
            } else {
                Text("On-device assistance is unavailable. Structured entry works without it.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(s.pendingProposals) { p in
                VStack(alignment: .leading, spacing: 6) {
                    Label("Proposed — not used until you confirm", systemImage: "sparkles").font(.caption).foregroundStyle(.purple)
                    Text(p.text)
                    HStack {
                        Menu("Confirm as…") {
                            ForEach(FactProvenance.allCases, id: \.self) { prov in
                                Button(prov.title) { mutate { $0.confirmProposal(p.id, provenance: prov) } }
                            }
                        }
                        Spacer()
                        Button("Reject", role: .destructive) { mutate { $0.rejectProposal(p.id) } }
                    }
                }
            }
        } header: {
            SectionHeader(title: "Information supplied", systemImage: "list.bullet.clipboard")
        }
    }

    private func offencesSection(_ a: ScenarioAnalysis, _ s: Scenario) -> some View {
        Section {
            if a.candidates.isEmpty {
                Text("No installed offence guide matched. Use Search or Statutes; the guides cover a limited set of offences.").foregroundStyle(.secondary)
            }
            ForEach(a.candidates) { c in
                NavigationLink {
                    OffenceAnalysisView(scenarioID: s.id, offenceID: c.id)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(c.entry.title).font(.headline); Spacer(); ReviewBadge(status: c.entry.reviewStatus) }
                        if !c.matchedTerms.isEmpty {
                            Text("Shown because your text mentions: \(c.matchedTerms.joined(separator: ", ")). Keyword match, not legal reasoning.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        let counts = Dictionary(grouping: c.rows, by: \.status).mapValues(\.count)
                        Text(ElementStatus.allCases.compactMap { st in counts[st].map { "\($0) \(st.title.lowercased())" } }.joined(separator: " · "))
                            .font(.footnote)
                    }
                }
            }
            Menu("Add an offence guide") {
                ForEach((try? model.store?.guideEntries(kind: .offence)) ?? [], id: \.id) { e in
                    Button(e.title) { mutate { if !$0.selectedOffenceIDs.contains(e.id) { $0.selectedOffenceIDs.append(e.id) } } }
                }
            }
        } header: {
            SectionHeader(title: "Possible offences", systemImage: "list.bullet.rectangle.portrait")
        } footer: {
            Text("Element statuses are set by you. Missing information stays unknown; allegations stay allegations. This tool does not determine guilt or recommend charges.")
        }
    }

    private func authoritiesSection(_ a: ScenarioAnalysis) -> some View {
        Section {
            ForEach(AuthorityCategory.allCases, id: \.self) { cat in
                let refs = a.authorityReferences[cat] ?? []
                if !refs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(cat.title, systemImage: cat.symbolName).font(.subheadline.weight(.semibold))
                        ForEach(refs) { r in
                            NavigationLink(value: Route.guide(r.entry.id)) { Text(r.entry.title).font(.footnote) }
                        }
                    }
                }
            }
        } header: {
            SectionHeader(title: "Authorities to review", systemImage: "shield.lefthalf.filled")
        } footer: {
            Text("Reference descriptions of powers, filtered by encounter stage. An offence never creates an arrest, entry, search or seizure power by itself. Whether conditions are met is for you to assess.")
        }
    }

    private func rightsSection(_ s: Scenario, store: ContentStore) -> some View {
        Section {
            if let stage = s.stage {
                let rights = ((try? store.guideEntries(kind: .right)) ?? []).filter {
                    ($0.body.stages ?? []).contains(stage.rawValue) && ($0.body.youth != true || s.personIsYoungPerson != false)
                }
                ForEach(rights, id: \.id) { r in
                    NavigationLink(value: Route.guide(r.id)) {
                        HStack {
                            Text(r.title).font(.footnote)
                            if r.body.youth == true { Text("Youth").font(.caption2.weight(.bold)).padding(4).background(.purple.opacity(0.15), in: Capsule()) }
                        }
                    }
                }
            } else {
                HStack { StatusBadge(label: .informationMissing); Text("Set the encounter stage to see stage-specific rights.").font(.footnote) }
            }
            ForEach(s.timeline.sorted { $0.at < $1.at }) { e in
                VStack(alignment: .leading) {
                    Text(e.at.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    Text(e.text).font(.footnote)
                }
            }
            Button("Record communication (caution or rights)", systemImage: "quote.bubble") { showCaution = true }
            Text("Recording what was said does not establish understanding, a valid waiver or compliance.").font(.caption).foregroundStyle(.secondary)
        } header: {
            SectionHeader(title: "Rights timeline", systemImage: "person.badge.shield.checkmark")
        }
    }

    private func checklistsSection(_ s: Scenario, store: ContentStore) -> some View {
        Section {
            let ids = ChecklistSelector.ids(for: s)
            if ids.isEmpty {
                Text("Set the encounter stage to see conditional checklists.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(ids, id: \.self) { id in
                if let entry = try? store.guideEntry(id: id) {
                    ChecklistBlock(entry: entry, scenario: s) { change in mutate(change) }
                }
            }
        } header: {
            SectionHeader(title: "Next steps", systemImage: "checklist")
        } footer: {
            Text("Items never complete themselves. Deadlines are not calculated unless a reviewed rule is installed.")
        }
    }

    private func evidenceSection(_ s: Scenario) -> some View {
        Section {
            ForEach(s.evidence) { e in
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.description).font(.body)
                    Text("\(e.provenance.title) · \(e.isOriginal ? "Original" : "Working copy") · continuity entries: \(e.continuity.count)")
                        .font(.caption).foregroundStyle(.secondary)
                    if e.collectionAuthorityUnresolved {
                        StatusBadge(label: .reviewRequired)
                        Text("Collection authority unresolved.").font(.caption)
                    }
                }
            }
            Button("Add evidence item", systemImage: "plus") { showEvidence = true }
        } header: {
            SectionHeader(title: "Evidence", systemImage: "archivebox")
        }
    }

    private func investigatorSection(_ s: Scenario) -> some View {
        Section {
            ForEach(s.hypotheses) { h in Text("• \(h.statement)") }
            HStack {
                TextField("Add a competing hypothesis", text: $newHypothesis)
                Button("Add") { let t = newHypothesis; mutate { $0.hypotheses.append(Hypothesis(statement: t)) }; newHypothesis = "" }
                    .disabled(newHypothesis.isEmpty)
            }
            ForEach(s.unresolvedQuestions, id: \.self) { q in Text("? \(q)") }
            HStack {
                TextField("Add an unresolved legal question", text: $newQuestion)
                Button("Add") { let t = newQuestion; mutate { $0.unresolvedQuestions.append(t) }; newQuestion = "" }
                    .disabled(newQuestion.isEmpty)
            }
        } header: {
            SectionHeader(title: "Investigator tools", systemImage: "point.3.connected.trianglepath.dotted")
        }
    }

    private func provenanceSection(_ s: Scenario) -> some View {
        Section("Versions used") {
            if let p = s.provenance {
                Text("Analyzed with content package \(p.packageVersion) (published \(p.packagePublishedAt)).").font(.footnote)
                if let current = model.manifest?.packageVersion, current != p.packageVersion {
                    LimitationBanner(title: "A different content package is now installed",
                                     lines: ["This situation keeps the versions recorded above. Reassessment against package \(current) only happens if you choose it."])
                    Button("Reassess against installed package") { reassess() }
                }
            } else {
                Text("Versions are recorded the first time this situation is analyzed.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Actions

    private func load() {
        scenario = model.scenarios.first { $0.id == scenarioID }
        runAnalysis()
    }

    private func mutate(_ change: (inout Scenario) -> Void) {
        guard var s = scenario else { return }
        change(&s)
        s.updatedAt = Date()
        scenario = s
        model.save(s)
        runAnalysis()
    }

    private func runAnalysis() {
        guard var s = scenario, let store = model.store else { return }
        analysis = try? ScenarioAnalyzer(store: store).analyze(s)
        if s.provenance == nil, let a = analysis {
            model.recordProvenance(a, into: &s)
            scenario = s
            model.save(s)
        }
    }

    private func reassess() {
        guard let a = analysis else { return }
        mutate {
            $0.provenance = a.provenance
            $0.audit.append(AuditEntry(at: Date(), action: "reassessed against package \(a.provenance.packageVersion) by user"))
        }
    }

    private func propose() async {
        guard let s = scenario else { return }
        proposing = true
        defer { proposing = false }
        do {
            let proposals = try await model.assistant.proposeFacts(from: s.originalNarrative)
            mutate { $0.pendingProposals.append(contentsOf: proposals) }
        } catch {
            model.lastError = "The on-device model could not propose facts. You can enter them yourself."
        }
    }
}

/// Which checklists apply, by stage and known circumstances.
enum ChecklistSelector {
    static func ids(for s: Scenario) -> [String] {
        guard let stage = s.stage else { return [] }
        var out: [String] = []
        switch stage {
        case .initialInteraction: out = ["checklist-identifying-information"]
        case .detention: out = ["checklist-detention", "checklist-mha-apprehension"]
        case .arrest: out = ["checklist-after-arrest"]
        case .questioning: out = s.personIsYoungPerson == false ? [] : ["checklist-youth-statement"]
        case .searchSeizure: out = ["checklist-seizure-report"]
        case .custodyRelease: out = ["checklist-after-arrest"]
        }
        return out
    }
}
