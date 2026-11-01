-- Police HQ content package database schema (SQLite, FTS5).
-- Single source of truth: used by tools/phq_ingest/build_db.py and bundled
-- with the Swift core (PoliceHQCore) for tests. Bump schema_version on change.

PRAGMA foreign_keys = ON;

CREATE TABLE package_info (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- One row per distinct legal source document.
CREATE TABLE sources (
    source_id                TEXT PRIMARY KEY,
    title                    TEXT NOT NULL,
    title_basis              TEXT,
    citation                 TEXT,
    citation_basis           TEXT,
    abbreviations            TEXT,          -- JSON array
    doc_type                 TEXT NOT NULL, -- Act | regulation | by-law | by-law schedule | constitutional document | map (image) | sign (image) | ...
    level                    TEXT NOT NULL, -- federal | provincial | municipal | constitutional
    jurisdiction_label       TEXT NOT NULL, -- e.g. "Federal — Canada", "Municipal — Brampton"
    municipality             TEXT,          -- peel | brampton | mississauga | NULL
    municipality_basis       TEXT,
    issuing_authority        TEXT,
    territorial_application  TEXT,
    enforcement_responsibility TEXT,
    official_url             TEXT,
    official_url_status      TEXT NOT NULL,
    original_filename        TEXT NOT NULL,
    sha256                   TEXT NOT NULL,
    original_path            TEXT,          -- path inside the package
    format                   TEXT NOT NULL,
    pages                    INTEGER,
    consolidation            TEXT,          -- "current to" / consolidation period as printed
    last_amended             TEXT,
    effective_note           TEXT,
    retrieval_date           TEXT,
    verification_date        TEXT,
    verification_status      TEXT NOT NULL,
    publisher_status         TEXT NOT NULL,
    extraction_method        TEXT NOT NULL,
    extraction_quality       TEXT NOT NULL, -- automated-checks-passed | passed-with-warnings | heuristic-structure | image-only | unusable
    quality_notes            TEXT,
    editorial_review_status  TEXT NOT NULL, -- imported | extraction-verified | interpretation-drafted | legal-review-recorded | approved
    trusted_for_guidance     INTEGER NOT NULL DEFAULT 0,
    language_handling        TEXT,
    metadata_json            TEXT           -- full registry record
);

CREATE TABLE source_relationships (
    source_id   TEXT NOT NULL REFERENCES sources(source_id),
    relation    TEXT NOT NULL,
    target_id   TEXT NOT NULL REFERENCES sources(source_id),
    basis       TEXT,
    verified    INTEGER NOT NULL DEFAULT 0
);

-- Structured provisions. provision_id = "<source_id>:<path>[@status]".
CREATE TABLE provisions (
    provision_id  TEXT PRIMARY KEY,
    source_id     TEXT NOT NULL REFERENCES sources(source_id),
    parent_id     TEXT,
    kind          TEXT NOT NULL,
    number        TEXT,
    path          TEXT NOT NULL,
    label         TEXT NOT NULL,
    heading       TEXT,
    text          TEXT,
    status        TEXT NOT NULL,   -- in-force | not-yet-in-force | repealed | annotation | unknown
    history       TEXT,
    notes         TEXT,            -- JSON array of editorial notes
    page_start    INTEGER,
    page_end      INTEGER,
    ordinal       INTEGER NOT NULL,
    depth         INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX provisions_source ON provisions(source_id, ordinal);
CREATE INDEX provisions_path ON provisions(source_id, path);
CREATE INDEX provisions_parent ON provisions(parent_id);

CREATE TABLE pages (
    source_id  TEXT NOT NULL REFERENCES sources(source_id),
    page       INTEGER NOT NULL,
    region     TEXT,
    text       TEXT,
    ocr        INTEGER NOT NULL DEFAULT 0,
    image_only INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (source_id, page)
);

CREATE TABLE definitions (
    source_id    TEXT NOT NULL,
    term         TEXT NOT NULL,
    provision_id TEXT NOT NULL
);
CREATE INDEX definitions_term ON definitions(term);

-- Full-text indexes (external content). Porter stemming + unicode folding.
CREATE VIRTUAL TABLE provisions_fts USING fts5(
    label, heading, text,
    content='provisions', content_rowid='rowid',
    tokenize = "porter unicode61 remove_diacritics 2"
);
CREATE VIRTUAL TABLE pages_fts USING fts5(
    text,
    content='pages', content_rowid='rowid',
    tokenize = "porter unicode61 remove_diacritics 2"
);

-- Curated guide content (authorities, rights, cautions, offences, checklists).
-- Every entry carries its review status; nothing here is presented as approved
-- unless a qualified review record exists in review_records.
CREATE TABLE guide_entries (
    entry_id       TEXT PRIMARY KEY,
    kind           TEXT NOT NULL,   -- authority | right | caution | offence | checklist | penalty | gap
    category       TEXT,            -- arrest | detention | search | seizure | entry | release | stage names ...
    title          TEXT NOT NULL,
    review_status  TEXT NOT NULL,   -- interpretation-drafted | legal-review-recorded | approved
    version        TEXT NOT NULL,
    body_json      TEXT NOT NULL
);

CREATE TABLE guide_citations (
    entry_id      TEXT NOT NULL REFERENCES guide_entries(entry_id),
    role          TEXT NOT NULL,     -- basis | threshold | condition | limit | right | obligation | element | penalty | related
    source_id     TEXT NOT NULL REFERENCES sources(source_id),
    provision_id  TEXT NOT NULL REFERENCES provisions(provision_id),
    pinpoint      TEXT NOT NULL,
    excerpt       TEXT NOT NULL      -- verbatim text from the installed provision
);
CREATE INDEX guide_citations_entry ON guide_citations(entry_id);

CREATE TABLE coverage_gaps (
    gap_id       TEXT PRIMARY KEY,
    category     TEXT NOT NULL,     -- regulation | case-law | policy | caution-wording | schedule | penalty-data | by-law
    title        TEXT NOT NULL,
    description  TEXT NOT NULL,
    affects      TEXT,              -- JSON array of entry ids / features
    acquisition  TEXT
);

-- Penalty components. A missing component is a row with status not-installed,
-- never a zero amount.
CREATE TABLE penalty_components (
    component_id     TEXT PRIMARY KEY,
    offence_entry_id TEXT,
    jurisdiction     TEXT NOT NULL,
    component        TEXT NOT NULL,  -- set-fine | victim-fine-surcharge | court-costs | other-charge | demerit-points | statutory-range | administrative-penalty
    amount_cents     INTEGER,        -- NULL unless status = verified-extraction
    points           INTEGER,
    range_min_cents  INTEGER,
    range_max_cents  INTEGER,
    status           TEXT NOT NULL,  -- verified-extraction | not-installed | not-verified | not-applicable
    provision_id     TEXT,
    excerpt          TEXT,
    effective_from   TEXT,
    effective_to     TEXT,
    date_trigger     TEXT,           -- offence-date | conviction-date | other (as stated by the rule)
    conditions_json  TEXT,
    notes            TEXT
);

CREATE TABLE review_records (
    record_id     TEXT PRIMARY KEY,
    entry_id      TEXT NOT NULL,
    entry_version TEXT NOT NULL,
    reviewer      TEXT NOT NULL,
    qualification TEXT NOT NULL,
    scope         TEXT NOT NULL,
    decision      TEXT NOT NULL,     -- approved | changes-required | rejected
    reviewed_on   TEXT NOT NULL,
    notes         TEXT
);
