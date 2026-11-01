import Foundation

/// How the user's text is interpreted.
public enum SearchMode: String, Codable, CaseIterable, Sendable {
    case keywords
    case exactPhrase
    case sectionNumber

    public var title: String {
        switch self {
        case .keywords: return "Keywords"
        case .exactPhrase: return "Exact phrase"
        case .sectionNumber: return "Section number"
        }
    }
}

/// "Search this document" and "Search all sources" are separate, explicit scopes.
public enum SearchScope: Hashable, Codable, Sendable {
    case allSources(levels: Set<LegislativeLevel>, municipalities: Set<Municipality>)
    case document(sourceID: String)

    public static var everything: SearchScope {
        .allSources(levels: Set(LegislativeLevel.allCases), municipalities: Set(Municipality.allCases))
    }

    public var isDocumentScope: Bool {
        if case .document = self { return true }
        return false
    }
}

public struct SearchQuery: Hashable, Codable, Sendable {
    public var text: String
    public var mode: SearchMode
    public var scope: SearchScope
    /// Not-yet-in-force text and editorial annotations are excluded unless requested.
    public var includeNonOperative: Bool

    public init(text: String, mode: SearchMode = .keywords, scope: SearchScope = .everything, includeNonOperative: Bool = false) {
        self.text = text
        self.mode = mode
        self.scope = scope
        self.includeNonOperative = includeNonOperative
    }
}

public struct SearchHit: Identifiable, Hashable, Sendable {
    public enum Target: Hashable, Sendable {
        case provision(String)
        case page(Int)
    }

    public var id: String {
        switch target {
        case .provision(let p): return "p:\(p)"
        case .page(let n): return "pg:\(sourceID):\(n)"
        }
    }

    public let sourceID: String
    public let sourceTitle: String
    public let jurisdictionLabel: String
    public let target: Target
    public let label: String
    public let heading: String?
    /// Snippet with highlight markers: `SearchHit.highlightStart` / `highlightEnd`.
    public let snippet: String
    public let status: ProvisionStatus
    public let ordinal: Int

    public static let highlightStart = "\u{2}"
    public static let highlightEnd = "\u{3}"

    /// Ranges of highlighted text after removing markers; used by the UI.
    public var highlightedSegments: [(text: String, highlighted: Bool)] {
        var out: [(text: String, highlighted: Bool)] = []
        var current = ""
        var on = false
        for ch in snippet {
            let s = String(ch)
            if s == SearchHit.highlightStart || s == SearchHit.highlightEnd {
                if !current.isEmpty { out.append((text: current, highlighted: on)) }
                current = ""
                on = (s == SearchHit.highlightStart)
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { out.append((text: current, highlighted: on)) }
        return out
    }
}

/// Builds safe FTS5 match expressions; user text is never interpolated as FTS syntax.
public enum FTSQueryBuilder {
    public static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    public static func matchExpression(for text: String, mode: SearchMode) -> String? {
        let toks = tokens(text)
        guard !toks.isEmpty else { return nil }
        switch mode {
        case .exactPhrase:
            return "\"" + toks.joined(separator: " ") + "\""
        case .keywords, .sectionNumber:
            // every token must occur; the last token may be a prefix
            var parts = toks.dropLast().map { "\"\($0)\"" }
            parts.append("\"\(toks.last!)\"*")
            return parts.joined(separator: " AND ")
        }
    }
}

struct SearchEngine {
    let store: ContentStore

    func search(_ q: SearchQuery, limit: Int) throws -> [SearchHit] {
        if q.mode == .sectionNumber {
            return try sectionSearch(q, limit: limit)
        }
        guard let match = FTSQueryBuilder.matchExpression(for: q.text, mode: q.mode) else { return [] }
        var hits = try provisionSearch(q, match: match, limit: limit)
        // Page-level text is searched for sources whose structure is heuristic or image-based,
        // so municipal material remains findable even where sections were not recognised.
        hits += try pageSearch(q, match: match, limit: max(10, limit / 4))
        if q.scope.isDocumentScope {
            hits.sort { ($0.ordinal, $0.id) < ($1.ordinal, $1.id) }
        }
        return Array(hits.prefix(limit))
    }

    private func scopeClause(_ scope: SearchScope, alias: String) -> (String, [SQLValue]) {
        switch scope {
        case .document(let sid):
            return (" AND \(alias).source_id = ?", [.text(sid)])
        case .allSources(let levels, let munis):
            var clause = ""
            var params: [SQLValue] = []
            if levels.count < LegislativeLevel.allCases.count {
                let ph = Array(repeating: "?", count: max(levels.count, 1)).joined(separator: ",")
                clause += " AND s.level IN (\(ph))"
                params += levels.isEmpty ? [SQLValue.text("none")] : levels.map { SQLValue.text($0.rawValue) }
            }
            if levels.contains(.municipal) && munis.count < Municipality.allCases.count {
                let ph = Array(repeating: "?", count: max(munis.count, 1)).joined(separator: ",")
                clause += " AND (s.level != 'municipal' OR s.municipality IN (\(ph)))"
                params += munis.isEmpty ? [SQLValue.text("none")] : munis.map { SQLValue.text($0.rawValue) }
            }
            return (clause, params)
        }
    }

    private func provisionSearch(_ q: SearchQuery, match: String, limit: Int) throws -> [SearchHit] {
        let (clause, params) = scopeClause(q.scope, alias: "p")
        let statusClause = q.includeNonOperative ? "" : " AND p.status IN ('in-force','repealed','unknown')"
        let order = q.scope.isDocumentScope ? "p.ordinal" : "bm25(provisions_fts, 5.0, 3.0, 1.0)"
        let sql = """
            SELECT p.provision_id, p.source_id, s.title, s.jurisdiction_label, p.label, p.heading,
                   snippet(provisions_fts, 2, '\(SearchHit.highlightStart)', '\(SearchHit.highlightEnd)', '…', 14),
                   p.status, p.ordinal
            FROM provisions_fts JOIN provisions p ON p.rowid = provisions_fts.rowid
            JOIN sources s ON s.source_id = p.source_id
            WHERE provisions_fts MATCH ?\(clause)\(statusClause)
            ORDER BY \(order) LIMIT ?
            """
        return try store.db.query(sql, [SQLValue.text(match)] + params + [SQLValue.int(Int64(limit))]) {
            SearchHit(sourceID: $0.text(1), sourceTitle: $0.text(2), jurisdictionLabel: $0.text(3),
                      target: .provision($0.text(0)), label: $0.text(4), heading: $0.string(5), snippet: $0.text(6),
                      status: ProvisionStatus(rawValue: $0.text(7)) ?? .unknown, ordinal: $0.int(8) ?? 0)
        }
    }

    private func pageSearch(_ q: SearchQuery, match: String, limit: Int) throws -> [SearchHit] {
        let (clause, params) = scopeClause(q.scope, alias: "g")
        let sql = """
            SELECT g.source_id, s.title, s.jurisdiction_label, g.page,
                   snippet(pages_fts, 0, '\(SearchHit.highlightStart)', '\(SearchHit.highlightEnd)', '…', 14), g.ocr
            FROM pages_fts JOIN pages g ON g.rowid = pages_fts.rowid
            JOIN sources s ON s.source_id = g.source_id
            WHERE pages_fts MATCH ? AND s.extraction_quality IN ('heuristic-structure','image-only')\(clause)
            ORDER BY \(q.scope.isDocumentScope ? "g.page" : "bm25(pages_fts)") LIMIT ?
            """
        return try store.db.query(sql, [SQLValue.text(match)] + params + [SQLValue.int(Int64(limit))]) {
            let page = $0.int(3) ?? 0
            return SearchHit(sourceID: $0.text(0), sourceTitle: $0.text(1), jurisdictionLabel: $0.text(2),
                             target: .page(page), label: "Page \(page)" + ($0.bool(5) ? " (OCR, unverified)" : ""),
                             heading: nil, snippet: $0.text(4), status: .unknown, ordinal: 1_000_000 + page)
        }
    }

    private func sectionSearch(_ q: SearchQuery, limit: Int) throws -> [SearchHit] {
        let cleaned = q.text.replacingOccurrences(of: "s.", with: "").replacingOccurrences(of: "section", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return [] }
        let (clause, params) = scopeClause(q.scope, alias: "p")
        let sql = """
            SELECT p.provision_id, p.source_id, s.title, s.jurisdiction_label, p.label, p.heading,
                   substr(coalesce(p.text, ''), 1, 160), p.status, p.ordinal
            FROM provisions p JOIN sources s ON s.source_id = p.source_id
            WHERE (p.path = ? OR p.path LIKE ?) AND p.status = 'in-force'\(clause)
            ORDER BY p.source_id, p.ordinal LIMIT ?
            """
        return try store.db.query(sql, [SQLValue.text(cleaned), SQLValue.text("%:\(cleaned)")] + params + [SQLValue.int(Int64(limit))]) {
            SearchHit(sourceID: $0.text(1), sourceTitle: $0.text(2), jurisdictionLabel: $0.text(3),
                      target: .provision($0.text(0)), label: $0.text(4), heading: $0.string(5), snippet: $0.text(6),
                      status: ProvisionStatus(rawValue: $0.text(7)) ?? .unknown, ordinal: $0.int(8) ?? 0)
        }
    }
}
