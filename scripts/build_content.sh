#!/usr/bin/env bash
# Build a signed Police HQ content package from local uploads.
#   scripts/build_content.sh <uploads-dir> <signing-key> <key-id> <package-version>
# Example:
#   scripts/build_content.sh ~/phq-uploads ~/phq-keys/signing.key my-service-2026 2026.11.01
# Uploaded documents, intermediate files and packages stay outside the repository (build/, dist/).
set -euo pipefail
UPLOADS="${1:?uploads dir}"; KEY="${2:?signing key}"; KEY_ID="${3:?key id}"; VERSION="${4:?package version}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build"
mkdir -p "$WORK/converted" "$WORK/cache" "$ROOT/dist"
echo "1/6 Converting legacy Word files (DOC -> DOCX) with LibreOffice"
shopt -s nullglob
docs=("$UPLOADS"/*.doc)
if [ ${#docs[@]} -gt 0 ]; then soffice --headless --convert-to docx --outdir "$WORK/converted" "${docs[@]}" >/dev/null; fi
cd "$ROOT/tools"
echo "2/6 Inventory"
python3 -m phq_ingest.inventory --uploads "$UPLOADS" --converted "$WORK/converted" --out "$WORK/inventory.json"
echo "3/6 Registry (metadata only; review content/source_registry.json changes before committing)"
python3 -m phq_ingest.registry_seed --inventory "$WORK/inventory.json" --registry "$ROOT/content/source_registry.json" --overrides "$ROOT/content/registry_overrides.json"
echo "4/6 Extraction, indexing, guide compilation"
python3 -m phq_ingest.build_db --registry "$ROOT/content/source_registry.json" --inventory "$WORK/inventory.json" \
  --schema "$ROOT/schema/content_schema.sql" --guides "$ROOT/content/guides" --penalties "$ROOT/content/penalties.json" \
  --gaps "$ROOT/content/coverage_gaps.json" --out "$WORK/package" --cache "$WORK/cache" --converted "$WORK/converted" \
  --package-version "$VERSION"
echo "5/6 Coverage report"
python3 -m phq_ingest.coverage --db "$WORK/package/content.sqlite" --registry "$ROOT/content/source_registry.json" \
  --out-json "$WORK/coverage_report.json" --out-md "$ROOT/docs/COVERAGE_REPORT.md"
echo "6/6 Signing and verifying"
python3 -m phq_ingest.package build --src "$WORK/package" --key "$KEY" --key-id "$KEY_ID" --version "$VERSION" \
  --out "$ROOT/dist/PoliceHQ-content-$VERSION.phqpkg"
python3 -m phq_ingest.package verify --pkg "$ROOT/dist/PoliceHQ-content-$VERSION.phqpkg" --public "$ROOT"/content/trusted_keys/*.pub
