"""Compile curated guide content into the content database.

Every citation in a guide must resolve to an installed, in-force provision and
every quoted threshold or "excerpt_contains" string must appear verbatim in that
provision's installed text. Any unresolved citation fails the build: guides can
never cite material that is not installed.
"""
from __future__ import annotations

import json
import re
import sqlite3
from pathlib import Path

from .util import read_json

ALLOWED_REVIEW = {"interpretation-drafted", "legal-review-recorded", "approved"}


class GuideError(Exception):
    pass


def _norm(s: str) -> str:
    return re.sub(r"\s+", " ", s.replace(" ", " ")).strip()


def subtree_text(con: sqlite3.Connection, provision_id: str) -> str:
    row = con.execute("SELECT source_id, path, ordinal, label, heading, text, status FROM provisions WHERE provision_id=?",
                      (provision_id,)).fetchone()
    if row is None:
        raise GuideError(f"provision not installed: {provision_id}")
    sid, path, ordinal, label, heading, text, status = row
    parts = [f"{label}" + (f" — {heading}" if heading else "") + (f": {text}" if text else "")]
    # descendants: same source, path prefix, contiguous ordinals after this one
    for clabel, cheading, ctext, cpath, cstatus in con.execute(
            "SELECT label, heading, text, path, status FROM provisions WHERE source_id=? AND ordinal>? "
            "ORDER BY ordinal", (sid, ordinal)):
        if not (cpath.startswith(path + "(") or cpath.startswith(path + "[")):
            if cpath.startswith("heading:") or cpath.startswith("note:"):
                continue
            break
        if cstatus != status:
            continue
        parts.append(f"{clabel}" + (f" — {cheading}" if cheading else "") + (f": {ctext}" if ctext else ""))
    return "\n".join(parts)


REVIEW_FIELDS = ("record_id", "entry_id", "entry_version", "reviewer", "qualification", "scope", "decision", "reviewed_on")


def load_reviews(con: sqlite3.Connection, reviews_dir: Path | None) -> int:
    """Loads qualified-review records (content/reviews/*.json). Records are written by people,
    never generated; each names the reviewer, qualification, scope, decision and date, and
    applies only to the exact guide version reviewed."""
    if not reviews_dir or not reviews_dir.exists():
        return 0
    n = 0
    for f in sorted(reviews_dir.glob("*.json")):
        for r in read_json(f).get("records", []):
            missing = [k for k in REVIEW_FIELDS if not str(r.get(k, "")).strip()]
            if missing:
                raise GuideError(f"review record in {f.name} missing {missing}")
            if r["decision"] not in ("approved", "changes-required", "rejected"):
                raise GuideError(f"review record {r['record_id']}: invalid decision")
            con.execute("INSERT INTO review_records VALUES (?,?,?,?,?,?,?,?,?)",
                        tuple(r.get(k) for k in REVIEW_FIELDS) + (r.get("notes"),))
            n += 1
    return n


def compile_guides(con: sqlite3.Connection, guides_dir: Path | None, penalties: Path | None, gaps: Path | None,
                   reviews_dir: Path | None = None) -> dict:
    errors: list[str] = []
    n_reviews = load_reviews(con, reviews_dir)
    gap_ids: set[str] = set()
    if gaps and gaps.exists():
        for g in read_json(gaps)["gaps"]:
            con.execute("INSERT INTO coverage_gaps VALUES (?,?,?,?,?,?)",
                        (g["gap_id"], g["category"], g["title"], g["description"],
                         json.dumps(g.get("affects", [])), g.get("acquisition")))
            gap_ids.add(g["gap_id"])
    n_entries = n_cites = 0
    entry_ids: set[str] = set()
    files = sorted(guides_dir.glob("*.json")) if guides_dir and guides_dir.exists() else []
    all_entries = []
    for f in files:
        for e in read_json(f)["entries"]:
            all_entries.append((f.name, e))
            entry_ids.add(e["entry_id"])
    for fname, e in all_entries:
        eid = e["entry_id"]
        if e.get("review_status") not in ALLOWED_REVIEW:
            errors.append(f"{eid}: invalid review_status {e.get('review_status')}")
        if e.get("review_status") in ("legal-review-recorded", "approved"):
            rec = con.execute("SELECT 1 FROM review_records WHERE entry_id=? AND entry_version=? AND decision='approved'",
                              (eid, e["version"])).fetchone()
            if rec is None:
                errors.append(f"{eid}: claims {e['review_status']} but no review record exists")
        body = e.get("body", {})
        for g in body.get("gaps", []):
            if g not in gap_ids:
                errors.append(f"{eid}: unknown gap {g}")
        for key in ("linked_rights", "linked_cautions", "linked_authorities", "linked_checklists"):
            for ref in body.get(key, []):
                if ref not in entry_ids:
                    errors.append(f"{eid}: {key} references unknown entry {ref}")
        con.execute("INSERT INTO guide_entries VALUES (?,?,?,?,?,?,?)",
                    (eid, e["kind"], e.get("category"), e["title"], e["review_status"], e["version"],
                     json.dumps(body, ensure_ascii=False)))
        n_entries += 1
        excerpts = []
        for i, c in enumerate(e.get("citations", [])):
            pid = f"{c['source_id']}:{c['path']}"
            row = con.execute("SELECT status FROM provisions WHERE provision_id=?", (pid,)).fetchone()
            if row is None:
                errors.append(f"{eid}: citation {i} not installed: {pid}")
                excerpts.append("")
                continue
            if row[0] != "in-force":
                errors.append(f"{eid}: citation {i} is not an in-force provision ({row[0]}): {pid}")
            try:
                ex = subtree_text(con, pid)
            except GuideError as exc:
                errors.append(f"{eid}: {exc}")
                excerpts.append("")
                continue
            for needle in ([c["excerpt_contains"]] if isinstance(c.get("excerpt_contains"), str) else c.get("excerpt_contains", [])):
                if _norm(needle) not in _norm(ex):
                    errors.append(f"{eid}: citation {i} ({pid}) does not contain: {needle!r}")
            excerpts.append(ex)
            con.execute("INSERT INTO guide_citations VALUES (?,?,?,?,?,?)",
                        (eid, c.get("role", "related"), c["source_id"], pid, c.get("pinpoint") or c["path"], ex))
            n_cites += 1
        # verbatim threshold / quote checks
        for q in body.get("quotes", []):
            idx = q["citation"]
            if idx >= len(excerpts) or _norm(q["text"]) not in _norm(excerpts[idx]):
                errors.append(f"{eid}: quote not found verbatim in citation {idx}: {q['text'][:60]!r}")
        for listname in ("elements", "defences", "items"):
            for item in body.get(listname, []):
                if item.get("general"):
                    if "citation" in item:
                        errors.append(f"{eid}: general {listname} item must not carry a citation")
                    if not item.get("basis"):
                        errors.append(f"{eid}: general {listname} item must state its basis")
                    continue
                idx = item.get("citation")
                quote = item.get("quote")
                if idx is None or quote is None:
                    errors.append(f"{eid}: {listname} item {item.get('id', item.get('text', '?'))!r} lacks citation/quote")
                    continue
                if idx >= len(excerpts) or _norm(quote) not in _norm(excerpts[idx]):
                    errors.append(f"{eid}: {listname} quote not verbatim in citation {idx}: {quote[:60]!r}")
    n_pen = 0
    if penalties and penalties.exists():
        for comp in read_json(penalties)["components"]:
            pid = None
            excerpt = None
            if comp.get("path"):
                pid = f"{comp['source_id']}:{comp['path']}"
                row = con.execute("SELECT text, status FROM provisions WHERE provision_id=?", (pid,)).fetchone()
                if row is None:
                    errors.append(f"penalty {comp['component_id']}: provision not installed {pid}")
                else:
                    excerpt = subtree_text(con, pid)
                    for needle in comp.get("verify_text", []):
                        if _norm(needle) not in _norm(excerpt):
                            errors.append(f"penalty {comp['component_id']}: {needle!r} not in {pid}")
            if comp["status"] == "verified-extraction" and not pid:
                errors.append(f"penalty {comp['component_id']}: verified amount without installed source")
            if comp["status"] != "verified-extraction" and (comp.get("amount_cents") is not None or comp.get("points") is not None):
                errors.append(f"penalty {comp['component_id']}: amount/points supplied for non-verified component")
            if comp.get("offence_entry_id") and comp["offence_entry_id"] not in entry_ids:
                errors.append(f"penalty {comp['component_id']}: unknown offence entry {comp['offence_entry_id']}")
            con.execute("INSERT INTO penalty_components VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                        (comp["component_id"], comp.get("offence_entry_id"), comp["jurisdiction"], comp["component"],
                         comp.get("amount_cents"), comp.get("points"), comp.get("range_min_cents"),
                         comp.get("range_max_cents"), comp["status"], pid, excerpt, comp.get("effective_from"),
                         comp.get("effective_to"), comp.get("date_trigger"),
                         json.dumps(comp.get("conditions", {}), ensure_ascii=False), comp.get("notes")))
            n_pen += 1
    if errors:
        raise GuideError("Guide compilation failed:\n  " + "\n  ".join(errors))
    return {"entries": n_entries, "citations": n_cites, "penalty_components": n_pen, "gaps": len(gap_ids),
            "review_records": n_reviews}
