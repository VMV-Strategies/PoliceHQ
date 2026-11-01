import Foundation

/// Read-only access to an installed content package database. Purely local:
/// this type has no networking code paths.
public final class ContentStore {
    public let db: SQLiteDatabase
    public let packageDirectory: URL?
    private let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    public init(database: SQLiteDatabase, packageDirectory: URL?) {
        self.db = database
        self.packageDirectory = packageDirectory
    }

    /// Opens `content.sqlite` inside an installed package directory.
    public convenience init(packageDirectory: URL) throws {
        let dbURL = packageDirectory.appendingPathComponent("content.sqlite")
        try self.init(database: SQLiteDatabase(path: dbURL.path, readOnly: true), packageDirectory: packageDirectory)
    }

    // MARK: Package

    public func packageInfo() throws -> PackageInfo {
        let pairs = try db.query("SELECT key, value FROM package_info") { ($0.text(0), $0.text(1)) }
        return PackageInfo(values: Dictionary(pairs, uniquingKeysWith: { a, _ in a }))
    }

    public func originalFileURL(for source: Source) -> URL? {
        guard let dir = packageDirectory, let rel = source.originalPath else { return nil }
        return dir.appendingPathComponent(rel)
    }

    // MARK: Sources

    private static let sourceColumns = """
        source_id, title, citation, abbreviations, doc_type, level, jurisdiction_label, municipality, municipality_basis,
        issuing_authority, territorial_application, enforcement_responsibility, official_url, official_url_status,
        original_filename, sha256, original_path, format, pages, consolidation, last_amended, verification_status,
        verification_date, publisher_status, extraction_method, extraction_quality, quality_notes,
        editorial_review_status, trusted_for_guidance, language_handling
        """

    private func mapSource(_ r: SQLiteRow) -> Source {
        let abbr = (try? JSONDecoder().decode([String].self, from: Data(r.text(3).utf8))) ?? []
        return Source(
            id: r.text(0), title: r.text(1), citation: r.string(2), abbreviations: abbr, docType: r.text(4),
            level: LegislativeLevel(rawValue: r.text(5)) ?? .federal, jurisdictionLabel: r.text(6),
            municipality: r.string(7).flatMap(Municipality.init(rawValue:)), municipalityBasis: r.string(8),
            issuingAuthority: r.string(9), territorialApplication: r.string(10), enforcementResponsibility: r.string(11),
            officialURL: r.string(12), officialURLStatus: r.text(13), originalFilename: r.text(14), sha256: r.text(15),
            originalPath: r.string(16), format: r.text(17), pages: r.int(18), consolidation: r.string(19),
            lastAmended: r.string(20), verificationStatus: r.text(21), verificationDate: r.string(22),
            publisherStatus: r.text(23), extractionMethod: r.text(24),
            extractionQuality: ExtractionQuality(rawValue: r.text(25)) ?? .unusable, qualityNotes: r.string(26),
            reviewStatus: ReviewStatus(rawValue: r.text(27)) ?? .imported, trustedForGuidance: r.bool(28),
            languageHandling: r.string(29))
    }

    public func allSources() throws -> [Source] {
        try db.query("SELECT \(Self.sourceColumns) FROM sources ORDER BY level, title", map: mapSource)
    }

    public func source(id: String) throws -> Source? {
        try db.query("SELECT \(Self.sourceColumns) FROM sources WHERE source_id = ?", [.text(id)], map: mapSource).first
    }

    /// Finds documents by title, abbreviation, citation or by-law number.
    public func findSources(matching text: String) throws -> [Source] {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return try allSources() }
        let like = "%\(q.replacingOccurrences(of: "%", with: ""))%"
        return try db.query("""
            SELECT \(Self.sourceColumns) FROM sources
            WHERE title LIKE ? OR citation LIKE ? OR abbreviations LIKE ? OR source_id LIKE ?
            ORDER BY CASE WHEN abbreviations LIKE ? THEN 0 ELSE 1 END, title
            """, [.text(like), .text(like), .text("%\"\(q)\"%"), .text(like), .text("%\"\(q)\"%")], map: mapSource)
    }

    public func relationships(for sourceID: String) throws -> [(relation: String, targetID: String, basis: String?, verified: Bool)] {
        try db.query("SELECT relation, target_id, basis, verified FROM source_relationships WHERE source_id = ? UNION ALL SELECT 'has-' || relation, source_id, basis, verified FROM source_relationships WHERE target_id = ?",
                     [.text(sourceID), .text(sourceID)]) { (relation: $0.text(0), targetID: $0.text(1), basis: $0.string(2), verified: $0.bool(3)) }
    }

    // MARK: Provisions

    private static let provisionColumns = "provision_id, source_id, parent_id, kind, number, path, label, heading, text, status, history, notes, page_start, page_end, ordinal, depth"

    private func mapProvision(_ r: SQLiteRow) -> Provision {
        let notes = r.string(11).flatMap { try? JSONDecoder().decode([String].self, from: Data($0.utf8)) } ?? []
        return Provision(id: r.text(0), sourceID: r.text(1), parentID: r.string(2), kind: r.text(3), number: r.string(4),
                         path: r.text(5), label: r.text(6), heading: r.string(7), text: r.string(8),
                         status: ProvisionStatus(rawValue: r.text(9)) ?? .unknown, history: r.string(10), notes: notes,
                         pageStart: r.int(12), pageEnd: r.int(13), ordinal: r.int(14) ?? 0, depth: r.int(15) ?? 0)
    }

    public func provision(id: String) throws -> Provision? {
        try db.query("SELECT \(Self.provisionColumns) FROM provisions WHERE provision_id = ?", [.text(id)], map: mapProvision).first
    }

    /// Provision lookup by section path within one source, e.g. ("ca-criminal-code", "495(1)").
    public func provision(sourceID: String, path: String, status: ProvisionStatus = .inForce) throws -> Provision? {
        try db.query("SELECT \(Self.provisionColumns) FROM provisions WHERE source_id = ? AND path = ? AND status = ? LIMIT 1",
                     [.text(sourceID), .text(path), .text(status.rawValue)], map: mapProvision).first
    }

    /// Table of contents: parts, schedules, headings and sections in document order.
    public func tableOfContents(sourceID: String) throws -> [Provision] {
        try db.query("""
            SELECT \(Self.provisionColumns) FROM provisions
            WHERE source_id = ? AND kind IN ('part','schedule','section','heading') AND status != 'annotation'
            ORDER BY ordinal
            """, [.text(sourceID)], map: mapProvision)
    }

    /// Every provision of a source in document order (for the reader).
    public func provisions(sourceID: String) throws -> [Provision] {
        try db.query("SELECT \(Self.provisionColumns) FROM provisions WHERE source_id = ? ORDER BY ordinal",
                     [.text(sourceID)], map: mapProvision)
    }

    /// A provision and its descendants in reading order (same status only).
    public func subtree(of provision: Provision) throws -> [Provision] {
        let rows = try db.query("SELECT \(Self.provisionColumns) FROM provisions WHERE source_id = ? AND ordinal >= ? ORDER BY ordinal LIMIT 400",
                                [.text(provision.sourceID), .int(Int64(provision.ordinal))], map: mapProvision)
        var out: [Provision] = []
        for p in rows {
            if p.id == provision.id { out.append(p); continue }
            if p.path.hasPrefix(provision.path + "(") || p.path.hasPrefix(provision.path + "[") {
                if p.status == provision.status { out.append(p) }
            } else if p.kind == "heading" || p.kind == "note" {
                continue
            } else {
                break
            }
        }
        return out
    }

    /// Jump target for a section number typed by the user (e.g. "495", "495(1)(a)", "s. 8").
    public func jump(sourceID: String, to sectionText: String) throws -> Provision? {
        let cleaned = sectionText.replacingOccurrences(of: "s.", with: "").replacingOccurrences(of: " ", with: "")
        if let exact = try provision(sourceID: sourceID, path: cleaned) { return exact }
        // Constitution Acts paths carry an Act prefix (e.g. "CA1982:8").
        return try db.query("SELECT \(Self.provisionColumns) FROM provisions WHERE source_id = ? AND (path LIKE ? OR path = ?) AND status = 'in-force' ORDER BY ordinal LIMIT 1",
                            [.text(sourceID), .text("%:\(cleaned)"), .text(cleaned)], map: mapProvision).first
    }

    public func pages(sourceID: String) throws -> [PageRecord] {
        try db.query("SELECT source_id, page, region, text, ocr, image_only FROM pages WHERE source_id = ? ORDER BY page",
                     [.text(sourceID)]) {
            PageRecord(sourceID: $0.text(0), page: $0.int(1) ?? 0, region: $0.string(2), text: $0.text(3),
                       isOCR: $0.bool(4), isImageOnly: $0.bool(5))
        }
    }

    public func definitions(term: String, sourceID: String? = nil) throws -> [Definition] {
        var sql = "SELECT source_id, term, provision_id FROM definitions WHERE term LIKE ?"
        var params: [SQLValue] = [.text(term)]
        if let s = sourceID { sql += " AND source_id = ?"; params.append(.text(s)) }
        return try db.query(sql, params) { Definition(sourceID: $0.text(0), term: $0.text(1), provisionID: $0.text(2)) }
    }

    // MARK: Guides

    public func guideEntries(kind: GuideKind? = nil, category: String? = nil) throws -> [GuideEntry] {
        var sql = "SELECT entry_id, kind, category, title, review_status, version, body_json FROM guide_entries WHERE 1=1"
        var params: [SQLValue] = []
        if let k = kind { sql += " AND kind = ?"; params.append(.text(k.rawValue)) }
        if let c = category { sql += " AND category = ?"; params.append(.text(c)) }
        sql += " ORDER BY rowid"
        let rows: [(String, String, String?, String, String, String, String)] = try db.query(sql, params) {
            ($0.text(0), $0.text(1), $0.string(2), $0.text(3), $0.text(4), $0.text(5), $0.text(6))
        }
        return try rows.map { r in
            let body = (try? jsonDecoder.decode(GuideBody.self, from: Data(r.6.utf8))) ?? GuideBody()
            return GuideEntry(id: r.0, kind: GuideKind(rawValue: r.1) ?? .authority, category: r.2, title: r.3,
                              reviewStatus: ReviewStatus(rawValue: r.4) ?? .interpretationDrafted, version: r.5,
                              body: body, citations: try citations(entryID: r.0))
        }
    }

    public func guideEntry(id: String) throws -> GuideEntry? {
        try guideEntries().first { $0.id == id }
    }

    public func citations(entryID: String) throws -> [GuideCitation] {
        let rows: [(String, String, String, String, String)] = try db.query(
            "SELECT role, source_id, provision_id, pinpoint, excerpt FROM guide_citations WHERE entry_id = ? ORDER BY rowid",
            [.text(entryID)]) { ($0.text(0), $0.text(1), $0.text(2), $0.text(3), $0.text(4)) }
        return rows.enumerated().map { i, r in
            GuideCitation(entryID: entryID, index: i, role: r.0, sourceID: r.1, provisionID: r.2, pinpoint: r.3, excerpt: r.4)
        }
    }

    /// Entries that cite a given source (for "Authorities" links from source pages).
    public func entriesCiting(sourceID: String) throws -> [String] {
        try db.query("SELECT DISTINCT entry_id FROM guide_citations WHERE source_id = ?", [.text(sourceID)]) { $0.text(0) }
    }

    public func coverageGaps() throws -> [CoverageGap] {
        try db.query("SELECT gap_id, category, title, description, affects, acquisition FROM coverage_gaps ORDER BY rowid") {
            let affects = (try? JSONDecoder().decode([String].self, from: Data($0.text(4).utf8))) ?? []
            return CoverageGap(id: $0.text(0), category: $0.text(1), title: $0.text(2), description: $0.text(3),
                               affects: affects, acquisition: $0.string(5))
        }
    }

    public func penaltyComponents(offenceEntryID: String) throws -> [PenaltyComponentRecord] {
        try db.query("""
            SELECT component_id, offence_entry_id, jurisdiction, component, amount_cents, points, range_min_cents,
                   range_max_cents, status, provision_id, excerpt, effective_from, effective_to, date_trigger,
                   conditions_json, notes
            FROM penalty_components WHERE offence_entry_id = ? ORDER BY rowid
            """, [.text(offenceEntryID)]) {
            PenaltyComponentRecord(id: $0.text(0), offenceEntryID: $0.string(1), jurisdiction: $0.text(2),
                                   component: PenaltyComponentKind(rawValue: $0.text(3)) ?? .otherCharge,
                                   amountCents: $0.int(4), points: $0.int(5), rangeMinCents: $0.int(6),
                                   rangeMaxCents: $0.int(7), status: PenaltyDataStatus(rawValue: $0.text(8)) ?? .notVerified,
                                   provisionID: $0.string(9), excerpt: $0.string(10), effectiveFrom: $0.string(11),
                                   effectiveTo: $0.string(12), dateTrigger: $0.string(13), conditionsJSON: $0.string(14),
                                   notes: $0.string(15))
        }
    }

    // MARK: Search

    public func search(_ query: SearchQuery, limit: Int = 100) throws -> [SearchHit] {
        try SearchEngine(store: self).search(query, limit: limit)
    }
}
