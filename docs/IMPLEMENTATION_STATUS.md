# Implementation status (2026-11-01)

These are the legend values used in the tables:

- **Implemented:** the code exists.
- **Tested:** automated tests ran and passed.
- **Untested:** written, but not compiled or run in this environment.
- **Unsupported:** deliberately not provided.
- **Awaiting source material:** the feature works, but the content it needs isn't installed.
- **Awaiting legal review:** drafted, but not reviewed.

Important: **all Swift code (app and core) is untested**. There was no Xcode or Swift toolchain, so it was syntax-checked only, at parser level. The Python tools are tested.

## Development-side tools (Python)

| Feature | Status |
|---|---|
| Inventory: hashes, duplicates, bilingual detection, banners, low-text pages | Implemented · Tested (run on all 219 uploads) |
| DOC → DOCX conversion (LibreOffice) | Implemented · Tested (33 files) |
| Federal Justice Laws extraction (English column, regions, hierarchy, marginal notes, not-in-force) | Implemented · Tested (unit tests and a full run) |
| Ontario e-Laws extraction (styles, not-yet-in-force `Y` styles, notes, history, closing words) | Implemented · Tested |
| Municipal extraction (page text, heuristic sections, OCR) | Implemented · Tested by full run. Structure accuracy is heuristic: **awaiting human verification** |
| Source registry, curated overrides, relationships | Implemented · Tested by full run |
| Quality assessment, `trusted_for_guidance` | Implemented · Tested |
| SQLite and FTS5 database build | Implemented · Tested |
| Guide compiler (citation, quote and review enforcement) | Implemented · Tested |
| Coverage report | Implemented · Tested (`docs/COVERAGE_REPORT.md`) |
| Package build, sign, verify (Ed25519, SHA-256, raw DEFLATE) | Implemented · Tested |
| Official-source update checker | Implemented · Runs, but every check was *Not verified* because outbound access was restricted here |

## iOS app and core (Swift)

| Feature | Status |
|---|---|
| Four tabs (Situation · Guides · Search · Saved), home shortcuts (Statutes · Authorities · Rights · Cautions), the required opening text | Implemented · Untested |
| Statute browser: level and municipal filters, find by title, abbreviation, citation or by-law number | Implemented · Untested |
| Document reader: contents, jump to section, **Search this document** with match navigation, highlights, bookmarks, original via QuickLook, currency, version and reproduction notices | Implemented · Untested |
| Search all sources (keywords, exact phrase, section number; level and municipality filters; not-in-force excluded by default); saved searches | Implemented · Untested (core logic covered by Swift tests that have not been run) |
| Authorities hub (6 categories, 10-part cards, statutory, common-law, judicial and consent pathways labelled) | Implemented · Untested |
| Rights hub by stage; rights timeline in situations | Implemented · Untested |
| Cautions library ("Approved wording not installed.", communication records) | Implemented · Untested · **Awaiting source material** (approved wording) |
| Situation workflow: provenance categories, clarification first, original narrative plus corrections, elements matrix, evidence, checklists, hypotheses, questions, training mode | Implemented · Untested |
| Penalties and points panel | Implemented · Untested · **Awaiting source material** (set fines, Ontario surcharge, costs, demerit points) |
| Explanation levels (4), with invariant legal content | Implemented · Untested · Summaries **awaiting legal review** |
| Version selection by incident date | Implemented · Untested · **Awaiting source material** (historical versions) |
| Content status screen, import from Files, user-initiated download, rollback | Implemented · Untested |
| Encrypted scenario storage, retention, export and import, erase, app-switcher shield, backup exclusion | Implemented · Untested |
| On-device model (Apple Foundation Models) with validation and fallback | Implemented · Untested · requires iOS 26 and Apple Intelligence |
| XcodeGen project, CI workflow | Implemented · Untested (not pushed or run) |

## Legal content

| Item | Status |
|---|---|
| 23 authority cards, 14 rights, 6 cautions, 9 offence guides, 6 checklists | Drafted · **Awaiting legal review** |
| Common-law powers (investigative detention, search incident to arrest, protective search, consent) | **Awaiting source material** (case law). Cards state the gap and give no test |
| Approved caution wording | **Awaiting source material** |
| Ontario set fines, victim fine surcharge, costs, demerit points | **Awaiting source material** |
| Statutory fine and range data (HTA ss. 128(14) and 216(2), TPA s. 2(1), CAIA s. 2(3), Criminal Code ss. 266, 334 and 737(2)) | Implemented from installed text · **Awaiting legal review** |
| Municipal penalty schedules, Brampton parking administrative-penalty schedule | **Awaiting source material and verification** |
| Historical point-in-time versions | **Awaiting source material** |
| Official-source verification of every source | Not performed |

## Unsupported (deliberately excluded)

- biometric identification
- predictive policing
- demographic risk scoring
- automated credibility scoring
- operational tactics
- CPIC or RMS integration
- cloud inference
- analytics and remote crash reporting
- guilt percentages, charge rankings and legal-assurance scores
- GPS-based jurisdiction
