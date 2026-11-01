"""Extraction for municipal by-law PDFs (Peel Region, Brampton, Mississauga).

Municipal publications vary widely (office consolidations, schedules, maps,
signs, reference conversions). Extraction therefore:
  * always stores page-level text (the dependable unit for search and viewing);
  * removes running headers/footers that repeat across pages;
  * builds a *heuristic* section tree (numbered sections such as 1., 1.1, 1.1.2,
    (a), (1)) that is labelled "heuristic" in quality reporting;
  * OCRs image-only pages with Tesseract when available and marks that text
    "OCR - unverified";
  * never merges a reference-conversion banner into operative text.
"""
from __future__ import annotations

import re
import shutil
import subprocess
import tempfile
from collections import Counter
from pathlib import Path

from .structure import ANNOTATION, IN_FORCE, Provision, dehyphenate_join, build_vocabulary
from .util import normalize_ws, pdf_text

NUM_RE = re.compile(r"^(\d{1,3}(?:\.\d{1,3}){0,3})(?:\.|\))?(?:\s+(.*)|$)")
PART_RE = re.compile(r"^(PART|Part)\s+([IVXLC]+|\d+)\b\s*[–—:-]?\s*(.*)$")
SCHEDULE_RE = re.compile(r"^(SCHEDULE|S C H E D U L E)\s*[\"“]?([A-Z0-9IVXL]+(?:\.\d+)?)?[\"”]?\b(.*)$")
PARA_RE = re.compile(r"^\(([a-z]{1,2}|[ivx]{1,4}|\d{1,2})\)\s*(.*)$")
DEF_RE = re.compile(r"^\d{0,3}\s*[“\"]([^”\"]{1,80})[”\"]\s*(means|includes|shall mean|has the same meaning|refers to)\b")
BANNER_PREFIXES = ("REFERENCE CONVERSION", "Converted from the official", "been certified", "Source: http")


def _ocr_page(pdf: Path, page: int) -> str:
    if not shutil.which("tesseract") or not shutil.which("pdftoppm"):
        return ""
    with tempfile.TemporaryDirectory() as td:
        base = Path(td) / "p"
        subprocess.run(["pdftoppm", "-f", str(page), "-l", str(page), "-r", "200", "-png", str(pdf), str(base)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
        imgs = sorted(Path(td).glob("p*.png"))
        if not imgs:
            return ""
        res = subprocess.run(["tesseract", str(imgs[0]), "-", "--psm", "3"], stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, timeout=300)
        return res.stdout.decode("utf-8", "replace")


def _key(num: str) -> tuple[int, ...]:
    return tuple(int(x) for x in num.split("."))


def page_texts(pdf: Path, pages: int, ocr: bool = True) -> list[dict]:
    raw = pdf_text(pdf).split("\f")
    raw = raw[:pages] + [""] * max(0, pages - len(raw))
    # Running header/footer lines: identical (digit-normalised) lines on >= 50% of pages (min 3 pages).
    norm = lambda s: re.sub(r"\d+", "#", s.strip())
    counts: Counter[str] = Counter()
    for p in raw:
        for l in set(norm(x) for x in p.splitlines() if x.strip()):
            counts[l] += 1
    threshold = max(3, int(0.5 * pages))
    running = {l for l, c in counts.items()
               if c >= threshold and len(l) < 120 and len(re.findall(r"[A-Za-z]", l)) >= 4} if pages >= 3 else set()
    out = []
    for i, p in enumerate(raw):
        lines = [l.rstrip() for l in p.splitlines()]
        kept, removed = [], []
        for l in lines:
            s = l.strip()
            if not s:
                continue
            if norm(s) in running or re.fullmatch(r"-\s*\d+\s*-|Page \d+( of \d+)?|page \d+", s):
                removed.append(s)
                continue
            kept.append(s)
        words = sum(len(l.split()) for l in kept)
        rec = {"page": i + 1, "lines": kept, "ocr": False, "image_only": False}
        if words < 15 and ocr:
            text = _ocr_page(pdf, i + 1)
            ocr_lines = [normalize_ws(x) for x in text.splitlines() if x.strip()]
            if sum(len(x.split()) for x in ocr_lines) > words:
                rec["lines"] = ocr_lines
                rec["ocr"] = True
            rec["image_only"] = True
        out.append(rec)
    return out


def extract(pdf: Path, source_id: str, pages: int, ocr: bool = True) -> tuple[list[Provision], list[dict], list[str]]:
    pts = page_texts(pdf, pages, ocr=ocr)
    vocab = build_vocabulary("\n".join("\n".join(p["lines"]) for p in pts))
    provisions: list[Provision] = []
    issues: list[str] = []
    by_path: dict[str, Provision] = {}
    ordinal = 0
    part: Provision | None = None
    stack: list[Provision] = []       # numbered units, by depth
    para: Provision | None = None
    current: Provision | None = None
    last_top: tuple[int, ...] | None = None
    banner_lines: list[str] = []
    defn_list: tuple[Provision, int] | None = None

    def add(kind: str, number: str, path: str, parent: Provision | None, page: int, heading: str = "",
            status: str = IN_FORCE) -> Provision:
        nonlocal ordinal
        if path in by_path:
            n = 2
            while f"{path}~{n}" in by_path:
                n += 1
            issues.append(f"duplicate path {path} p{page}")
            path = f"{path}~{n}"
        ordinal += 1
        label = ("Part " + number) if kind == "part" else ("Schedule " + number if kind == "schedule" else f"s. {path}")
        p = Provision(source_id, kind, number, path, label, heading=heading,
                      parent_path=parent.path if parent else None, status=status, page_start=page, page_end=page,
                      ordinal=ordinal)
        provisions.append(p)
        by_path[path] = p
        return p

    for pt in pts:
        pg = pt["page"]
        for line in pt["lines"]:
            if line.startswith(BANNER_PREFIXES) or "NOT A PUBLISHER-ISSUED PDF" in line or \
                    line.startswith("Read with the amendments"):
                banner_lines.append(line)
                continue
            line = re.sub(r"^\d{1,3}(?=[“\"])", "", line)  # stray footnote numerals before defined terms
            if current is not None:
                current.page_end = pg
            m = PART_RE.match(line)
            if m and len(line) < 110:
                part = add("part", m.group(2), f"part:{m.group(2)}", None, pg, heading=normalize_ws(m.group(3)))
                stack, para, current = [], None, part
                continue
            m = SCHEDULE_RE.match(line)
            if m and len(line) < 110 and (m.group(2) or line.strip().upper() == "SCHEDULE"):
                name = m.group(2) or str(ordinal + 1)
                part = add("schedule", name, f"schedule:{name}", None, pg, heading=normalize_ws(m.group(3) or ""))
                stack, para, current = [], None, part
                last_top = None
                continue
            m = NUM_RE.match(line)
            if m and defn_list is not None and m.group(1) == str(defn_list[1]) and (m.group(2) or "")[:1].isupper():
                d0 = defn_list[0]
                para = add("paragraph", f"{m.group(1)}.", f"{d0.path}({m.group(1)})", d0, pg)
                para.lines.append(m.group(2) or "")
                current = para
                defn_list = (d0, defn_list[1] + 1)
                continue
            if m and part is not None and part.kind == "schedule":
                m = None  # numbers in schedule tables are row data, not sections
            if m:
                num = m.group(1)
                rest = m.group(2) or ""
                k = _key(num)
                depth = len(k)
                ok = False
                if rest and rest[:1].islower():
                    ok = False
                elif depth == 1:
                    ok = (last_top is None and k[0] <= 3) or (last_top is not None and last_top[0] < k[0] <= last_top[0] + 6)
                else:
                    parent_num = ".".join(num.split(".")[:-1])
                    ok = any(s.number == parent_num for s in stack)
                if ok:
                    if depth == 1:
                        last_top = k
                        stack = []
                    else:
                        stack = [s for s in stack if len(_key(s.number)) < depth]
                    parent = stack[-1] if stack else part
                    defn_list = None
                    unit = add("section" if depth == 1 else "subsection", num, num, parent, pg)
                    stack.append(unit)
                    para = None
                    current = unit
                    if rest:
                        unit.lines.append(rest)
                    continue
            pm = PARA_RE.match(line)
            if pm and stack:
                tok = pm.group(1)
                base = stack[-1]
                para = add("paragraph", f"({tok})", f"{base.path}({tok})", base, pg)
                current = para
                if pm.group(2):
                    para.lines.append(pm.group(2))
                continue
            dm = DEF_RE.match(line)
            if dm and stack:
                term = dm.group(1)
                slug = re.sub(r"[^a-z0-9]+", "-", term.lower()).strip("-")
                d = add("definition", term, f"{stack[-1].path}[def:{slug}]", stack[-1], pg, heading=term)
                d.lines.append(line)
                current = d
                defn_list = (d, 1)
                continue
            if current is None:
                # preamble / title material
                ordinal += 1
                p = Provision(source_id, "heading", "", f"front:{ordinal}", line[:80], text=line,
                              status=IN_FORCE, page_start=pg, page_end=pg, ordinal=ordinal)
                provisions.append(p)
                by_path[p.path] = p
                continue
            current.lines.append(line)
    for p in provisions:
        if p.lines:
            p.text = dehyphenate_join(p.lines, vocab)
        p.lines = []
    if banner_lines:
        ordinal += 1
        provisions.append(Provision(source_id, "note", "", "note:reference-conversion", "Reference conversion notice",
                                    text=" ".join(banner_lines), status=ANNOTATION, ordinal=ordinal))
    page_records = [{
        "page": pt["page"],
        "region": "body",
        "text": dehyphenate_join(pt["lines"], vocab) if pt["lines"] else "",
        "ocr": pt["ocr"],
        "image_only": pt["image_only"],
    } for pt in pts]
    return provisions, page_records, issues
