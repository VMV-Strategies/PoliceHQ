# Police HQ

Police HQ is a native iPhone app (Swift and SwiftUI) for **offline Canadian police legal reference**, structured scenario analysis and investigation checklists. It covers federal law, Ontario law, and by-laws for Peel Region, Brampton and Mississauga.

It supports human judgment. It does **not** determine guilt, direct that charges be laid, create grounds or guarantee legal compliance. Its core behaviour is:

> Here are potentially relevant provisions, their requirements, the information you supplied, what remains unresolved and the sources to review.

> **Status:** development build. No guide, rule or explanation has had a qualified legal review. The Swift code has **not yet been compiled or run**: the environment it was written in had no Xcode or Swift toolchain. The Python tools and tests were run. See [docs/IMPLEMENTATION_STATUS.md](docs/IMPLEMENTATION_STATUS.md) and [docs/TESTING.md](docs/TESTING.md).

## What is in this repository

| Path | Contents |
|---|---|
| `App/` | SwiftUI iPhone app: four tabs (Situation · Guides · Search · Saved) and home shortcuts (Statutes · Authorities · Rights · Cautions) |
| `Packages/PoliceHQCore/` | Swift package with the core logic and XCTest suite: SQLite/FTS5 content store, search, jurisdiction and version logic, scenario model, analyzer, penalties, package verification and installation, encrypted storage, and the on-device model interface |
| `tools/phq_ingest/` | Development-side Python tools: inventory, DOC/PDF extraction, OCR, structure parsing, registry, quality checks, database build, guide compilation, coverage report, signing and verification, official-source update checks |
| `schema/content_schema.sql` | The content database schema (single source of truth) |
| `content/` | Curated metadata and editorial drafts, with no legal text: source registry, overrides, coverage gaps, guides, penalty components, review records, trusted public keys |
| `docs/` | Setup, architecture, ingestion, legal review, updates, privacy, testing, installation, device checklist, implementation status, coverage report, redistribution |
| `project.yml` | XcodeGen project definition (run `xcodegen generate` to create the Xcode project) |
| `.github/workflows/ci.yml` | CI for the Python tools on Ubuntu, and the Swift tests and app build on a macOS/Xcode runner |

**Not in this repository:**

- The uploaded legal documents.
- The built content package.
- Signing keys.

Redistribution rights for some sources (municipal by-laws) are not established. Build the package locally (see [docs/INGESTION.md](docs/INGESTION.md)) and provision it separately. See [docs/REDISTRIBUTION.md](docs/REDISTRIBUTION.md).

## Quick start

```bash
# 1. Generate and open the Xcode project (macOS, Xcode 26+)
brew install xcodegen
xcodegen generate
open PoliceHQ.xcodeproj

# 2. Run the core tests
cd Packages/PoliceHQCore && swift test

# 3. Build a content package from your own copies of the source documents
pip install -r tools/requirements.txt          # plus poppler, LibreOffice, Tesseract
python3 -m phq_ingest.package keygen --out-private ~/phq-keys/signing.key --out-public content/trusted_keys/mine.pub   # run inside tools/
scripts/build_content.sh ~/phq-uploads ~/phq-keys/signing.key my-key-2026 2026.11.01
```

Then install the app on an iPhone ([docs/INSTALLATION.md](docs/INSTALLATION.md)) and import the `.phqpkg` file through Files (Settings › Content status › Import). After that, core functions work in airplane mode.

## Offline by design

Once the app and a content package are installed, everything below runs without a network, account, server, cloud AI, subscription or remote interface assets:

- Situation entry, clarification questions and structured analysis
- Statute browsing, in-document search and full-text search
- Authorities, Rights and Cautions hubs
- Penalties panel and checklists
- Saved work, and source versions with their provenance

The app has no analytics and no remote crash reporting.

The app uses the network only when the user starts an update from an address they configured. Development, installation and package building need internet access; runtime use does not. The on-device language model (Apple Foundation Models, iOS 26 or later on Apple Intelligence devices) is optional, and the app never switches to cloud inference.
