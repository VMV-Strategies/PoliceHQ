# Architecture

The app is built in five layers. Every legal proposition the app shows traces back to an installed provision.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ SwiftUI app (App/)  Situation · Guides · Search · Saved; Statutes · Authorities │
│                     · Rights · Cautions; Content status; Settings             │
├──────────────────────────────────────────────────────────────────────────────┤
│ 4  Optional on-device model (Intelligence/)                                   │
│    LocalAssistant protocol → FoundationModelsAssistant | UnavailableAssistant │
│    Fact proposals need confirmation · CitationValidator · no cloud path        │
├──────────────────────────────────────────────────────────────────────────────┤
│ 3  Explicit, testable rules (Analysis/, Penalties/)                           │
│    ScenarioAnalyzer · ExplanationRenderer · CautionPresentation ·             │
│    DeadlineCalculator · PenaltyCalculator · SurchargeRule · VersionSelector · │
│    MunicipalApplicability                                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│ 2  Local retrieval (Content/)  SQLite FTS5 over provisions and pages;          │
│    document-scoped vs all-source scope; section jumps; definitions            │
├──────────────────────────────────────────────────────────────────────────────┤
│ 1  Local content (installed package)  content.sqlite + originals/ +           │
│    manifest.json (Ed25519-signed) — Packages/ContentInstaller (atomic, rollback)│
├──────────────────────────────────────────────────────────────────────────────┤
│ 5  Protected scenario storage (Scenarios/)  AES-GCM per file, Keychain key     │
│    (this device only), NSFileProtectionComplete, export/import with provenance│
└──────────────────────────────────────────────────────────────────────────────┘
```

## Content model

Content is stored in `schema/content_schema.sql`.

### Sources

The `sources` table holds one row per distinct document, with these fields:

- **Identity:** stable `source_id`, title and citation, each with the basis it was established on, and abbreviations.
- **Classification:** document type, legislative level, jurisdiction label, municipality, issuing authority, territorial application and enforcement responsibility. These are separate fields.
- **Provenance:** official URL and its status, original filename, SHA-256, path to the original in the package.
- **Dates:** consolidation, last amendment, retrieval, verification.
- **Status:** publisher status (publisher-issued or reference conversion), extraction method and quality, editorial review status, and `trusted_for_guidance`.

### Provisions

`provisions` holds the hierarchy Part → section → subsection → paragraph → subparagraph → clause. Each row carries:

- the verbatim extracted text and the marginal note or headnote
- the amendment history
- a status (`in-force`, `not-yet-in-force`, `repealed` or `annotation`)
- page numbers and document order

Text that is not yet in force has its own `provision_id` (with a `@not-yet-in-force` suffix) and is never merged into operative text.

### Other tables

- **`pages`:** page-level text for PDFs (English column only for bilingual PDFs), with OCR and image-only flags.
- **`definitions`**, **`source_relationships`**, and the FTS5 indexes `provisions_fts` and `pages_fts`.
- **`guide_entries` and `guide_citations`:** curated authorities, rights, cautions, offences and checklists. Each citation stores the verbatim installed text it points to, checked at build time.
- **`penalty_components`:** set fine, victim fine surcharge, costs, other charges, demerit points, statutory ranges and administrative penalties. Each row has a status and links to its source.
- **`coverage_gaps`** and **`review_records`**.

## Jurisdiction rules

- **The Constitution has its own level (`constitutional`).** It is not filed as an ordinary federal statute.
- **Level, territory and enforcement are separate fields.** The app never applies a rule that federal law displaces provincial or municipal law.
- **City selection is manual** (Brampton or Mississauga). `MunicipalApplicability` never applies one city's by-laws to the other. Peel Region by-laws are shown as regional material whose own terms define where they apply, and the app does not determine road ownership.
- **Offences and powers are separate.** Authority cards come only from curated authority entries, filtered by encounter stage, never from an offence.

## Versions and currency

`VersionSelector` compares the incident date with dates printed in the source: "Current to", "Last amended on" and the e-Laws "Consolidation Period". It reports one of:

- the installed version covers the incident date
- the historical version is not installed
- the incident is after the installed text's currency date
- unknown

The import date is never treated as a currency date. Each analysis records a `ContentProvenance`: the package version and the source and guide versions it used. Installing a later package never rewrites that record. Reassessment against a new package is an explicit user action.

## Guided analysis

`ScenarioAnalyzer` is deterministic. It works as follows:

- **Clarification comes first:** incident date, city, stage, youth, and where each fact came from.
- **Candidate offences** come from user selections and curated keywords. The app labels this as keyword matching, not legal reasoning.
- **The elements matrix** links the user's facts to elements. **Statuses are set by the user only**, and default to *unknown*.
- **Findings use fixed wording:** insufficient information, element unsupported, conflicting information, relevant source not installed, no applicable authority identified (never stated as proof that none exists), legal review required, and version warnings.
- **No automatic completion:** checklists never complete themselves, and `DeadlineCalculator` returns *not calculated* unless an approved, validated rule exists.

## Explanation levels

There are four levels: Very simple, Plain language, Detailed and Legal analysis. `ExplanationRenderer` keeps `InvariantContent` identical at every level: quotes, conditions, limits, citations, gaps and review status. Only the drafted summary changes, and it is labelled. Where no summary exists, the supported wording is shown instead. `CautionPresentation` ignores the level entirely, and shows *Approved wording not installed.* unless reviewed wording with an approving organization exists.

## Penalties

`PenaltyCalculator` keeps these separate:

- set fines, victim fine surcharge, court costs and other charges
- demerit points
- statutory fines and ranges on conviction
- administrative penalties

The rules it follows:

- **Missing values:** a missing value is *Not installed*, *Not verified* or *Not applicable*, never zero.
- **Totals:** a total appears only when every component is verified. Otherwise the panel shows *Total cannot be verified.* and lists what is missing.
- **Statutory amounts:** statutory amounts (for example HTA s. 128(14) per-km/h fines) are calculated only from installed text. They are never added to a ticket total and never shown as a ticket amount.
- **Dates:** components carry their own effective dates and are selected by date. Nothing falls back to the latest rule.
- **Points:** a verified zero points is distinct from unknown.

## Packages

`.phqpkg` is a simple container: a magic number, a JSON index, then file payloads (raw DEFLATE or stored). `manifest.json` lists every file's size and SHA-256, and `manifest.sig` is an Ed25519 signature over the exact manifest bytes.

`ContentPackageReader` verifies in this order:

1. signature
2. format and schema compatibility, and the minimum app version
3. no unlisted files and no unsafe paths
4. every hash

Files are written only after every check passes. `ContentInstaller` then extracts to `staging-*`, smoke-tests the database, and swaps `current` to `previous` and `staging` to `current`. Rollback swaps them back, and a failed install leaves `current` untouched. A valid signature shows origin and integrity only, not legal correctness.

## On-device model

The model sits behind the `LocalAssistant` protocol:

- **`FoundationModelsAssistant`** is compiled only when the FoundationModels framework exists, and is available only on iOS 26 or later with Apple Intelligence.
- **Fact proposals** are kept as `ProposedFact` until the user confirms each one, choosing its provenance. `ProposalValidator` drops proposals that aren't traceable to the narrative.
- **Explanations:** the model receives fenced passages and instructions to treat them as data. `CitationValidator` rejects output that cites a provision outside the retrieved set, or mentions section numbers that weren't retrieved.
- **Clarification questions:** `LeadingQuestionFilter` drops leading questions.
- **Fallback:** `UnavailableAssistant` is the explicit fallback, and every core workflow works without the model.
