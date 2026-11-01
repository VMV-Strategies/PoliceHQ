"""Extraction for Justice Laws Website bilingual consolidations (PDF).

* English is taken from the left column only, so English and French are never
  interleaved. Pages printed full-width in English (tables) are read whole;
  pages printed in French only are skipped (the original PDF still contains them).
* Running headers and the "Current to / Last amended" footer are removed.
* Table of provisions, foreword, endnotes, "RELATED PROVISIONS" and
  "AMENDMENTS NOT IN FORCE" regions are separated from operative provisions.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from decimal import Decimal
from pathlib import Path

from .structure import (ANNOTATION, IN_FORCE, NOT_YET_IN_FORCE, REPEALED, Provision,
                        build_vocabulary, dehyphenate_join, int_to_roman, is_roman,
                        label_for, next_letter, roman_to_int, section_decimal)
from .util import language_ratio, pdf_text

SECTION_RE = re.compile(r"^(\d+(?:\.\d+)*)(?:\s+|$)(?:\((\d+(?:\.\d+)?)\)\s*)?(?=[A-Z“\"‘'\[(]|$)")
BARE_NUMBER_RE = re.compile(r"^\d+(?:\.\d+)*$")


def _reorder_margin_numbers(lines: list[str]) -> list[str]:
    """Justice Laws PDFs sometimes emit a section number printed in the margin
    *after* the first line of its subsection (1). Move such a bare number in
    front of the "(1)" line so the section is recognised."""
    out = [l.strip() for l in lines if l.strip()]
    i = 0
    while i < len(out):
        if re.match(r"^\(1\)\s", out[i]):
            for j in range(i + 1, min(i + 4, len(out))):
                if BARE_NUMBER_RE.match(out[j]) and (j + 1 >= len(out) or not BARE_NUMBER_RE.match(out[j + 1])):
                    num = out.pop(j)
                    out[i] = num + " " + out[i]
                    break
        i += 1
    return out
SUBSECTION_RE = re.compile(r"^\((\d+(?:\.\d+)?)\)\s*")
PARA_RE = re.compile(r"^\(([a-z]{1,3}(?:\.\d+)?)\)\s*")
CLAUSE_RE = re.compile(r"^\(([A-Z](?:\.\d+)?)\)\s*")
PART_RE = re.compile(r"^PART ([IVXLC]+(?:\.\d+)?)\b\s*(.*)$")
HISTORY_RE = re.compile(r"^(R\.S\.(?:C\.)?,? ?\d{0,4}|\d{4}, c\. ?[\w.-]+|S\.C\. \d{4}|SOR/\d|\d{4}, c\.|R\.S\.)")
REPEALED_RE = re.compile(r"^\[Repealed|^\[Abrogé", re.I)
DEFINITION_RE = re.compile(r"^([a-z][\w’'\- ]{0,60}?|[A-Z][\w’'\- ]{0,60}?) (means|includes|has the same meaning|has the meaning)\b")
FOOTER_RE = re.compile(r"^(Current to|Last amended on|À jour au|Dernière modification)")
SECTIONS_HDR_RE = re.compile(r"^(Sections?|Articles?) [\dA-Z.\-–, ]+$")
SPECIAL_REGIONS = {
    "TABLE OF PROVISIONS": "toc",
    "FOREWORD": "front",
    "ENDNOTES": ANNOTATION,
    "RELATED PROVISIONS": ANNOTATION,
    "AMENDMENTS NOT IN FORCE": NOT_YET_IN_FORCE,
}


@dataclass
class PageText:
    page: int
    lines: list[str]
    region: str          # body | toc | front | annotation | not-yet-in-force | french-only
    full_width: bool
    header_context: str  # first header line (e.g. Act name in the Constitution Acts)


def _page_texts(pdf: Path, pages: int) -> list[PageText]:
    left_all = pdf_text(pdf, crop=(0, 0, 306, 792)).split("\f")
    right_all = pdf_text(pdf, crop=(306, 0, 306, 792)).split("\f")
    out: list[PageText] = []
    region = "front"
    for i in range(pages):
        left = left_all[i] if i < len(left_all) else ""
        right = right_all[i] if i < len(right_all) else ""
        lines = [l.rstrip() for l in left.splitlines()]
        nonempty = [l.strip() for l in lines if l.strip()]
        header2 = nonempty[1] if len(nonempty) > 1 else ""
        context = nonempty[0] if nonempty else ""
        r_en, r_fr = language_ratio(right)
        l_en, l_fr = language_ratio(left)
        full_width = False
        if "(French)" in header2 or (l_fr > 3 * max(l_en, 1) and l_fr > 10):
            out.append(PageText(i + 1, [], "french-only", False, context))
            continue
        if r_en > 3 * max(r_fr, 1) and r_en > 10:
            full_width = True
            lines = [l.rstrip() for l in pdf_text(pdf, i + 1, i + 1, layout=True).splitlines()]
            # keep only the English half of the running header in layout mode
        for key, reg in SPECIAL_REGIONS.items():
            if header2.upper().startswith(key):
                region = reg
                break
        else:
            if SECTIONS_HDR_RE.match(header2) or i > 0 and region in ("front", "toc") and _looks_like_body(nonempty):
                region = "body"
            elif region in ("toc",) and not header2.upper().startswith("TABLE OF PROVISIONS"):
                region = "body"
        out.append(PageText(i + 1, _strip_header_footer(lines), region, full_width, context))
    return out


def _looks_like_body(nonempty: list[str]) -> bool:
    return any(SECTIONS_HDR_RE.match(l) for l in nonempty[:6])


def _strip_header_footer(lines: list[str]) -> list[str]:
    nonempty_idx = [i for i, l in enumerate(lines) if l.strip()]
    if not nonempty_idx:
        return []
    # footer: from first footer line to end
    end = len(lines)
    for i, l in enumerate(lines):
        if FOOTER_RE.match(l.strip()):
            end = i
            break
    body = lines[:end]
    idx = [i for i, l in enumerate(body) if l.strip()]
    if not idx:
        return []
    # header: title line, then header lines up to and including "Section(s) ..." within first 6 non-empty lines
    cut = idx[0] + 1
    for j in idx[1:7]:
        if SECTIONS_HDR_RE.match(body[j].strip()):
            cut = j + 1
            break
    else:
        # Without a Sections line, drop the title line and a following PART/heading line that repeats the running head.
        if len(idx) > 1 and (PART_RE.match(body[idx[1]].strip()) or body[idx[1]].strip().startswith("SCHEDULE")):
            cut = idx[1] + 1
    return [l for l in body[cut:]]


class FederalParser:
    def __init__(self, source_id: str, constitution: bool = False):
        self.source_id = source_id
        self.constitution = constitution
        self.provisions: list[Provision] = []
        self.by_path: dict[str, Provision] = {}
        self.part: Provision | None = None
        self.section: Provision | None = None
        self.subsection: Provision | None = None
        self.paragraph: Provision | None = None
        self.subparagraph: Provision | None = None
        self.clause: Provision | None = None
        self.current: Provision | None = None
        self.pending: list[str] = []
        self.last_section_num: Decimal | None = None
        self.closed = True
        self.region = "body"
        self.act_prefix = ""
        self.act_prefix_label = ""
        self.ordinal = 0
        self.issues: list[str] = []
        self.in_definitions = False
        self.definition: Provision | None = None
        self.seen_section = False

    # ------------------------------------------------------------------ helpers
    def _status(self) -> str:
        return {"body": IN_FORCE, ANNOTATION: ANNOTATION, NOT_YET_IN_FORCE: NOT_YET_IN_FORCE}.get(self.region, ANNOTATION)

    def _add(self, kind: str, number: str, path: str, parent: Provision | None, page: int, text: str = "",
             heading: str = "") -> Provision:
        status = self._status()
        key = path if status == IN_FORCE else f"{path}@{status}"
        if key in self.by_path:
            # Duplicate path (e.g. repeated numbering in schedules); disambiguate and record.
            n = 2
            while f"{path}~{n}" in self.by_path or f"{path}~{n}@{status}" in self.by_path:
                n += 1
            self.issues.append(f"duplicate path {path} on page {page}")
            path = f"{path}~{n}"
            key = path if status == IN_FORCE else f"{path}@{status}"
        self.ordinal += 1
        label_prefix = "s."
        disp_path = path
        if self.constitution and self.act_prefix:
            disp_path = path.split(":", 1)[1] if ":" in path and not path.startswith(("part:", "schedule:")) else path
        p = Provision(self.source_id, kind, number, path, label_for(disp_path, label_prefix), heading=heading,
                      parent_path=parent.path if parent else (self.part.path if self.part and kind == "section" else None),
                      status=status, page_start=page, page_end=page, ordinal=self.ordinal)
        if self.constitution and self.act_prefix:
            p.label = f"{self.act_prefix_label} {p.label}".strip()
        if text:
            p.lines.append(text)
        self.provisions.append(p)
        self.by_path[key] = p
        self.current = p
        return p

    def _take_heading(self) -> str:
        """Pop a marginal note from the end of the current unit's lines or pending lines."""
        is_pending = bool(self.pending)
        src = self.pending if is_pending else (self.current.lines if self.current else [])
        if not src:
            return ""
        block: list[str] = []
        i = len(src) - 1
        while i >= 0 and len(block) < 4:
            l = src[i].strip()
            if not l:
                i -= 1
                continue
            if re.search(r"[.;:,]$|\]$", l) or HISTORY_RE.match(l) or len(l) > 95:
                break
            block.insert(0, l)
            i -= 1
        if not block:
            return ""
        before = src[i].strip() if i >= 0 else ""
        closed = i < 0 or bool(re.search(r"[.;:]$|\]$|\)$", before)) or bool(HISTORY_RE.match(before))
        if not is_pending and (not closed or not block[0][:1].isupper()):
            return ""
        cont = re.compile(r"\b(by|of|and|or|the|to|in|for|from|with|on|at|a|an|under|against|respecting|not|into|—|–|-)$")
        upper_idx = [k for k, l in enumerate(block) if l[:1].isupper() and not (k > 0 and cont.search(block[k - 1]))]
        if not upper_idx:
            return ""
        idx = upper_idx[-1]
        group, note = block[:idx], " ".join(block[idx:])
        del src[i + 1:]
        if is_pending:
            self.pending = list(src) + group
        else:
            self.pending = group
        return note

    def _flush_pending_as_headings(self, page: int) -> None:
        if self.pending:
            for h in self.pending:
                if h.strip():
                    self.ordinal += 1
                    path = f"heading:{self.ordinal}"
                    p = Provision(self.source_id, "heading", "", path, h.strip(), text=h.strip(),
                                  parent_path=self.part.path if self.part else None, status=self._status(),
                                  page_start=page, page_end=page, ordinal=self.ordinal)
                    self.provisions.append(p)
                    self.by_path[path] = p
            self.pending = []

    def _sec_path(self, num: str) -> str:
        return f"{self.act_prefix}{num}" if self.act_prefix else num

    # ------------------------------------------------------------------ main
    def feed(self, page: PageText) -> None:
        if page.region in ("toc", "front", "french-only"):
            return
        if page.region != self.region:
            self.region = page.region
            self._reset_units(region_change=True)
        if self.constitution:
            ctx = page.header_context.upper()
            m = re.match(r"^(THE )?(CONSTITUTION ACT|CANADA ACT) ?,? ?(\d{4})", ctx)
            if m and page.region == "body":
                prefix = ("CA" if m.group(2) == "CONSTITUTION ACT" else "CANADA") + m.group(3) + ":"
                if prefix != self.act_prefix:
                    self.act_prefix = prefix
                    self.act_prefix_label = ("Constitution Act, " if m.group(2) == "CONSTITUTION ACT" else "Canada Act ") + m.group(3)
                    self._reset_units(region_change=True)
        for raw in _reorder_margin_numbers(page.lines):
            line = raw.strip()
            if not line:
                continue
            if self.constitution:
                line = re.sub(r"(?<=[A-Za-z.,;:’)\]])\((\d{1,3})\)(?=\s|$)", "", line)
            self._line(line, page.page)

    def _reset_units(self, region_change: bool = False) -> None:
        self.section = self.subsection = self.paragraph = self.subparagraph = self.clause = None
        self.definition = None
        self.current = None
        self.last_section_num = None
        self.pending = []
        self.closed = True
        if region_change:
            self.part = None

    def _line(self, line: str, page: int) -> None:
        if self.current:
            self.current.page_end = page
        m = PART_RE.match(line)
        if m and (self.closed or not self.current or re.search(r"[.;:\]]$", (self.current.lines or [""])[-1])):
            self._flush_pending_as_headings(page)
            num = m.group(1)
            path = f"part:{self.act_prefix}{num}" if self.act_prefix else f"part:{num}"
            title = m.group(2).strip()
            self.section = self.subsection = self.paragraph = self.subparagraph = self.clause = None
            self.part = None
            self.part = self._add("part", num, path, None, page, heading=title)
            self.part.text = ""
            self.closed = True
            self.current = None
            self._part_title_open = True
            return
        if line.upper().startswith("SCHEDULE") and (self.closed or self.current is None) and len(line) < 120:
            self._flush_pending_as_headings(page)
            name = re.sub(r"\s+", " ", line)
            path = f"schedule:{self.act_prefix}{name}"
            self.part = self._add("schedule", name, path, None, page, heading=name)
            self.section = self.subsection = self.paragraph = self.subparagraph = self.clause = None
            self.last_section_num = None
            self.current = self.part
            self.closed = False
            return
        sm = SECTION_RE.match(line)
        if sm and self._accept_section(sm.group(1), line):
            num = sm.group(1)
            heading = self._take_heading()
            self._flush_pending_as_headings(page)
            rest = line[sm.end():]
            self.subsection = self.paragraph = self.subparagraph = self.clause = None
            self.definition = None
            self.section = self._add("section", num, self._sec_path(num), self.part, page, heading=heading)
            self.section.parent_path = self.part.path if self.part else None
            self.last_section_num = section_decimal(num)
            self.seen_section = True
            self.in_definitions = bool(re.match(r"(Definitions?|Interpretation)", heading or "")) or \
                bool(re.match(r"(The following definitions|In this (Act|Part|section|Regulation|Regulations)\b)", rest))
            self.closed = False
            if REPEALED_RE.match(rest):
                self.section.status = REPEALED if self._status() == IN_FORCE else self.section.status
            if sm.group(2):
                self.subsection = self._add("subsection", f"({sm.group(2)})", f"{self.section.path}({sm.group(2)})",
                                            self.section, page)
            if rest:
                self.current.lines.append(rest)
            return
        if self.section is None and not self.closed and self.current is None:
            self.pending.append(line)
            return
        if self.section is not None:
            ss = SUBSECTION_RE.match(line)
            if ss and self._accept_subsection(ss.group(1), line[ss.end():]):
                heading = self._take_heading()
                self._flush_pending_as_headings(page)
                self.paragraph = self.subparagraph = self.clause = None
                self.definition = None
                self.subsection = self._add("subsection", f"({ss.group(1)})", f"{self.section.path}({ss.group(1)})",
                                            self.section, page, heading=heading)
                rest = line[ss.end():]
                if rest:
                    self.subsection.lines.append(rest)
                self.closed = False
                return
            pm = PARA_RE.match(line)
            if pm:
                tok = pm.group(1)
                kind = self._para_kind(tok)
                rest = line[pm.end():]
                if kind == "paragraph":
                    base = self.definition or self.subsection or self.section
                    self.subparagraph = self.clause = None
                    self.paragraph = self._add("paragraph", f"({tok})", f"{base.path}({tok})", base, page)
                    if rest:
                        self.paragraph.lines.append(rest)
                    self.closed = False
                    return
                if kind == "subparagraph":
                    self.clause = None
                    self.subparagraph = self._add("subparagraph", f"({tok})", f"{self.paragraph.path}({tok})",
                                                  self.paragraph, page)
                    if rest:
                        self.subparagraph.lines.append(rest)
                    self.closed = False
                    return
            cm = CLAUSE_RE.match(line)
            if cm and self.subparagraph is not None and self._accept_clause(cm.group(1)):
                self.clause = self._add("clause", f"({cm.group(1)})", f"{self.subparagraph.path}({cm.group(1)})",
                                        self.subparagraph, page)
                rest = line[cm.end():]
                if rest:
                    self.clause.lines.append(rest)
                return
            if HISTORY_RE.match(line) and re.search(r"[.;\]]$", line) and len(line) < 400:
                self.section.history = (self.section.history + " " + line).strip()
                self.closed = True
                self.current = None
                return
            if self.in_definitions and self.subsection is None or self.in_definitions and self.subsection is not None and \
                    self.subsection.path.endswith("(1)"):
                prev = self._last_line()
                starts_def = (not line.startswith("(")) and (prev.endswith((";", ")", ":", "]")) or prev.endswith(",") and self.current is (self.subsection or self.section))
                dm = DEFINITION_RE.match(line)
                if starts_def and (dm or len(line) <= 60 or re.match(r"^[\w’'\- ]{2,60}(,| means\b| includes\b| has the\b| does not include\b)", line)):
                    tm = re.match(r"^(.+?)(?:,| means\b| includes\b| has the\b| does not include\b|$)", line)
                    term = (tm.group(1) if tm else line).strip()
                    if 2 <= len(term) <= 70:
                        base = self.subsection or self.section
                        slug = re.sub(r"[^a-z0-9]+", "-", term.lower()).strip("-")
                        d = self._add("definition", term, f"{base.path}[def:{slug}]", base, page)
                        d.heading = term
                        d.lines.append(line)
                        self.definition = d
                        self.paragraph = self.subparagraph = self.clause = None
                        return
        if self.closed:
            self.pending.append(line)
        elif self.current is not None:
            self.current.lines.append(line)
        else:
            self.pending.append(line)

    def _last_line(self) -> str:
        if self.current and self.current.lines:
            return self.current.lines[-1].strip()
        return ""

    def _accept_section(self, num: str, line: str) -> bool:
        d = section_decimal(num)
        if d is None:
            return False
        if re.match(r"^\d{4}, c\.", line) or re.match(r"^\d+\.\d+\s+[a-z]", line):
            return False
        if not self.closed and self.current is not None:
            prev = self._last_line()
            # a wrapped sentence ending without punctuation followed by a number is usually continuation,
            # unless the unclosed tail is a block of heading lines (group heading + marginal note).
            if prev and not re.search(r"[.;:\]]$", prev) and not self._trailing_heading_block():
                return False
        if self.last_section_num is None:
            # The first section of a document body must look like a start (<= 10) unless a Part
            # heading precedes it; later regions (e.g. amendments not in force) may start anywhere.
            return d <= 10 or (self.part is not None or self.seen_section or self.region != "body") and d < 100000
        return self.last_section_num < d <= self.last_section_num + 80

    def _trailing_heading_block(self) -> bool:
        src = self.current.lines if self.current else []
        block = []
        i = len(src) - 1
        while i >= 0 and len(block) < 4:
            l = src[i].strip()
            if re.search(r"[.;:,]$|\]$", l) or HISTORY_RE.match(l) or len(l) > 95:
                break
            block.insert(0, l)
            i -= 1
        if not block or i < 0:
            return False
        return block[0][:1].isupper()

    @staticmethod
    def _heading_candidate(s: str) -> bool:
        return 0 < len(s) <= 95 and s[:1].isupper() and not re.search(r"[.;:,]$", s)

    def _accept_subsection(self, tok: str, rest: str = "") -> bool:
        d = section_decimal(tok)
        if d is None:
            return False
        prev = self._last_line()
        starts_like_text = bool(rest) and (rest[:1].isupper() or rest[:1] in "“\"‘'[(")
        if rest and not starts_like_text:
            return False
        if not starts_like_text and prev and not re.search(r"[.;:\]—]$", prev) and not self._heading_candidate(prev) \
                and self.current is not None:
            return False
        if self.subsection is None:
            return d in (Decimal(1), Decimal("0.1")) or d <= 2
        last = section_decimal(self.subsection.number.strip("()"))
        return last is not None and last < d <= last + 10

    def _para_kind(self, tok: str) -> str:
        base = tok.split(".")[0]
        expected_letter = next_letter(self.paragraph.number.strip("()")) if self.paragraph else "a"
        if is_roman(base) and self.paragraph is not None:
            expected_roman = "i"
            if self.subparagraph is not None:
                sb = self.subparagraph.number.strip("()").split(".")[0]
                if is_roman(sb):
                    expected_roman = int_to_roman(roman_to_int(sb) + 1)
            if base == expected_roman or (self.subparagraph is not None and "." in tok and base == self.subparagraph.number.strip("()").split(".")[0]):
                if base != expected_letter or self.subparagraph is not None:
                    return "subparagraph"
            if base == expected_letter or ("." in tok and self.paragraph and base == self.paragraph.number.strip("()").split(".")[0]):
                return "paragraph"
            return "subparagraph" if base == expected_roman else "paragraph"
        return "paragraph"

    def _accept_clause(self, tok: str) -> bool:
        base = tok.split(".")[0]
        if self.clause is None:
            return base == "A"
        last = self.clause.number.strip("()").split(".")[0]
        return ord(base) == ord(last) + 1 or ("." in tok and base == last)

    def finish(self, vocabulary: set[str]) -> list[Provision]:
        self._flush_pending_as_headings(self.provisions[-1].page_end if self.provisions else 0)
        for p in self.provisions:
            if p.lines:
                p.text = dehyphenate_join(p.lines, vocabulary)
            p.lines = []
            if p.kind == "section" and REPEALED_RE.match(p.text or ""):
                p.status = REPEALED if p.status == IN_FORCE else p.status
        return self.provisions


def extract(pdf: Path, source_id: str, pages: int, constitution: bool = False) -> tuple[list[Provision], list[dict], list[str]]:
    page_texts = _page_texts(pdf, pages)
    all_text = "\n".join("\n".join(p.lines) for p in page_texts)
    vocab = build_vocabulary(all_text)
    parser = FederalParser(source_id, constitution=constitution)
    for pt in page_texts:
        parser.feed(pt)
    provisions = parser.finish(vocab)
    page_records = []
    for pt in page_texts:
        txt = dehyphenate_join(pt.lines, vocab) if pt.lines else ""
        page_records.append({
            "page": pt.page,
            "region": pt.region,
            "full_width": pt.full_width,
            "text": txt,
        })
    return provisions, page_records, parser.issues
