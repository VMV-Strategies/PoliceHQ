import SwiftUI
import QuickLook
import PoliceHQCore

/// Search all sources. "Search this document" lives inside each document and is labelled separately.
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var mode: SearchMode = .keywords
    @State private var levels: Set<LegislativeLevel> = Set(LegislativeLevel.allCases)
    @State private var municipalities: Set<Municipality> = Set(Municipality.allCases)
    @State private var includeNonOperative = false
    @State private var hits: [SearchHit] = []

    private var query: SearchQuery {
        SearchQuery(text: text, mode: mode, scope: .allSources(levels: levels, municipalities: municipalities), includeNonOperative: includeNonOperative)
    }

    var body: some View {
        List {
            Section {
                NavigationLink(value: Route.statutes) { Label("Statutes browser", systemImage: "books.vertical") }
            }
            Section("Search all sources") {
                Picker("Mode", selection: $mode) { ForEach(SearchMode.allCases, id: \.self) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented)
                DisclosureGroup("Filters") {
                    ForEach(LegislativeLevel.allCases, id: \.self) { l in
                        Toggle(l.displayName, isOn: Binding(get: { levels.contains(l) }, set: { on in if on { levels.insert(l) } else { levels.remove(l) } }))
                    }
                    ForEach(Municipality.allCases, id: \.self) { m in
                        Toggle("Municipal — \(m.displayName)", isOn: Binding(get: { municipalities.contains(m) }, set: { on in if on { municipalities.insert(m) } else { municipalities.remove(m) } }))
                    }
                    Toggle("Include not-yet-in-force text and annotations", isOn: $includeNonOperative)
                }
            }
            if model.store == nil { NoContentView() }
            if !hits.isEmpty {
                Section("\(hits.count) results") {
                    ForEach(hits) { h in SearchHitRow(hit: h) }
                }
                Section { Button("Save this search", systemImage: "bookmark") { model.saveSearch(query) } }
            } else if !text.isEmpty {
                Section { Text("No matches in the installed material. This does not mean the law contains nothing relevant.").font(.footnote) }
            }
        }
        .navigationTitle("Search")
        .searchable(text: $text, prompt: "Search all sources")
        .onSubmit(of: .search) { run() }
        .onChange(of: mode) { _, _ in run() }
        .onChange(of: levels) { _, _ in run() }
        .onChange(of: municipalities) { _, _ in run() }
        .onChange(of: includeNonOperative) { _, _ in run() }
    }

    private func run() {
        guard let store = model.store, !text.trimmingCharacters(in: .whitespaces).isEmpty else { hits = []; return }
        hits = (try? store.search(query, limit: 150)) ?? []
    }
}

struct SearchHitRow: View {
    let hit: SearchHit
    var body: some View {
        NavigationLink(value: destination) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(hit.sourceTitle).font(.caption.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Text(hit.jurisdictionLabel).font(.caption2).foregroundStyle(.secondary)
                }
                Text(hit.label + (hit.heading.map { " — \($0)" } ?? "")).font(.subheadline.weight(.medium))
                HighlightedText(segments: hit.highlightedSegments).font(.footnote).lineLimit(4)
                if hit.status != .inForce && hit.status != .unknown {
                    Text(hit.status.label).font(.caption2.weight(.bold)).foregroundStyle(.orange)
                }
            }
        }
    }

    private var destination: Route {
        switch hit.target {
        case .provision(let id): return .provision(id)
        case .page: return .source(hit.sourceID)
        }
    }
}

struct StatutesBrowserView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ""
    @State private var municipal: Municipality?

    var body: some View {
        List {
            if let store = model.store {
                let sources = ((try? store.findSources(matching: filter)) ?? [])
                Section {
                    Picker("Municipal filter", selection: $municipal) {
                        Text("All").tag(Municipality?.none)
                        ForEach(Municipality.allCases, id: \.self) { Text($0.displayName).tag(Municipality?.some($0)) }
                    }
                }
                ForEach([LegislativeLevel.constitutional, .federal, .provincial, .municipal], id: \.self) { level in
                    let group = sources.filter { $0.level == level && (level != .municipal || municipal == nil || $0.municipality == municipal) }
                    if !group.isEmpty {
                        Section("\(level.displayName) (\(group.count))") {
                            ForEach(group) { s in
                                NavigationLink(value: Route.source(s.id)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.title)
                                        Text([s.citation, s.jurisdictionLabel].compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                NoContentView()
            }
        }
        .navigationTitle("Statutes")
        .searchable(text: $filter, prompt: "Title, abbreviation, citation or by-law number")
    }
}

/// Document reader with table of contents, jump-to-section, in-document search and match navigation.
struct DocumentView: View {
    let sourceID: String
    let focusProvisionID: String?
    @Environment(AppModel.self) private var model
    @State private var provisions: [Provision] = []
    @State private var pages: [PageRecord] = []
    @State private var source: Source?
    @State private var docQuery = ""
    @State private var matches: [SearchHit] = []
    @State private var matchIndex = 0
    @State private var showTOC = false
    @State private var showOriginal = false
    @State private var jumpText = ""
    @State private var scrollTarget: String?
    @State private var showPages = false

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if let s = source { header(s) }
                Section {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass").accessibilityHidden(true)
                        TextField("Search this document", text: $docQuery).onSubmit(runDocSearch).submitLabel(.search)
                    }
                    if !matches.isEmpty {
                        HStack {
                            Text("Match \(matchIndex + 1) of \(matches.count)").font(.footnote)
                            Spacer()
                            Button { step(-1, proxy) } label: { Image(systemName: "chevron.up") }.accessibilityLabel("Previous match")
                            Button { step(1, proxy) } label: { Image(systemName: "chevron.down") }.accessibilityLabel("Next match")
                        }
                        .buttonStyle(.borderless)
                    } else if !docQuery.isEmpty {
                        Text("No matches in this document.").font(.footnote).foregroundStyle(.secondary)
                    }
                    HStack {
                        TextField("Go to section (e.g. 495(1)(a))", text: $jumpText).onSubmit { jump(proxy) }
                        Button("Go") { jump(proxy) }.buttonStyle(.borderless)
                    }
                } header: {
                    Text("Search this document")
                }
                if showPages || provisions.filter({ !$0.isStructural }).count < 3 {
                    pagesSection
                } else {
                    provisionsSection
                }
            }
            .listStyle(.plain)
            .onAppear { load(); if let f = focusProvisionID { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation { proxy.scrollTo(f, anchor: .top) } } } }
            .onChange(of: scrollTarget) { _, t in if let t { withAnimation { proxy.scrollTo(t, anchor: .top) } } }
        }
        .navigationTitle(source?.title ?? "Document")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showTOC = true } label: { Image(systemName: "list.bullet.indent") }.accessibilityLabel("Table of contents")
                Menu {
                    Button("View original document", systemImage: "doc.richtext") { showOriginal = true }
                    Toggle("Show page text", isOn: $showPages)
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Document options")
            }
        }
        .sheet(isPresented: $showTOC) {
            NavigationStack {
                List(provisions.filter { $0.kind == "part" || $0.kind == "schedule" || $0.kind == "section" }) { p in
                    Button {
                        showTOC = false
                        scrollTarget = p.id
                    } label: {
                        Text(p.label + (p.heading.map { " — \($0)" } ?? ""))
                            .font(p.kind == "section" ? .body : .headline)
                    }
                }
                .navigationTitle("Contents")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showTOC = false } } }
            }
        }
        .sheet(isPresented: $showOriginal) {
            if let s = source, let url = model.store?.originalFileURL(for: s) {
                QuickLookPreview(url: url).ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private func header(_ s: Source) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(s.title).font(.title3.weight(.semibold))
                if let c = s.citation { Text(c).font(.subheadline) }
                HStack { JurisdictionBadge(label: s.jurisdictionLabel); Text(s.docType).font(.caption).foregroundStyle(.secondary) }
                Text(s.currencyLine).font(.footnote)
                Text(s.reproductionNotice).font(.caption).foregroundStyle(.secondary)
                Text(s.extractionQuality.label).font(.footnote).foregroundStyle(.secondary)
                if s.isReferenceConversion {
                    LimitationBanner(title: "Reference conversion", lines: ["Not a publisher-issued document. Amendment completeness has not been certified."])
                }
                if !s.trustedForGuidance {
                    Text("Reference material only — not used in guided analysis until its extraction is verified.").font(.caption).foregroundStyle(.orange)
                }
                if let basis = s.municipalityBasis, s.level == .municipal { Text("Jurisdiction basis: \(basis)").font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }

    private var provisionsSection: some View {
        ForEach(provisions) { p in
            ProvisionRow(provision: p, highlighted: p.id == focusProvisionID || matches.indices.contains(matchIndex) && matches[matchIndex].target == .provision(p.id),
                         sourceTitle: source?.title ?? "")
                .id(p.id)
        }
    }

    private var pagesSection: some View {
        ForEach(pages, id: \.page) { pg in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Page \(pg.page)").font(.caption.weight(.semibold))
                    if pg.isOCR { Text("OCR text — unverified").font(.caption2).foregroundStyle(.orange) }
                    if pg.isImageOnly && !pg.isOCR { Text("Image — view original").font(.caption2).foregroundStyle(.orange) }
                }
                Text(pg.text.isEmpty ? "No extractable text on this page." : pg.text).font(.footnote).textSelection(.enabled)
            }
            .id("page-\(pg.page)")
        }
    }

    private func load() {
        guard let store = model.store else { return }
        source = try? store.source(id: sourceID)
        provisions = (try? store.provisions(sourceID: sourceID)) ?? []
        pages = (try? store.pages(sourceID: sourceID)) ?? []
    }

    private func runDocSearch() {
        guard let store = model.store else { return }
        matches = (try? store.search(SearchQuery(text: docQuery, mode: .keywords, scope: .document(sourceID: sourceID)), limit: 500)) ?? []
        matchIndex = 0
        if let first = matches.first { focus(first) }
    }

    private func step(_ delta: Int, _ proxy: ScrollViewProxy) {
        guard !matches.isEmpty else { return }
        matchIndex = (matchIndex + delta + matches.count) % matches.count
        focus(matches[matchIndex])
    }

    private func focus(_ hit: SearchHit) {
        switch hit.target {
        case .provision(let id): showPages = false; scrollTarget = id
        case .page(let n): showPages = true; scrollTarget = "page-\(n)"
        }
    }

    private func jump(_ proxy: ScrollViewProxy) {
        guard let store = model.store, let p = try? store.jump(sourceID: sourceID, to: jumpText) else { return }
        showPages = false
        scrollTarget = p.id
    }
}

struct ProvisionRow: View {
    let provision: Provision
    let highlighted: Bool
    let sourceTitle: String
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if provision.kind == "part" || provision.kind == "schedule" {
                Text(provision.label + (provision.heading.map { " — \($0)" } ?? "")).font(.headline).padding(.top, 8)
            } else if provision.kind == "heading" {
                Text(provision.text ?? provision.label).font(.subheadline.weight(.semibold)).padding(.top, 4)
            } else {
                if let h = provision.heading, !h.isEmpty { Text(h).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                HStack(alignment: .firstTextBaseline) {
                    Text(provision.label).font(.footnote.monospacedDigit().weight(.semibold))
                    if provision.status != .inForce {
                        Text(provision.status.label).font(.caption2.weight(.bold)).foregroundStyle(.orange)
                    }
                    Spacer()
                    Button {
                        model.toggleBookmark(provision, sourceTitle: sourceTitle)
                    } label: {
                        Image(systemName: model.isBookmarked(provision) ? "bookmark.fill" : "bookmark")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(model.isBookmarked(provision) ? "Remove bookmark" : "Bookmark")
                }
                if let t = provision.text, !t.isEmpty { Text(t).textSelection(.enabled) }
                if let h = provision.history, !h.isEmpty { Text(h).font(.caption2).foregroundStyle(.secondary) }
                ForEach(provision.notes, id: \.self) { Text($0).font(.caption2).italic().foregroundStyle(.orange) }
            }
        }
        .padding(.leading, CGFloat(min(provision.depth, 4)) * 10)
        .listRowBackground(highlighted ? Color.accentColor.opacity(0.12) : Color.clear)
    }
}

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> QLPreviewController {
        let c = QLPreviewController()
        c.dataSource = context.coordinator
        return c
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
