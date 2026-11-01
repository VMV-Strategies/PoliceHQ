"""Build the offline content database from the source registry and uploads.

    python -m phq_ingest.build_db \
        --registry content/source_registry.json \
        --inventory build/inventory.json \
        --schema schema/content_schema.sql \
        --guides content/guides \
        --out build/package

Produces build/package/content.sqlite and build/package/originals/*, plus
build/package/build_report.json. Original uploads are copied byte-for-byte
(hash-checked) and never modified.
"""
from __future__ import annotations

import argparse
import json
import shutil
import sqlite3
from dataclasses import asdict
from datetime import datetime, timezone
from pathlib import Path

from . import PIPELINE_VERSION, SCHEMA_VERSION
from . import extract_federal, extract_municipal, extract_ontario
from .guides import compile_guides
from .quality import assess
from .structure import Provision
from .util import read_json, sha256_file, write_json


def _publisher_family(rec: dict) -> str:
    ps = rec.get("publisher_status", "")
    if ps.startswith("publisher-issued (Justice Laws"):
        return "justice-laws"
    if ps.startswith("publisher-issued (Ontario e-Laws"):
        return "e-laws"
    return "municipal"


def _extract(rec: dict, upload: Path, inv_item: dict, cache_dir: Path, converted_dir: Path) -> dict:
    cache = cache_dir / f"{rec['sha256']}.json"
    if cache.exists():
        return read_json(cache)
    fam = _publisher_family(rec)
    pages = inv_item.get("pages") or 0
    page_records: list[dict] = []
    meta: dict = {}
    if fam == "justice-laws":
        provs, page_records, issues = extract_federal.extract(upload, rec["source_id"], pages,
                                                              constitution=rec["level"] == "constitutional")
        method = ("pdftotext (poppler) English left-column crop; header/footer removal; dehyphenation using "
                  "document vocabulary; heuristic Justice Laws structure parser")
    elif fam == "e-laws":
        docx = converted_dir / (upload.stem + ".docx")
        provs, meta, issues = extract_ontario.extract(docx, rec["source_id"])
        method = "LibreOffice DOC->DOCX conversion on development computer; e-Laws paragraph-style structure parser"
    else:
        provs, page_records, issues = extract_municipal.extract(upload, rec["source_id"], pages, ocr=True)
        method = ("pdftotext (poppler) page text; running header/footer removal; heuristic numbered-section parser; "
                  "Tesseract OCR for image-only pages")
    data = {
        "method": method,
        "provisions": [asdict(p) for p in provs],
        "pages": page_records,
        "issues": issues,
        "meta": meta,
    }
    write_json(cache, data)
    return data


def _depth(path: str) -> int:
    return path.count("(") + path.count("[")


def build(registry: Path, inventory: Path, schema: Path, guides_dir: Path, out: Path, cache_dir: Path,
          converted_dir: Path, package_version: str, coverage_gaps: Path | None, penalties: Path | None) -> dict:
    reg = read_json(registry)
    inv = read_json(inventory)
    inv_by_hash: dict[str, dict] = {}
    for it in inv["items"]:
        inv_by_hash.setdefault(it["sha256"], it)
    out.mkdir(parents=True, exist_ok=True)
    (out / "originals").mkdir(exist_ok=True)
    db_path = out / "content.sqlite"
    if db_path.exists():
        db_path.unlink()
    con = sqlite3.connect(db_path)
    con.executescript(schema.read_text(encoding="utf-8"))
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    report: dict = {"sources": {}, "generated_at": now}

    for sid, rec in sorted(reg["sources"].items()):
        it = inv_by_hash.get(rec["sha256"])
        if it is None:
            report["sources"][sid] = {"status": "missing-upload"}
            continue
        upload = Path(it["upload_path"])
        if sha256_file(upload) != rec["sha256"]:
            raise SystemExit(f"hash mismatch for {upload}")
        data = _extract(rec, upload, it, cache_dir, converted_dir)
        provs = [Provision(**{k: v for k, v in p.items() if k != "lines"}) for p in data["provisions"]]
        q = assess(rec, it, provs, data["pages"], data["issues"])
        # copy original byte-for-byte
        ext = upload.suffix.lower()
        orig_rel = f"originals/{sid}{ext}"
        dest = out / orig_rel
        shutil.copyfile(upload, dest)
        if sha256_file(dest) != rec["sha256"]:
            raise SystemExit(f"copy hash mismatch for {dest}")
        meta = data.get("meta") or {}
        consolidation = rec.get("consolidation_current_to") or rec.get("consolidation_period") or meta.get("consolidation_period") \
            or rec.get("consolidation_note") or ("Reference conversion retrieved " + rec["reference_conversion_retrieved"]
                                                 if rec.get("reference_conversion_retrieved") else "Unknown")
        if rec.get("consolidation_current_to"):
            consolidation = "Current to " + rec["consolidation_current_to"]
        con.execute(
            """INSERT INTO sources VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (sid, rec["title"], rec.get("title_basis"), rec.get("citation"), rec.get("citation_basis"),
             json.dumps(rec.get("abbreviations", []), ensure_ascii=False), rec["doc_type"], rec["level"],
             rec["jurisdiction_label"], rec.get("municipality") if rec.get("municipality") not in (None, "Unknown") else None,
             rec.get("municipality_basis"), rec.get("issuing_authority"), rec.get("territorial_application"),
             rec.get("enforcement_responsibility"), rec.get("official_url"), rec.get("official_url_status", "Not verified"),
             rec["original_filename"], rec["sha256"], orig_rel, rec["format"], it.get("pages"), consolidation,
             rec.get("last_amended"), rec.get("effective_note"), rec.get("retrieval_date"), rec.get("verification_date"),
             rec.get("verification_status", "Not verified"), rec["publisher_status"], data["method"], q["quality"],
             q["notes"], rec.get("editorial_review_status", "imported"), 1 if q["trusted"] else 0,
             rec.get("language_handling"), json.dumps(rec, ensure_ascii=False)))
        rows = []
        known_paths: dict[str, str] = {}
        all_ids = {p.provision_id for p in provs}
        for p in provs:
            known_paths.setdefault(p.path, p.provision_id)
        for p in provs:
            parent_id = None
            if p.parent_path:
                parent_id = known_paths.get(p.parent_path)
                if p.status not in ("in-force", "repealed", "unknown"):
                    cand = f"{sid}:{p.parent_path}@{p.status}"
                    if cand in all_ids:
                        parent_id = cand
            rows.append((p.provision_id, sid, parent_id, p.kind, p.number, p.path, p.label, p.heading, p.text, p.status,
                         p.history, json.dumps(p.notes, ensure_ascii=False) if p.notes else None, p.page_start, p.page_end,
                         p.ordinal, _depth(p.path)))
        con.executemany("INSERT OR REPLACE INTO provisions VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", rows)
        for p in provs:
            if p.kind == "definition" and p.status == "in-force":
                con.execute("INSERT INTO definitions VALUES (?,?,?)", (sid, p.heading or p.number, p.provision_id))
        for pr in data["pages"]:
            con.execute("INSERT INTO pages VALUES (?,?,?,?,?,?)",
                        (sid, pr["page"], pr.get("region"), pr.get("text"), 1 if pr.get("ocr") else 0,
                         1 if pr.get("image_only") else 0))
        report["sources"][sid] = {"provisions": len(provs), "pages": len(data["pages"]), **q}

    for sid, rec in reg["sources"].items():
        for rel in rec.get("relationships", []):
            con.execute("INSERT INTO source_relationships VALUES (?,?,?,?,?)",
                        (sid, rel["relation"], rel["target"], rel.get("basis"), 1 if rel.get("verified") else 0))
    con.execute("INSERT INTO provisions_fts(provisions_fts) VALUES ('rebuild')")
    con.execute("INSERT INTO pages_fts(pages_fts) VALUES ('rebuild')")

    reviews_dir = guides_dir.parent / "reviews" if guides_dir else None
    guide_report = compile_guides(con, guides_dir, penalties, coverage_gaps, reviews_dir)
    report["guides"] = guide_report

    info = {
        "schema_version": str(SCHEMA_VERSION),
        "pipeline_version": PIPELINE_VERSION,
        "package_version": package_version,
        "package_published_at": now,
        "import_date": now[:10],
        "source_count": str(len(reg["sources"])),
        "language": "en",
        "notice": ("Imported date is not a statement that the law is current. Each source shows its own "
                   "consolidation date and verification status."),
    }
    con.executemany("INSERT INTO package_info VALUES (?,?)", list(info.items()))
    con.commit()
    con.execute("VACUUM")
    con.close()
    report["package_info"] = info
    write_json(out / "build_report.json", report)
    return report


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--registry", type=Path, required=True)
    ap.add_argument("--inventory", type=Path, required=True)
    ap.add_argument("--schema", type=Path, required=True)
    ap.add_argument("--guides", type=Path, required=True)
    ap.add_argument("--penalties", type=Path, default=None)
    ap.add_argument("--gaps", type=Path, default=None)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--cache", type=Path, required=True)
    ap.add_argument("--converted", type=Path, required=True)
    ap.add_argument("--package-version", required=True)
    a = ap.parse_args()
    a.cache.mkdir(parents=True, exist_ok=True)
    rep = build(a.registry, a.inventory, a.schema, a.guides, a.out, a.cache, a.converted, a.package_version, a.gaps,
                a.penalties)
    n = len(rep["sources"])
    print(f"built {n} sources; guides: {rep['guides']['entries']} entries, {rep['guides']['citations']} citations")


if __name__ == "__main__":
    main()
