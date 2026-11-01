# Developer setup

## Swift app and core

1. **Install tools:** Xcode 26 or later, and XcodeGen (`brew install xcodegen`).
2. **Generate the project:** `xcodegen generate`. This creates `PoliceHQ.xcodeproj`, which is git-ignored; `project.yml` is the source of truth.
3. **Run the core tests:**
   - `cd Packages/PoliceHQCore && swift test` (macOS host)
   - or in Xcode, the PoliceHQ scheme › Test, which runs `PoliceHQCoreTests`
4. **Run the app:** select an iPhone simulator or a device (see [INSTALLATION.md](INSTALLATION.md)).

### Dependencies

The app has **no third-party Swift dependencies**. SQLite3, CryptoKit, CommonCrypto, QuickLook, SwiftUI and the optional FoundationModels are system frameworks, so no packages are downloaded at build time and nothing is fetched at runtime.

### Build-time and runtime downloads

| Download | Development time | Runtime |
|---|---|---|
| Xcode, XcodeGen, Python packages, poppler, LibreOffice, Tesseract | Yes | No |
| Official source documents (to build content) | Yes | No |
| Content package | Copied to the device once | Optional user-initiated update only |
| Apple on-device model | Managed by iOS (Apple Intelligence) | Runs on device; no network needed by Police HQ |

## Python tools

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r tools/requirements.txt
# system tools: poppler-utils, libreoffice, tesseract-ocr
scripts/check.sh            # schema sync, JSON validity, Python tests
```

To run the integration tests against a built database:

```bash
PHQ_CONTENT_DB=build/package/content.sqlite python3 -m pytest -q   # run inside tools/
```

## Keeping the schema in sync

`schema/content_schema.sql` is copied into `Packages/PoliceHQCore/Sources/PoliceHQCore/Resources/`. `scripts/check.sh` fails if the two copies differ. Bump `SCHEMA_VERSION` (Python), `ContentSchema.version` and `ContentPackageReader.supportedSchemaVersion` (Swift) together.

## CI

`.github/workflows/ci.yml` runs two jobs:

- **Ubuntu:** the Python checks.
- **macOS:** `swift test`, the iOS Simulator core tests, `xcodegen generate` and an unsigned app build.

Adjust the runner label (`macos-26`), the Xcode path and the simulator name to whatever your GitHub plan provides. CI hasn't run yet, because the repository hasn't been pushed.
