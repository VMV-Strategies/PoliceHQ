"""Automated extraction-quality checks.

These checks are mechanical. Passing them is *not* "extraction verified" in the
legal-review sense; that state requires a recorded human comparison against the
original. The app shows both.
"""
from __future__ import annotations

from decimal import Decimal

from .structure import Provision, section_decimal


def assess(rec: dict, inv_item: dict, provs: list[Provision], pages: list[dict], issues: list[str]) -> dict:
    notes: list[str] = []
    fam = rec.get("publisher_status", "")
    sections = [p for p in provs if p.kind == "section" and p.status == "in-force"]
    n = max(1, len(provs))
    dup = sum(1 for i in issues if i.startswith("duplicate"))
    other = len(issues) - dup
    if dup:
        notes.append(f"{dup} duplicate numbering paths disambiguated (~n suffix)")
    if other:
        notes.append(f"{other} other parser warnings")
    image_pages = [p["page"] for p in pages if p.get("image_only")]
    ocr_pages = [p["page"] for p in pages if p.get("ocr")]
    if image_pages:
        notes.append(f"image-only pages: {image_pages[:20]}{'…' if len(image_pages) > 20 else ''}")
    if ocr_pages:
        notes.append(f"OCR text (unverified) on pages: {ocr_pages[:20]}")
    # numbering monotonicity (federal/provincial)
    regress = 0
    last: Decimal | None = None
    for s in sections:
        d = section_decimal(s.number.split("~")[0]) if s.number else None
        if d is None:
            continue
        if last is not None and d <= last and ":" not in s.path:
            regress += 1
        last = d
    if regress:
        notes.append(f"{regress} section-number regressions (possible missed or repeated sections)")
    empty = sum(1 for p in provs if p.kind in ("section", "subsection", "paragraph") and not p.text
                and not any(q.parent_path == p.path for q in provs[:0]))
    total_words = sum(len((p.text or "").split()) for p in provs) + sum(len((pg.get("text") or "").split()) for pg in pages)
    if inv_item.get("format") == "pdf":
        src_words = inv_item.get("page_words") or 0
        if src_words and total_words < 0.5 * src_words * (0.45 if "Justice Laws" in fam else 1.0):
            notes.append(f"possible truncation: extracted {total_words} words vs ~{src_words} in source text layer")
    trusted = False
    if fam.startswith("publisher-issued"):
        if (dup + other) / n < 0.03 and regress <= max(3, len(sections) // 100) and sections:
            quality = "automated-checks-passed"
        else:
            quality = "passed-with-warnings"
        trusted = quality in ("automated-checks-passed", "passed-with-warnings") and regress <= max(5, len(sections) // 50)
    elif rec.get("doc_type", "").startswith(("map", "sign")):
        quality = "image-only"
        notes.append("image content; view the original. Any OCR text is unverified.")
    elif fam.startswith("reference conversion"):
        quality = "heuristic-structure"
        notes.append("reference conversion: not a publisher-issued document; amendment completeness not certified")
    else:
        quality = "heuristic-structure"
        notes.append("municipal structure parsed heuristically; cite by page and verify against the original")
    if not provs and not any((p.get("text") or "").strip() for p in pages):
        quality = "unusable"
        trusted = False
    notes.append("automated checks only; no human extraction verification recorded")
    return {"quality": quality, "trusted": trusted, "notes": "; ".join(notes), "sections": len(sections),
            "warnings": len(issues), "regressions": regress, "words": total_words}
