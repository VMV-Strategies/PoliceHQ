import SwiftUI
import UniformTypeIdentifiers
import PoliceHQCore

/// Elements-and-evidence matrix for one offence guide within a situation.
struct OffenceAnalysisView: View {
    let scenarioID: UUID
    let offenceID: String
    @Environment(AppModel.self) private var model
    @State private var editingElement: OffenceElementDef?

    private var scenario: Scenario? { model.scenarios.first { $0.id == scenarioID } }

    var body: some View {
        if let s = scenario, let store = model.store, let entry = try? store.guideEntry(id: offenceID) {
            List {
                Section {
                    HStack { JurisdictionBadge(label: entry.body.jurisdictionLabel ?? "—"); Spacer(); ReviewBadge(status: entry.reviewStatus) }
                    if let p = entry.body.procedure { Text(p).font(.footnote) }
                }
                Section {
                    ForEach(entry.body.elements ?? []) { el in
                        Button { editingElement = el } label: { ElementRowView(element: el, entry: entry, scenario: s) }
                            .buttonStyle(.plain)
                    }
                } header: {
                    SectionHeader(title: "Elements and facts in issue", systemImage: "tablecells")
                } footer: {
                    Text("Tap an element to record its status and link information. Statutory wording does not state every requirement; mental-element and interpretive questions depend on case law that is not installed.")
                }
                if let d = entry.body.defences, !d.isEmpty {
                    Section("Exceptions and defences in the installed text") {
                        ForEach(d, id: \.self) { def in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(def.text).font(.subheadline.weight(.medium))
                                QuoteBlock(label: nil, text: def.quote)
                            }
                        }
                    }
                }
                if let ex = entry.body.exculpatoryPrompts, !ex.isEmpty {
                    Section("Potentially exculpatory information to look for") {
                        ForEach(ex, id: \.self) { Text($0).font(.footnote) }
                    }
                }
                if let q = entry.body.lawfulQuestions, !q.isEmpty {
                    Section("Remaining lawful investigative questions") {
                        ForEach(q, id: \.self) { Text($0).font(.footnote) }
                    }
                }
                Section("Penalties and points") {
                    NavigationLink(value: Route.penalties(entry.id)) { Label("Open penalties panel", systemImage: "dollarsign.circle") }
                }
                Section("Sources") {
                    ForEach(entry.citations) { CitationRow(citation: $0, showExcerpt: false) }
                }
            }
            .navigationTitle(entry.title)
            .navigationBarTitleDisplayMode(.inline)
            .privacySensitive()
            .sheet(item: $editingElement) { el in
                ElementAssessmentSheet(scenario: s, offenceID: offenceID, element: el) { updated in model.save(updated) }
            }
        } else {
            ContentUnavailableView("Not available", systemImage: "doc.questionmark")
        }
    }
}

struct ElementRowView: View {
    let element: OffenceElementDef
    let entry: GuideEntry
    let scenario: Scenario

    var body: some View {
        let a = scenario.elementAssessments[Scenario.elementKey(offenceID: entry.id, elementID: element.id)] ?? ElementAssessment()
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(element.text).font(.body.weight(.medium))
                Spacer()
                Text(a.status.title).font(.caption.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(color(a.status).opacity(0.15), in: Capsule())
            }
            if let q = element.quote { QuoteBlock(label: citationLabel, text: q) }
            if element.isGeneralFact { Text(element.basis ?? "").font(.caption).foregroundStyle(.secondary) }
            let sup = scenario.facts.filter { a.supportingFactIDs.contains($0.id) }
            let con = scenario.facts.filter { a.contradictingFactIDs.contains($0.id) }
            ForEach(sup) { f in Label("\(f.text) — \(f.provenance.title)", systemImage: "plus.circle").font(.caption) }
            ForEach(con) { f in Label("\(f.text) — \(f.provenance.title)", systemImage: "minus.circle").font(.caption) }
        }
        .accessibilityElement(children: .combine)
    }

    private var citationLabel: String? {
        guard let i = element.citation, entry.citations.indices.contains(i) else { return nil }
        return entry.citations[i].pinpoint
    }

    private func color(_ s: ElementStatus) -> Color {
        switch s {
        case .supported: return .green
        case .disputed: return .orange
        case .notEstablished: return .red
        case .unknown: return .gray
        }
    }
}

struct ElementAssessmentSheet: View {
    let scenario: Scenario
    let offenceID: String
    let element: OffenceElementDef
    let onSave: (Scenario) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var status: ElementStatus = .unknown
    @State private var supporting: Set<UUID> = []
    @State private var contradicting: Set<UUID> = []
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(element.text) {
                    Picker("Status", selection: $status) {
                        ForEach(ElementStatus.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
                Section("Information that supports it") {
                    ForEach(scenario.activeFacts) { f in
                        Toggle(isOn: Binding(get: { supporting.contains(f.id) }, set: { on in if on { supporting.insert(f.id) } else { supporting.remove(f.id) } })) {
                            VStack(alignment: .leading) { Text(f.text); Text(f.provenance.title).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                Section("Information that contradicts it") {
                    ForEach(scenario.activeFacts) { f in
                        Toggle(isOn: Binding(get: { contradicting.contains(f.id) }, set: { on in if on { contradicting.insert(f.id) } else { contradicting.remove(f.id) } })) {
                            Text(f.text)
                        }
                    }
                }
                Section("Note") { TextField("Optional note", text: $note, axis: .vertical) }
            }
            .navigationTitle("Element")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var s = scenario
                        s.setElement(offenceID: offenceID, elementID: element.id,
                                     assessment: ElementAssessment(status: status, supportingFactIDs: Array(supporting),
                                                                   contradictingFactIDs: Array(contradicting), note: note.isEmpty ? nil : note))
                        onSave(s)
                        dismiss()
                    }
                }
            }
            .onAppear {
                let a = scenario.elementAssessments[Scenario.elementKey(offenceID: offenceID, elementID: element.id)] ?? ElementAssessment()
                status = a.status
                supporting = Set(a.supportingFactIDs)
                contradicting = Set(a.contradictingFactIDs)
                note = a.note ?? ""
            }
        }
    }
}

/// One conditional checklist. Every status change is an explicit user action.
struct ChecklistBlock: View {
    let entry: GuideEntry
    let scenario: Scenario
    let applyChange: ((inout Scenario) -> Void) -> Void
    @State private var pending: (item: ChecklistItemDef, mode: Mode)?
    @State private var who = ""
    @State private var text = ""

    enum Mode { case complete, notApplicable }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(entry.title).font(.subheadline.weight(.semibold)); Spacer(); ReviewBadge(status: entry.reviewStatus) }
            ForEach(applicableItems) { item in
                let status = scenario.checklistItemStatus(checklistID: entry.id, itemID: item.id)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.requirement).font(.footnote.weight(.medium))
                    Text("Trigger: \(item.trigger) · Applies: \(item.applicability)").font(.caption2).foregroundStyle(.secondary)
                    if let i = item.citation, entry.citations.indices.contains(i) {
                        NavigationLink(value: Route.provision(entry.citations[i].provisionID)) {
                            Text("Source: \(entry.citations[i].pinpoint)").font(.caption2)
                        }
                    } else if let basis = item.basis {
                        Text(basis).font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack {
                        switch status {
                        case .notStarted: StatusBadge(label: .informationMissing)
                        case .recordedComplete(let by, let at, let note):
                            StatusBadge(label: .recordedComplete)
                            Text("\(by) · \(at.formatted(date: .omitted, time: .shortened))\(note.isEmpty ? "" : " · \(note)")").font(.caption2)
                        case .notApplicable(let reason, let by, _):
                            Text("Not applicable — \(reason) (\(by))").font(.caption2)
                        }
                        Spacer()
                        Menu("Record") {
                            Button("Recorded complete…") { pending = (item, .complete) }
                            Button("Not applicable…") { pending = (item, .notApplicable) }
                            Button("Reset") { applyChange { $0.resetChecklistItem(checklistID: entry.id, itemID: item.id) } }
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .sheet(isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            NavigationStack {
                Form {
                    TextField("Recorded by (name or number)", text: $who)
                    TextField(pending?.mode == .notApplicable ? "Reason (required)" : "Note (time, details)", text: $text, axis: .vertical)
                }
                .navigationTitle(pending?.mode == .notApplicable ? "Not applicable" : "Recorded complete")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { pending = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            guard let p = pending else { return }
                            let by = who, t = text, cid = entry.id
                            applyChange { s in
                                if p.mode == .complete {
                                    try? s.recordChecklistComplete(checklistID: cid, itemID: p.item.id, by: by, note: t)
                                } else {
                                    try? s.markChecklistNotApplicable(checklistID: cid, itemID: p.item.id, reason: t, by: by)
                                }
                            }
                            pending = nil
                            text = ""
                        }
                        .disabled(who.trimmingCharacters(in: .whitespaces).isEmpty ||
                                  (pending?.mode == .notApplicable && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var applicableItems: [ChecklistItemDef] {
        (entry.body.items ?? []).filter { item in
            if item.condition == "youth" { return scenario.personIsYoungPerson != false }
            return true
        }
    }
}

struct AddFactSheet: View {
    let onAdd: (Fact) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var provenance: FactProvenance = .unknown
    @State private var source = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("What is known", text: $text, axis: .vertical).privacySensitive()
                Picker("Where it comes from", selection: $provenance) {
                    ForEach(FactProvenance.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("Source detail (optional)", text: $source)
            }
            .navigationTitle("Add information")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { onAdd(Fact(text: text, provenance: provenance, source: source.isEmpty ? nil : source)); dismiss() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct TextEntrySheet: View {
    let title: String
    let prompt: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    var body: some View {
        NavigationStack {
            Form { TextField(prompt, text: $text, axis: .vertical).privacySensitive() }
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { onSave(text); dismiss() }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
    }
}

struct CautionRecordSheet: View {
    let onSave: (CautionRecord) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var cautionID = ""
    @State private var communicated = ""
    @State private var at = Date()
    @State private var language = "English"
    @State private var interpreter = ""
    @State private var response = ""
    @State private var steps = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Entry", selection: $cautionID) {
                    ForEach((try? model.store?.guideEntries(kind: .caution)) ?? [], id: \.id) { Text($0.title).tag($0.id) }
                }
                Section("What was communicated") { TextField("Your record of what was said or read", text: $communicated, axis: .vertical) }
                DatePicker("When", selection: $at)
                TextField("Language", text: $language)
                TextField("Interpreter (name/service), if any", text: $interpreter)
                Section("Person's response (as said)") { TextField("Response", text: $response, axis: .vertical) }
                Section("Subsequent steps") { TextField("Steps taken", text: $steps, axis: .vertical) }
                Section {
                    Text("This record does not establish that the person understood, waived any right, or that legal requirements were met.")
                        .font(.footnote)
                }
            }
            .privacySensitive()
            .navigationTitle("Record communication")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let entry = try? model.store?.guideEntry(id: cautionID)
                        let version: String? = entry.flatMap { e in
                            if case .approvedWording(_, _, let v) = CautionPresentation.make(for: e, level: .legalAnalysis) { return v }
                            return nil
                        }
                        onSave(CautionRecord(cautionEntryID: cautionID, wordingVersion: version, whatWasCommunicated: communicated, at: at,
                                             language: language, interpreter: interpreter.isEmpty ? nil : interpreter,
                                             personResponse: response, subsequentSteps: steps))
                        dismiss()
                    }
                    .disabled(cautionID.isEmpty || communicated.isEmpty)
                }
            }
        }
    }
}

struct EvidenceEditorSheet: View {
    let onSave: (EvidenceItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var desc = ""
    @State private var provenance: FactProvenance = .officerObservation
    @State private var isOriginal = true
    @State private var preservation = ""
    @State private var disclosure = ""
    @State private var custodian = ""
    @State private var location = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Description", text: $desc, axis: .vertical)
                Picker("Provenance", selection: $provenance) { ForEach(FactProvenance.allCases, id: \.self) { Text($0.title).tag($0) } }
                Toggle("Original (not a working copy)", isOn: $isOriginal)
                Section("Continuity — first entry") {
                    TextField("Custodian", text: $custodian)
                    TextField("Location", text: $location)
                }
                Section("Preservation") { TextField("Preservation notes", text: $preservation, axis: .vertical) }
                Section("Disclosure") { TextField("Disclosure considerations", text: $disclosure, axis: .vertical) }
                Section { Text("Collection authority is marked unresolved until you link an authority card.").font(.footnote) }
            }
            .privacySensitive()
            .navigationTitle("Evidence item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var item = EvidenceItem(description: desc, provenance: provenance, isOriginal: isOriginal,
                                                preservationNotes: preservation, disclosureNotes: disclosure)
                        if !custodian.isEmpty { item.continuity.append(ContinuityEntry(at: Date(), custodian: custodian, location: location, action: "Received")) }
                        onSave(item)
                        dismiss()
                    }
                    .disabled(desc.isEmpty)
                }
            }
        }
    }
}

struct ExportScenarioSheet: View {
    let scenario: Scenario
    @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""
    @State private var exportURL: URL?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(ScenarioStore.exportWarning).font(.footnote)
                }
                Section("Passphrase (recommended, 12+ characters)") {
                    SecureField("Passphrase", text: $passphrase)
                }
                if let url = exportURL {
                    ShareLink(item: url) { Label("Share exported file", systemImage: "square.and.arrow.up") }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Export situation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { cleanup(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create file") { create() }
                }
            }
        }
    }

    private func create() {
        do {
            let data = try ScenarioStore.export(scenario, passphrase: passphrase.isEmpty ? nil : passphrase)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("situation-\(scenario.id.uuidString.prefix(8)).phqscenario")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            exportURL = url
            error = nil
        } catch ScenarioStoreError.weakPassphrase {
            error = "Use at least 12 characters, or leave the passphrase empty for an unencrypted file."
        } catch {
            self.error = "The file could not be created."
        }
    }

    private func cleanup() {
        if let u = exportURL { try? FileManager.default.removeItem(at: u) }
    }
}
