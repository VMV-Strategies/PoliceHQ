#!/usr/bin/env bash
# Checks that run without Xcode: Python tests, schema copy in sync, JSON validity.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cmp "$ROOT/schema/content_schema.sql" "$ROOT/Packages/PoliceHQCore/Sources/PoliceHQCore/Resources/content_schema.sql" \
  || { echo "schema copy out of sync"; exit 1; }
for f in "$ROOT"/content/*.json "$ROOT"/content/guides/*.json "$ROOT"/App/Resources/TrainingScenarios.json; do
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" || { echo "invalid JSON: $f"; exit 1; }
done
(cd "$ROOT/tools" && python3 -m pytest -q)
echo "OK"
