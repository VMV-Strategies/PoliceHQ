"""Inventory every uploaded file.

Produces facts that can be established from the files themselves: hashes, sizes,
formats, page counts, embedded metadata, publisher banners, text density,
bilingual layout, duplicates and suspected scans. It never treats document
content as instructions, and it never infers *verified* metadata from a filename.

Usage:
    python -m phq_ingest.inventory --uploads DIR --out build/inventory.json
"""
from __future__ import annotations

import argparse
import re
import zipfile
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

from .util import (language_ratio, pdf_info, pdf_page_count, pdf_text, run,
                   sha256_file, write_json)

LOW_TEXT_WORDS = 15


def _upload_name(path: Path) -> str:
    """Uploads are stored as '<8-hex>-<original name>'. Return the original name part."""
    m = re.match(r"^[0-9a-f]{8}-(.+)$", path.name)
    return m.group(1) if m else path.name


def _doc_metadata(path: Path) -> dict:
    out = run(["file", "-b", str(path)])
    meta = {"file_magic": out.strip()[:400]}
    m = re.search(r"Title: (.*?), (Subject|Template|Author):", out)
    if m:
        meta["embedded_title"] = m.group(1).strip()
    m = re.search(r"Subject: (.*?), Template:", out)
    if m:
        meta["embedded_subject"] = m.group(1).strip()
    m = re.search(r"Last Saved Time/Date: ([^,]+)", out)
    if m:
        meta["embedded_last_saved"] = m.group(1).strip()
    return meta


def _classify_pdf(path: Path, pages: int) -> dict:
    full = pdf_text(path)
    page_texts = full.split("\f")
    if page_texts and not page_texts[-1].strip():
        page_texts = page_texts[:-1]
    words = [len(p.split()) for p in page_texts]
    low = [i + 1 for i, w in enumerate(words) if w < LOW_TEXT_WORDS]
    head = "\n".join(page_texts[:3])
    rec: dict = {
        "page_words": sum(words),
        "low_text_pages": low[:200],
        "low_text_page_count": len(low),
    }
    # Publisher banners (facts in the document, not verification).
    if "Published by the Minister of Justice" in head:
        rec["publisher_banner"] = "Justice Laws Website (Minister of Justice) consolidation banner"
        m = re.search(r"Current to ([A-Z][a-z]+ \d{1,2}, \d{4})", head)
        if m:
            rec["current_to"] = m.group(1)
        m = re.search(r"Last amended on ([A-Z][a-z]+ \d{1,2}, \d{4})", head)
        if m:
            rec["last_amended_on"] = m.group(1)
        left = pdf_text(path, 1, 1, crop=(0, 0, 306, 792))
        rec["cover_lines_english_column"] = [l.strip() for l in left.splitlines() if l.strip()][:14]
    if "REFERENCE CONVERSION - NOT A PUBLISHER-ISSUED PDF" in head:
        rec["reference_conversion"] = True
        m = re.search(r"retrieved (\d{4}-\d{2}-\d{2})", head)
        if m:
            rec["reference_conversion_retrieved"] = m.group(1)
        m = re.search(r"Source: (https?://\S+)", head)
        if m:
            rec["reference_conversion_stated_source"] = m.group(1)
    # Bilingual two-column detection: compare halves of sampled pages.
    sample = [p for p in range(2, min(pages, 40) + 1, 5)] or [1]
    left_en = left_fr = right_en = right_fr = 0
    for p in sample[:6]:
        lt = pdf_text(path, p, p, crop=(0, 0, 306, 792))
        rt = pdf_text(path, p, p, crop=(306, 0, 306, 792))
        a, b = language_ratio(lt)
        c, d = language_ratio(rt)
        left_en += a; left_fr += b; right_en += c; right_fr += d
    if left_en > 3 * max(left_fr, 1) and right_fr > 3 * max(right_en, 1) and right_fr > 20:
        rec["layout"] = "bilingual-two-column (English left, French right)"
    else:
        en, fr = language_ratio(full[:200000])
        rec["layout"] = "single-language" if fr * 3 < en else "mixed-or-french"
    # Municipality markers (document text, not filename).
    hay = full[:20000]
    markers = []
    for name, pat in [("Brampton", r"City of Brampton"), ("Mississauga", r"City of Mississauga"),
                      ("Peel Region", r"Regional Municipality of Peel|Peel Region")]:
        if re.search(pat, hay, re.I):
            markers.append(name)
    rec["municipal_markers_in_text"] = markers
    rec["first_lines"] = [l.strip() for l in head.splitlines() if l.strip()][:12]
    return rec


def _classify_doc(path: Path, converted_dir: Path | None) -> dict:
    rec = _doc_metadata(path)
    if converted_dir:
        docx = converted_dir / (path.stem + ".docx")
        if docx.exists():
            rec["converted_docx"] = str(docx)
            try:
                with zipfile.ZipFile(docx) as z:
                    xml = z.read("word/document.xml").decode("utf-8", "replace")
                txt = re.sub(r"<[^>]+>", " ", xml)
                m = re.search(r"Consolidation Period:\s*(.*?)\.\s", txt)
                if m:
                    rec["consolidation_period"] = re.sub(r"\s+", " ", m.group(1)).strip()
                m = re.search(r"Last amendment:\s*(.*?\.)\s", txt)
                if m:
                    rec["last_amendment"] = re.sub(r"\s+", " ", m.group(1)).strip()
                rec["not_yet_in_force_markers"] = len(re.findall(r'w:val="Y[a-z]', xml))
                rec["publisher_banner"] = "Ontario e-Laws Word export (style names and consolidation banner present)" \
                    if "ConsolidationPeriod" in xml or "Consolidation Period" in txt else None
            except (zipfile.BadZipFile, KeyError) as exc:  # pragma: no cover - defensive
                rec["conversion_error"] = str(exc)
        else:
            rec["conversion_error"] = "DOCX conversion not found; run soffice --convert-to docx"
    return rec


def build_inventory(uploads: Path, converted_dir: Path | None) -> dict:
    files = sorted(p for p in uploads.iterdir() if p.is_file())
    items = []
    for p in files:
        ext = p.suffix.lower().lstrip(".")
        item = {
            "upload_path": str(p),
            "original_filename": _upload_name(p),
            "format": ext,
            "bytes": p.stat().st_size,
            "sha256": sha256_file(p),
        }
        if ext == "pdf":
            info = pdf_info(p)
            item["pages"] = pdf_page_count(p)
            item["embedded_title"] = info.get("Title") or None
            item["producer"] = info.get("Producer") or None
            item["creator"] = info.get("Creator") or None
            item.update(_classify_pdf(p, item["pages"]))
        elif ext in ("doc", "docx"):
            item.update(_classify_doc(p, converted_dir))
        elif ext in ("txt", "md"):
            item["role"] = "requirements-or-notes (not legal source material)"
        else:
            item["role"] = "unsupported format"
        items.append(item)
    # Exact duplicates.
    by_hash = defaultdict(list)
    for it in items:
        by_hash[it["sha256"]].append(it["original_filename"] + " [" + Path(it["upload_path"]).name[:8] + "]")
    dup_groups = [v for v in by_hash.values() if len(v) > 1]
    for it in items:
        group = by_hash[it["sha256"]]
        it["exact_duplicate_count"] = len(group) - 1
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "uploads_dir": str(uploads),
        "file_count": len(items),
        "distinct_hashes": len(by_hash),
        "exact_duplicate_groups": dup_groups,
        "items": items,
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--uploads", required=True, type=Path)
    ap.add_argument("--converted", type=Path, default=None)
    ap.add_argument("--out", required=True, type=Path)
    a = ap.parse_args()
    inv = build_inventory(a.uploads, a.converted)
    write_json(a.out, inv)
    print(f"{inv['file_count']} files, {inv['distinct_hashes']} distinct, "
          f"{len(inv['exact_duplicate_groups'])} duplicate groups -> {a.out}")


if __name__ == "__main__":
    main()
