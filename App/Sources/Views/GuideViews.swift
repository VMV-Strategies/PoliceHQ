import SwiftUI
import PoliceHQCore

struct GuidesView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            Section("Hubs") {
                NavigationLink(value: Route.authorities) { Label("Authorities", systemImage: "shield.lefthalf.filled") }
                NavigationLink(value: Route.rights) { Label("Rights", systemImage: "person.badge.shield.checkmark") }
                NavigationLink(value: Route.cautions) { Label("Cautions", systemImage: "quote.bubble") }
                NavigationLink(value: Route.statutes) { Label("Statutes", systemImage: "books.vertical") }
            }
            if let store = model.store {
                Section("Offence guides") {
                    ForEach((try? store.guideEntries(kind: .offence)) ?? [], id: \.id) { e in
                        NavigationLink(value: Route.guide(e.id)) { GuideRow(entry: e) }
                    }
                }
                Section("Checklists") {
                    ForEach((try? store.guideEntries(kind: .checklist)) ?? [], id: \.id) { e in
                        NavigationLink(value: Route.guide(e.id)) { GuideRow(entry: e) }
                    }
                }
                Section {
                    NavigationLink { TrainingView() } label: { Label("Training scenarios (fictional)", systemImage: "graduationcap") }
                }
                Section {
                    LimitationBanner(title: "All guides are drafts", lines: ["No qualified legal review has been recorded for any guide in this package. Use them as source references, not operational approval."])
                }
            } else {
                NoContentView()
            }
        }
        .navigationTitle("Guides")
    }
}

struct GuideRow: View {
    let entry: GuideEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title).font(.body)
            HStack(spacing: 8) {
                ReviewBadge(status: entry.reviewStatus)
                if let b = entry.body.basisType {
                    Text(basisLabel(b)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func basisLabel(_ b: String) -> String {
        switch b {
        case "statutory": return "Statutory power"
        case "common-law": return "Common-law power — source not installed"
        case "judicial-authorization": return "Judicial authorization"
        case "consent": return "Consent-based pathway"
        default: return b
        }
    }
}

struct AuthoritiesHubView: View {
    var body: some View {
        List {
            Section {
                ForEach(AuthorityCategory.allCases, id: \.self) { c in
                    NavigationLink(value: Route.authorityCategory(c)) {
                        Label(c.title, systemImage: c.symbolName).font(.headline).padding(.vertical, 6)
                    }
                }
            } footer: {
                Text("Statutory powers, common-law powers, judicial authorizations and consent are labelled separately. Creating an offence does not create a power to arrest, enter, search or seize.")
            }
        }
        .navigationTitle("Authorities")
    }
}

struct AuthorityCategoryView: View {
    let category: AuthorityCategory
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            let entries = (try? model.store?.guideEntries(kind: .authority, category: category.rawValue)) ?? []
            if entries.isEmpty {
                Text("No \(category.title.lowercased()) authority cards are installed. This does not mean no authority exists.")
            }
            ForEach(entries, id: \.id) { e in
                NavigationLink(value: Route.guide(e.id)) { GuideRow(entry: e) }
            }
        }
        .navigationTitle(category.title)
    }
}

struct RightsHubView: View {
    var body: some View {
        List {
            Section {
                ForEach(EncounterStage.allCases, id: \.self) { s in
                    NavigationLink(value: Route.rightsStage(s)) { Text(s.title).font(.headline) }
                }
            } footer: {
                Text("Rights of suspects, detained and accused persons, including youth safeguards where the installed law provides them. Interpretation depends on case law that is not installed.")
            }
        }
        .navigationTitle("Rights")
    }
}

struct RightsStageView: View {
    let stage: EncounterStage
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            let rights = ((try? model.store?.guideEntries(kind: .right)) ?? []).filter { ($0.body.stages ?? []).contains(stage.rawValue) }
            ForEach(rights, id: \.id) { r in
                NavigationLink(value: Route.guide(r.id)) {
                    HStack {
                        GuideRow(entry: r)
                        if r.body.youth == true { Text("Youth").font(.caption2.weight(.bold)) }
                    }
                }
            }
            Section { Text("Reassess rights whenever the stage changes (for example detention becomes arrest).").font(.footnote) }
        }
        .navigationTitle(stage.title)
    }
}

struct CautionsLibraryView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            let cautions = (try? model.store?.guideEntries(kind: .caution)) ?? []
            Section {
                ForEach(cautions, id: \.id) { c in
                    NavigationLink(value: Route.guide(c.id)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.title)
                            if case .approvedWordingNotInstalled = CautionPresentation.make(for: c, level: model.settings.explanationLevel) {
                                StatusBadge(label: .notInstalled)
                            }
                        }
                    }
                }
            } footer: {
                Text("Available without a situation and without on-device assistance. The app never generates or paraphrases official wording.")
            }
        }
        .navigationTitle("Cautions")
    }
}

/// Detail for any guide kind. Exact quotations and conditions are identical at every explanation level.
struct GuideDetailView: View {
    let entryID: String
    @Environment(AppModel.self) private var model
    @State private var level: ExplanationLevel = .plainLanguage

    var body: some View {
        if let entry = try? model.store?.guideEntry(id: entryID) {
            let explained = ExplanationRenderer.render(entry, level: level)
            List {
                Section {
                    HStack { ReviewBadge(status: entry.reviewStatus); Spacer(); Text("v\(entry.version)").font(.caption).foregroundStyle(.secondary) }
                    Picker("Explanation", selection: $level) {
                        ForEach(ExplanationLevel.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                if entry.kind == .caution {
                    cautionSection(entry)
                }
                if let s = explained.summary {
                    Section {
                        Text(s)
                        Text(explained.summaryLabel).font(.caption).foregroundStyle(.secondary)
                    }
                } else if level != .legalAnalysis {
                    Section { Text(explained.summaryLabel).font(.footnote).foregroundStyle(.secondary) }
                }
                if !explained.invariant.quotes.isEmpty {
                    Section("Exact wording") {
                        ForEach(Array(explained.invariant.quotes.enumerated()), id: \.offset) { _, q in
                            QuoteBlock(label: q.label, text: q.text)
                        }
                    }
                }
                kindSpecific(entry)
                if !explained.invariant.conditions.isEmpty {
                    Section("Required conditions") { ForEach(explained.invariant.conditions, id: \.self) { Text($0) } }
                }
                if !explained.invariant.limits.isEmpty {
                    Section("Limits and exceptions") { ForEach(explained.invariant.limits, id: \.self) { Text($0) } }
                }
                Section("Sources") {
                    ForEach(entry.citations) { CitationRow(citation: $0, showExcerpt: explained.showFullExcerpts) }
                }
                gapsSection(explained.invariant.gaps)
            }
            .navigationTitle(entry.title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { level = model.settings.explanationLevel }
        } else {
            ContentUnavailableView("Guide not installed", systemImage: "doc.questionmark")
        }
    }

    @ViewBuilder
    private func cautionSection(_ entry: GuideEntry) -> some View {
        switch CautionPresentation.make(for: entry, level: level) {
        case .approvedWording(let text, let org, let version):
            Section("Approved wording — \(org), version \(version)") {
                ScrollView {
                    Text(text).font(.title3).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 200)
            }
        case .approvedWordingNotInstalled(let missing):
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(CautionPresentation.notInstalledTitle).font(.title3.weight(.semibold))
                    Text("Missing: \(missing)").font(.body)
                }
                .padding(.vertical, 6)
            }
        }
        Section("Purpose and circumstances") {
            if let p = entry.body.purpose { Text(p) }
            if let c = entry.body.applicableCircumstances { Text("Applies: \(c)").font(.footnote) }
            if let n = entry.body.statutoryContentNote { Text(n).font(.footnote).foregroundStyle(.secondary) }
        }
        if let steps = entry.body.accompanyingSteps, !steps.isEmpty {
            Section("Accompanying steps") { ForEach(steps, id: \.self) { Text($0) } }
        }
        Section {
            Text("Recording that wording was read does not establish understanding, a valid waiver or compliance.").font(.footnote)
        }
    }

    @ViewBuilder
    private func kindSpecific(_ e: GuideEntry) -> some View {
        let b = e.body
        if e.kind == .authority {
            Section("What the authority permits") {
                if let a = b.action { LabeledText(title: "Proposed action", text: a) }
                if let p = b.permits { LabeledText(title: "Permits", text: p) }
                if let w = b.who { LabeledText(title: "Who may exercise it", text: w) }
                if let t = b.territorialScope { LabeledText(title: "Territorial scope", text: t) }
                if let j = b.judicialAuthorization { LabeledText(title: "Judicial authorization", text: j) }
                if let p = b.pathway { LabeledText(title: "Pathway", text: p) }
            }
            if let n = b.notAuthorityFor, !n.isEmpty {
                Section("Not authority for") { ForEach(n, id: \.self) { Label($0, systemImage: "nosign") } }
            }
            linkSection("Linked rights", ids: b.linkedRights)
            linkSection("Linked cautions", ids: b.linkedCautions)
            linkSection("Linked checklists", ids: b.linkedChecklists)
            if let d = b.documentation, !d.isEmpty { Section("Documentation") { ForEach(d, id: \.self) { Text($0) } } }
            if let f = b.followUp, !f.isEmpty { Section("Follow-up obligations") { ForEach(f, id: \.self) { Text($0) } } }
            if let rule = b.deadlineRule {
                Section("Timing") {
                    Text(rule.statutoryText).font(.body.weight(.medium))
                    if case .notCalculated(let reason) = DeadlineCalculator.deadline(rule: rule, reviewStatus: e.reviewStatus, triggerTime: nil, hours: nil) {
                        Text(reason).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        } else if e.kind == .right {
            Section("Who and when") {
                if let p = b.protects { LabeledText(title: "Protects", text: p) }
                if let t = b.triggers { LabeledText(title: "Triggered by", text: t) }
                if let t = b.timing { LabeledText(title: "Timing", text: t) }
            }
            if let o = b.officerObligations, !o.isEmpty { Section("Officer obligations") { ForEach(o, id: \.self) { Text($0) } } }
            if let c = b.communication, !c.isEmpty { Section("Comprehension, language and communication") { ForEach(c, id: \.self) { Text($0) } } }
            if let d = b.documentation, !d.isEmpty { Section("Documentation") { ForEach(d, id: \.self) { Text($0) } } }
            linkSection("Linked authorities", ids: b.linkedAuthorities)
            linkSection("Linked cautions", ids: b.linkedCautions)
        } else if e.kind == .offence {
            Section("Elements and facts in issue") {
                ForEach(b.elements ?? []) { el in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(el.text).font(.body.weight(.medium))
                        if let q = el.quote { QuoteBlock(label: nil, text: q) }
                        if el.isGeneralFact { Text(el.basis ?? "").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            if let d = b.defences, !d.isEmpty {
                Section("Exceptions and defences") { ForEach(d, id: \.self) { def in VStack(alignment: .leading) { Text(def.text); QuoteBlock(label: nil, text: def.quote) } } }
            }
            Section { NavigationLink(value: Route.penalties(e.id)) { Label("Penalties and points", systemImage: "dollarsign.circle") } }
        } else if e.kind == .checklist {
            Section("Items") {
                ForEach(b.items ?? []) { it in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(it.requirement)
                        Text("Trigger: \(it.trigger) · Applies: \(it.applicability)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func linkSection(_ title: String, ids: [String]?) -> some View {
        if let ids, !ids.isEmpty {
            Section(title) {
                ForEach(ids, id: \.self) { id in
                    NavigationLink(value: Route.guide(id)) { Text((try? model.store?.guideEntry(id: id))?.title ?? id) }
                }
            }
        }
    }

    @ViewBuilder
    private func gapsSection(_ gapIDs: [String]) -> some View {
        let gaps = ((try? model.store?.coverageGaps()) ?? []).filter { gapIDs.contains($0.id) }
        if !gaps.isEmpty {
            Section {
                LimitationBanner(title: "Coverage limitations", lines: gaps.map { "\($0.title): \($0.description)" })
            }
        }
    }
}

struct LabeledText: View {
    let title: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(text)
        }
    }
}

/// Penalties and points panel. Missing components are shown as such, never as zero.
struct PenaltiesPanelView: View {
    let offenceEntryID: String
    @Environment(AppModel.self) private var model
    @State private var offenceDate = Date()
    @State private var useDate = false
    @State private var kmh = ""
    @State private var conviction = 1

    var body: some View {
        let comps = (try? model.store?.penaltyComponents(offenceEntryID: offenceEntryID)) ?? []
        let b = PenaltyCalculator.breakdown(offenceEntryID: offenceEntryID, components: comps,
                                            inputs: PenaltyInputs(offenceDate: useDate ? offenceDate : nil, kmhOverLimit: Int(kmh), convictionOrdinal: conviction))
        List {
            Section("Facts needed") {
                Toggle("Offence date known", isOn: $useDate)
                if useDate { DatePicker("Offence date", selection: $offenceDate, displayedComponents: .date) }
                if comps.contains(where: { ($0.conditionsJSON ?? "").contains("kmh_over_limit") }) {
                    TextField("km/h over the limit", text: $kmh).keyboardType(.numberPad)
                }
            }
            Section("Ticket amounts") {
                PenaltyLine(title: "Set fine", value: b.setFine.display)
                PenaltyLine(title: "Victim fine surcharge", value: b.victimFineSurcharge.display)
                PenaltyLine(title: "Court costs", value: b.courtCosts.display)
                PenaltyLine(title: "Other applicable prescribed charges", value: b.otherCharges.display)
                PenaltyLine(title: "Total payable", value: b.total.display, emphasized: true)
                PenaltyLine(title: "Demerit points", value: b.demeritPoints.display)
                if case .cannotVerify(let missing) = b.total {
                    Text("Missing: \(missing.joined(separator: ", ")). See Content status for what is not installed.").font(.footnote)
                }
                if case .courtDetermined(let why) = b.total { Text(why).font(.footnote) }
            }
            if !b.statutoryCalculations.isEmpty || !b.statutoryRanges.isEmpty {
                Section {
                    ForEach(b.statutoryCalculations, id: \.componentID) { c in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.cents.map { Money.format(cents: $0) } ?? "—").font(.title3.weight(.semibold))
                            Text(c.explanation).font(.footnote)
                            if let pid = c.provisionID { NavigationLink("Source", value: Route.provision(pid)) }
                        }
                    }
                    ForEach(b.statutoryRanges) { r in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rangeText(r)).font(.body.weight(.medium))
                            Text(r.applies).font(.footnote)
                            if let n = r.notes, !n.isEmpty { Text(n).font(.caption).foregroundStyle(.secondary) }
                            if let pid = r.provisionID { NavigationLink("Source", value: Route.provision(pid)) }
                        }
                    }
                } header: {
                    Text("Statutory fines and ranges on conviction")
                } footer: {
                    Text("These are not ticket amounts and are never added to a ticket total. A statutory maximum is never the ordinary ticket amount.")
                }
            }
            if !b.administrativePenalties.isEmpty {
                Section("Administrative penalties (separate process)") {
                    ForEach(Array(b.administrativePenalties.enumerated()), id: \.offset) { _, v in Text(v.display) }
                }
            }
            Section { ForEach(b.notes, id: \.self) { Text($0).font(.footnote) } }
            Section("Component sources") {
                ForEach(comps) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(c.component.rawValue) — \(c.status.rawValue)").font(.caption.weight(.semibold))
                        if let n = c.notes, !n.isEmpty { Text(n).font(.caption) }
                        if let pid = c.provisionID { NavigationLink("Open source", value: Route.provision(pid)).font(.caption) }
                    }
                }
            }
        }
        .navigationTitle("Penalties and points")
    }

    private func rangeText(_ r: StatutoryRangeLine) -> String {
        switch (r.minCents, r.maxCents) {
        case let (min?, max?): return "\(Money.format(cents: min)) to \(Money.format(cents: max))"
        case let (nil, max?): return "Up to \(Money.format(cents: max))"
        case let (min?, nil): return "At least \(Money.format(cents: min))"
        default: return "Non-monetary or court-determined (see source)"
        }
    }
}

struct PenaltyLine: View {
    let title: String
    let value: String
    var emphasized = false
    var body: some View {
        HStack {
            Text(title).font(emphasized ? .body.weight(.semibold) : .body)
            Spacer()
            Text(value).font(emphasized ? .body.weight(.semibold) : .body).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Fictional training scenarios bundled with the app, clearly separated from real work.
struct TrainingView: View {
    @Environment(AppModel.self) private var model
    @State private var opened: UUID?

    struct TrainingItem: Decodable, Identifiable {
        let id: String
        let title: String
        let narrative: String
    }

    private var items: [TrainingItem] {
        guard let url = Bundle.main.url(forResource: "TrainingScenarios", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([TrainingItem].self, from: data) else { return [] }
        return list
    }

    var body: some View {
        List {
            Section { Text("All training scenarios are fictional. They are saved with a Training label and never mixed with real situations.").font(.footnote) }
            ForEach(items) { t in
                Button {
                    var s = Scenario(title: "Training: \(t.title)", narrative: t.narrative, isTraining: true)
                    s.city = .notSelected
                    model.save(s)
                    opened = s.id
                } label: {
                    VStack(alignment: .leading) { Text(t.title).font(.headline); Text(t.narrative).font(.footnote).lineLimit(3) }
                }
            }
        }
        .navigationTitle("Training")
        .navigationDestination(item: $opened) { ScenarioWorkspaceView(scenarioID: $0) }
    }
}
