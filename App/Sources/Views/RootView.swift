import SwiftUI
import PoliceHQCore

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            NavigationStack { HomeView().navigationDestination(for: Route.self) { RouteDestination(route: $0) } }
                .tabItem { Label("Situation", systemImage: "text.bubble") }
            NavigationStack { GuidesView().navigationDestination(for: Route.self) { RouteDestination(route: $0) } }
                .tabItem { Label("Guides", systemImage: "list.bullet.rectangle") }
            NavigationStack { SearchView().navigationDestination(for: Route.self) { RouteDestination(route: $0) } }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            NavigationStack { SavedView().navigationDestination(for: Route.self) { RouteDestination(route: $0) } }
                .tabItem { Label("Saved", systemImage: "folder") }
        }
        .alert("Something needs attention", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK", role: .cancel) { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }
}

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var narrative = ""
    @State private var openScenario: UUID?
    @FocusState private var editorFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What are you dealing with?")
                        .font(.largeTitle.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Describe the situation, or choose a guide.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $narrative)
                        .focused($editorFocused)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(alignment: .topLeading) {
                            if narrative.isEmpty {
                                Text("For example: a store employee says a man took items without paying and left on foot…")
                                    .foregroundStyle(.tertiary).padding(16).allowsHitTesting(false)
                            }
                        }
                        .accessibilityLabel("Situation description")
                        .privacySensitive()
                    HStack {
                        Button {
                            startScenario(training: false)
                        } label: {
                            Label("Start", systemImage: "arrow.right.circle.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(narrative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.store == nil)
                    }
                    Text("Saved only on this device, encrypted. The original wording is kept; later corrections are added separately.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ShortcutTile(title: "Statutes", symbol: "books.vertical", route: .statutes)
                    ShortcutTile(title: "Authorities", symbol: "shield.lefthalf.filled", route: .authorities)
                    ShortcutTile(title: "Rights", symbol: "person.badge.shield.checkmark", route: .rights)
                    ShortcutTile(title: "Cautions", symbol: "quote.bubble", route: .cautions)
                }

                if let msg = model.contentMessage {
                    LimitationBanner(title: "Content", lines: [msg])
                }
                ContentSummaryCard()

                NavigationLink(value: Route.settings) {
                    Label("Settings and content status", systemImage: "gearshape")
                }
            }
            .padding()
        }
        .navigationTitle("Police HQ")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openScenario) { id in ScenarioWorkspaceView(scenarioID: id) }
    }

    private func startScenario(training: Bool) {
        let text = narrative.trimmingCharacters(in: .whitespacesAndNewlines)
        var s = Scenario(title: String(text.prefix(48)), narrative: text, isTraining: training)
        s.city = model.settings.defaultCity
        model.save(s)
        narrative = ""
        editorFocused = false
        openScenario = s.id
    }
}

struct ShortcutTile: View {
    let title: String
    let symbol: String
    let route: Route
    var body: some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol).font(.title2).accessibilityHidden(true)
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .padding()
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct ContentSummaryCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        NavigationLink(value: Route.contentStatus) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Installed content", systemImage: "shippingbox").font(.subheadline.weight(.semibold))
                    Spacer()
                    StatusBadge(label: .coverageIncomplete)
                }
                Text("Package \(model.manifest?.packageVersion ?? "not installed")")
                    .font(.footnote)
                Text("The import date is not a statement that the law is current. Each source shows its own consolidation date.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
