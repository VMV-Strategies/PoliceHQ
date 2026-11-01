import SwiftUI
import PoliceHQCore

/// Status labels used across the app. Text is always present; colour is secondary.
enum StatusLabel: String {
    case informationMissing = "Information missing"
    case sourceAvailable = "Source available"
    case reviewRequired = "Review required"
    case recordedComplete = "Recorded complete"
    case coverageIncomplete = "Coverage incomplete"
    case notInstalled = "Not installed"
    case draft = "Draft — review required"

    var symbol: String {
        switch self {
        case .informationMissing: return "questionmark.circle"
        case .sourceAvailable: return "book.closed"
        case .reviewRequired, .draft: return "exclamationmark.triangle"
        case .recordedComplete: return "checkmark.circle"
        case .coverageIncomplete, .notInstalled: return "square.dashed"
        }
    }

    var tint: Color {
        switch self {
        case .recordedComplete: return .green
        case .reviewRequired, .draft: return .orange
        case .informationMissing: return .blue
        case .coverageIncomplete, .notInstalled: return .secondary
        case .sourceAvailable: return .accentColor
        }
    }
}

struct StatusBadge: View {
    let label: StatusLabel
    var body: some View {
        Label(label.rawValue, systemImage: label.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(label.tint.opacity(0.12), in: Capsule())
            .foregroundStyle(label.tint)
            .accessibilityElement(children: .combine)
    }
}

struct ReviewBadge: View {
    let status: ReviewStatus
    var body: some View {
        if status.isOperationallyApproved {
            Label(status.label, systemImage: "checkmark.seal")
                .font(.caption.weight(.semibold))
        } else {
            StatusBadge(label: .draft)
        }
    }
}

struct JurisdictionBadge: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(.secondary.opacity(0.4)))
            .accessibilityLabel("Jurisdiction: \(label)")
    }
}

/// Limitations are never collapsed: this banner is always visible where used.
struct LimitationBanner: View {
    let title: String
    let lines: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            ForEach(lines, id: \.self) { line in
                Text(line).font(.footnote).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

/// Exact statutory quotation. Never altered by explanation settings.
struct QuoteBlock: View {
    let label: String?
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label { Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
            Text("“\(text)”")
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .leading) { Rectangle().fill(Color.accentColor).frame(width: 3) }
        .accessibilityLabel("Quotation\(label.map { ", \($0)" } ?? ""): \(text)")
    }
}

/// A citation that opens the cited provision (back navigation returns to where you were).
struct CitationRow: View {
    let citation: GuideCitation
    var showExcerpt: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationLink(value: Route.provision(citation.provisionID)) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "book.closed").accessibilityHidden(true)
                    Text(sourceTitle).font(.subheadline.weight(.semibold))
                }
                Text(citation.pinpoint).font(.caption).foregroundStyle(.secondary)
                if showExcerpt {
                    Text(citation.excerpt).font(.footnote).lineLimit(12).foregroundStyle(.primary)
                }
            }
        }
        .accessibilityHint("Opens the cited provision")
    }

    private var sourceTitle: String {
        (try? model.store?.source(id: citation.sourceID))?.title ?? citation.sourceID
    }
}

/// Text with search highlights.
struct HighlightedText: View {
    let segments: [(text: String, highlighted: Bool)]
    var body: some View {
        segments.reduce(Text("")) { acc, seg in
            acc + (seg.highlighted ? Text(seg.text).bold().foregroundColor(.accentColor) : Text(seg.text))
        }
    }
}

struct SectionHeader: View {
    let title: String
    let systemImage: String
    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Navigation destinations shared by all stacks.
enum Route: Hashable {
    case source(String)
    case provision(String)
    case guide(String)
    case authorityCategory(AuthorityCategory)
    case rightsStage(EncounterStage)
    case statutes
    case authorities
    case rights
    case cautions
    case contentStatus
    case scenario(UUID)
    case penalties(String)
    case settings
}

struct RouteDestination: View {
    let route: Route
    var body: some View {
        switch route {
        case .source(let id): DocumentView(sourceID: id, focusProvisionID: nil)
        case .provision(let pid): ProvisionDestination(provisionID: pid)
        case .guide(let id): GuideDetailView(entryID: id)
        case .authorityCategory(let c): AuthorityCategoryView(category: c)
        case .rightsStage(let s): RightsStageView(stage: s)
        case .statutes: StatutesBrowserView()
        case .authorities: AuthoritiesHubView()
        case .rights: RightsHubView()
        case .cautions: CautionsLibraryView()
        case .contentStatus: ContentStatusView()
        case .scenario(let id): ScenarioWorkspaceView(scenarioID: id)
        case .penalties(let id): PenaltiesPanelView(offenceEntryID: id)
        case .settings: SettingsView()
        }
    }
}

/// Opens the document at the cited provision.
struct ProvisionDestination: View {
    let provisionID: String
    @Environment(AppModel.self) private var model
    var body: some View {
        if let p = try? model.store?.provision(id: provisionID) {
            DocumentView(sourceID: p.sourceID, focusProvisionID: p.id)
        } else {
            ContentUnavailableView("Provision not installed", systemImage: "doc.questionmark",
                                   description: Text("This provision is not in the installed content package."))
        }
    }
}

struct NoContentView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ContentUnavailableView {
            Label("No content installed", systemImage: "tray")
        } description: {
            Text(model.contentMessage ?? "Import a signed content package to use search, statutes and guides.")
        } actions: {
            NavigationLink("Content status", value: Route.contentStatus)
        }
    }
}
