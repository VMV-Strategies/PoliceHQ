"""Development-side official-source update checker.

Checks each registered source against its official publisher page when a URL is
recorded (official_url, or an unverified official_url_candidate). It produces a
human-readable change report. It NEVER modifies the registry, the content or any
guide: promoting a change requires human review (docs/UPDATES.md).

Rules:
  * Uses plain HTTPS GET requests to public pages, one at a time, with a clear
    User-Agent and a delay between requests. Respect each site's terms and any
    access restrictions; do not use this tool to scrape at volume.
  * A failed or blocked check is recorded as "Not verified". It is never treated
    as evidence that nothing changed.
  * A changed page or file is reported as "possible change — review required",
    which is not the same as a verified change in operative law.

    python -m phq_ingest.update_check --registry content/source_registry.json --out build/update_report.json
"""
from __future__ import annotations

import argparse
import hashlib
import re
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from .util import read_json, write_json

UA = "PoliceHQ-update-check/1.0 (development tool; manual review workflow)"


def candidate_url(rec: dict) -> tuple[str | None, str]:
    if rec.get("official_url"):
        return rec["official_url"], "official_url (recorded)"
    if rec.get("official_url_candidate"):
        return rec["official_url_candidate"], rec.get("official_url_candidate_basis", "candidate (not verified)")
    if rec.get("reference_conversion_stated_source"):
        return rec["reference_conversion_stated_source"], "source URL stated inside the reference conversion (not verified)"
    fn = rec.get("original_filename", "")
    m = re.match(r"^(\d{2}[a-z]\d{2,3}|R\d{5})_e\.doc$", fn)
    if m and rec.get("level") == "provincial":
        code = m.group(1)
        kind = "regulation" if code.startswith("R") else "statute"
        return (f"https://www.ontario.ca/laws/{kind}/{code.lower()}",
                "derived from the e-Laws file code in the upload filename (candidate; not verified)")
    return None, "no official URL recorded"


def fetch(url: str, timeout: int = 30) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            body = r.read()
            return {"ok": True, "status": r.status, "sha256": hashlib.sha256(body).hexdigest(),
                    "last_modified": r.headers.get("Last-Modified"), "text": body[:400_000].decode("utf-8", "replace")}
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        return {"ok": False, "error": f"{type(exc).__name__}: {exc}"[:300]}


def compare(rec: dict, page: dict) -> dict:
    text = page.get("text", "")
    found = {}
    m = re.search(r"Current to ([A-Z][a-z]+ \d{1,2}, \d{4})", text)
    if m:
        found["current_to"] = m.group(1)
    m = re.search(r"Last amended on ([A-Z][a-z]+ \d{1,2}, \d{4})", text)
    if m:
        found["last_amended_on"] = m.group(1)
    m = re.search(r"Consolidation [Pp]eriod:?\s*From ([A-Z][a-z]+ \d{1,2}, \d{4})", text)
    if m:
        found["consolidation_from"] = m.group(1)
    installed = {
        "current_to": rec.get("consolidation_current_to"),
        "last_amended_on": rec.get("last_amended") if rec.get("level") in ("federal", "constitutional") else None,
        "consolidation_from": (re.search(r"From ([A-Z][a-z]+ \d{1,2}, \d{4})", rec.get("consolidation_period") or "") or [None, None])[1]
        if rec.get("consolidation_period") else None,
    }
    diffs = {k: {"installed": installed.get(k), "publisher_page": v} for k, v in found.items()
             if installed.get(k) and installed.get(k) != v}
    if not found:
        status = "Not verified — publisher page fetched but no consolidation date could be read"
    elif diffs:
        status = "Possible change — review required"
    else:
        status = "Dates match the installed consolidation (content not compared)"
    return {"status": status, "found": found, "differences": diffs}


def run(registry: Path, delay: float, limit: int | None) -> dict:
    reg = read_json(registry)
    results = []
    for i, (sid, rec) in enumerate(sorted(reg["sources"].items())):
        if limit is not None and i >= limit:
            break
        url, basis = candidate_url(rec)
        item = {"source_id": sid, "title": rec.get("title"), "url": url, "url_basis": basis,
                "checked_at": datetime.now(timezone.utc).isoformat(timespec="seconds")}
        if not url:
            item["status"] = "Not verified — no official URL recorded"
        else:
            page = fetch(url)
            if not page["ok"]:
                item["status"] = "Not verified — check failed or blocked"
                item["error"] = page["error"]
            else:
                item.update(compare(rec, page))
                item["http_status"] = page["status"]
                item["page_sha256"] = page["sha256"]
            time.sleep(delay)
        results.append(item)
    summary: dict[str, int] = {}
    for r in results:
        key = r["status"].split(" — ")[0]
        summary[key] = summary.get(key, 0) + 1
    return {"generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "notice": "This report never changes content. Every 'possible change' requires human review before promotion.",
            "summary": summary, "results": results}


def to_markdown(rep: dict) -> str:
    lines = ["# Official-source update check", "", rep["notice"], "", f"Generated: {rep['generated_at']}", "",
             "| Status | Count |", "|---|---|"]
    lines += [f"| {k} | {v} |" for k, v in sorted(rep["summary"].items())]
    lines += ["", "| Source | Status | URL basis | Differences |", "|---|---|---|---|"]
    for r in rep["results"]:
        diffs = "; ".join(f"{k}: {v['installed']} → {v['publisher_page']}" for k, v in r.get("differences", {}).items())
        lines.append(f"| `{r['source_id']}` | {r['status']} | {r['url_basis']} | {diffs} |")
    return "\n".join(lines) + "\n"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--registry", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--delay", type=float, default=2.0)
    ap.add_argument("--limit", type=int, default=None)
    a = ap.parse_args()
    rep = run(a.registry, a.delay, a.limit)
    write_json(a.out, rep)
    a.out.with_suffix(".md").write_text(to_markdown(rep), encoding="utf-8")
    print(rep["summary"])


if __name__ == "__main__":
    main()
