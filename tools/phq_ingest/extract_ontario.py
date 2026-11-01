"""Extraction for Ontario e-Laws Word exports (.doc converted to .docx on the
development computer with LibreOffice).

e-Laws paragraph style names carry the structure:
  partnum / heading1 / headnote / section / subsection / paragraph / subpara /
  subclause / subsubpara / subsubclause / definition / footnoteLeft / Pnote ...
Styles prefixed with "Y" hold text that is NOT YET IN FORCE (shown after a
"Note: On a day to be named..." annotation, style "Pnote"). Those are stored with
status "not-yet-in-force" and never merged into operative text. Regulations use
the same names with an "-e" suffix.
"""
from __future__ import annotations

import re
from pathlib import Path

import docx  # python-docx

from .structure import (ANNOTATION, IN_FORCE, NOT_YET_IN_FORCE, REPEALED, Provision, label_for)
from .util import normalize_ws

NUM_SECTION = re.compile(r"^(\d+(?:\.\d+)*)\.?\s+(?:\((\d+(?:\.\d+)?)\)\s+)?")
NUM_SUBSECTION = re.compile(r"^\((\d+(?:\.\d+)?)\)\s+")
NUM_CLAUSE = re.compile(r"^\(([a-z]{1,3}(?:\.\d+)?)\)\s+")
NUM_PARA = re.compile(r"^(\d+(?:\.\d+)?)\.\s+")
NUM_SUBCLAUSE = re.compile(r"^\(([ivxlc]+(?:\.\d+)?)\)\s+")
NUM_SUBPARA = re.compile(r"^([ivxlc]+(?:\.\d+)?)\.\s+")
NUM_SUBSUB = re.compile(r"^\(?([A-Z](?:\.\d+)?)[.)]\s+")
HISTORY_TAIL = re.compile(r"(?:\s{2,}|(?<=[.;:])\s+)((?:R\.S\.O\. \d{4}|\d{4}, c\. ?\d+|O\. Reg\. \d+/\d+)[^“”]*?\.)\s*$")


def _base_style(name: str) -> tuple[str, bool]:
    n = name
    not_in_force = False
    if n.startswith("Y") and len(n) > 1 and n[1].islower():
        n = n[1:]
        not_in_force = True
    if n.endswith("-e"):
        n = n[:-2]
    return n, not_in_force


def _clean(text: str) -> str:
    return normalize_ws(text.replace("\t", " "))


def _split_history(text: str) -> tuple[str, str]:
    """e-Laws appends amendment citations after two spaces at the end of a unit."""
    raw = text.replace(" ", " ")
    m = HISTORY_TAIL.search(raw)
    if m:
        return _clean(raw[: m.start()]), _clean(m.group(1))
    return _clean(raw), ""


class OntarioParser:
    def __init__(self, source_id: str):
        self.source_id = source_id
        self.provisions: list[Provision] = []
        self.by_key: dict[str, Provision] = {}
        self.part: Provision | None = None
        self.sec: Provision | None = None
        self.sub: Provision | None = None
        self.clause: Provision | None = None
        self.subclause: Provision | None = None
        self.subsub: Provision | None = None
        self.defn: Provision | None = None
        self.headnote = ""
        self.group_heading = ""
        self.ordinal = 0
        self.issues: list[str] = []
        self.pending_note: list[str] = []
        self.meta: dict[str, str] = {}
        self.history_block: Provision | None = None

    def _add(self, kind: str, number: str, path: str, parent: Provision | None, text: str, status: str,
             heading: str = "") -> Provision:
        key = path if status == IN_FORCE else f"{path}@{status}"
        if key in self.by_key:
            n = 2
            while f"{key}~{n}" in self.by_key:
                n += 1
            self.issues.append(f"duplicate path {key}")
            path = f"{path}~{n}"
            key = path if status == IN_FORCE else f"{path}@{status}"
        self.ordinal += 1
        body, hist = _split_history(text)
        p = Provision(self.source_id, kind, number, path, label_for(path), heading=heading, text=body,
                      parent_path=parent.path if parent else (self.part.path if self.part else None),
                      status=status, history=hist, ordinal=self.ordinal)
        if self.pending_note and status == NOT_YET_IN_FORCE:
            p.notes.extend(self.pending_note)
        if re.match(r"^(Repealed|\[Repealed|Revoked)", body) or re.search(r"\bRepealed: \d{4}", body) and len(body) < 120:
            if status == IN_FORCE:
                p.status = REPEALED
        self.provisions.append(p)
        self.by_key[key] = p
        return p

    def feed(self, style: str, raw_text: str) -> None:
        text = raw_text.strip("\n")
        if not text.strip():
            return
        base, nif = _base_style(style)
        status = NOT_YET_IN_FORCE if nif else IN_FORCE
        t = _clean(text)
        tr = re.sub(r"[ \t\u00a0]{2,}", "  ", text.replace("\t", " ").replace("\u00a0", " ")).strip()
        if base in ("shorttitle", "ActTitle", "regtitle", "regnumber", "chapter", "made/app/filed"):
            self.meta.setdefault(base, t)
            return
        if base == "ConsolidationPeriod":
            self.meta["consolidation_period"] = t
            return
        if base == "comment" and t.startswith("Last amendment"):
            self.meta["last_amendment"] = t
            return
        if base in ("toc", "Normal", "line", "ellipsis"):
            return
        if base == "footnoteLeft" or base == "footnote":
            if t.startswith("Legislative History"):
                self.meta["legislative_history"] = t
            elif self.sec is not None and not t.startswith("Section Amendments"):
                self.sec.history = (self.sec.history + "; " + t).strip("; ") if self.sec.history else t
            return
        if base == "Pnote":
            self.pending_note.append(t)
            self.ordinal += 1
            path = f"note:{self.ordinal}"
            p = Provision(self.source_id, "note", "", path, "Editorial note", text=t,
                          parent_path=self.sec.path if self.sec else (self.part.path if self.part else None),
                          status=ANNOTATION, ordinal=self.ordinal)
            self.provisions.append(p)
            return
        if not nif:
            self.pending_note = []
        if base in ("partnum", "partnumRepeal"):
            m = re.match(r"^PART\s+([IVXLC]+(?:\.\d+)?)", t, re.I)
            num = m.group(1).upper() if m else str(self.ordinal + 1)
            title = re.sub(r"^PART\s+[IVXLC.\d]+\s*", "", text.replace("\n", " "), flags=re.I).strip()
            self.part = None
            self.part = self._add("part", num, f"part:{num}", None, "", status, heading=_clean(title))
            self.sec = self.sub = self.clause = self.subclause = self.subsub = self.defn = None
            return
        if base in ("heading1", "heading2", "heading3", "headingx", "schedule"):
            self.group_heading = t
            self.ordinal += 1
            path = f"heading:{self.ordinal}"
            p = Provision(self.source_id, "heading", "", path, t, text=t,
                          parent_path=self.part.path if self.part else None, status=status, ordinal=self.ordinal)
            self.provisions.append(p)
            return
        if base in ("headnote", "headnoteitalic"):
            self.headnote = t
            return
        if base in ("section", "Psection"):
            m = NUM_SECTION.match(t)
            if not m:
                # Closing words that follow a list of clauses ("... is guilty of an offence ...").
                parent = self.sub or self.sec
                if parent is not None:
                    self._add("closing-words", "", f"{parent.path}[closing]", parent, tr, status)
                    self.clause = self.subclause = self.subsub = None
                else:
                    self.issues.append(f"unnumbered section text: {t[:60]}")
                return
            num = m.group(1)
            rest = text.replace(" ", " ")
            rest = re.sub(r"^\s*" + re.escape(num) + r"\.?\s+", "", rest.strip())
            self.sec = self._add("section", num, num, self.part, "", status, heading=self.headnote)
            self.headnote = ""
            self.sub = self.clause = self.subclause = self.subsub = self.defn = None
            if m.group(2):
                rest2 = re.sub(r"^\(" + re.escape(m.group(2)) + r"\)\s*", "", rest.strip())
                self.sub = self._add("subsection", f"({m.group(2)})", f"{num}({m.group(2)})", self.sec, rest2, status)
            else:
                body, hist = _split_history(rest)
                self.sec.text, self.sec.history = body, hist
            return
        if base in ("subsection", "Psubsection"):
            m = NUM_SUBSECTION.match(t)
            if not m or self.sec is None:
                self._append(t)
                return
            rest = re.sub(r"^\s*\(" + re.escape(m.group(1)) + r"\)\s*", "", text.replace(" ", " ").strip())
            self.sub = self._add("subsection", f"({m.group(1)})", f"{self.sec.path}({m.group(1)})", self.sec, rest,
                                 status, heading=self.headnote)
            self.headnote = ""
            self.clause = self.subclause = self.subsub = self.defn = None
            return
        if base in ("definition", "defparagraph"):
            if base == "defparagraph" and self.defn is not None:
                self._child_of(self.defn, tr, status)
                return
            parent = self.sub or self.sec
            if parent is None:
                return
            m = re.match(r"^[“\"]([^”\"]+)[”\"]", t)
            term = m.group(1) if m else t[:40]
            slug = re.sub(r"[^a-z0-9]+", "-", term.lower()).strip("-")
            self.defn = self._add("definition", term, f"{parent.path}[def:{slug}]", parent, tr, status, heading=term)
            self.clause = self.subclause = self.subsub = None
            return
        if base in ("paragraph", "clause", "defclause"):
            parent = self.defn if (self.defn is not None and base in ("paragraph", "defclause") and self._defn_open()) \
                else (self.sub or self.sec)
            if parent is None:
                return
            m = NUM_CLAUSE.match(tr) or NUM_PARA.match(tr)
            if not m:
                self._append(tr)
                return
            tok = m.group(1)
            rest = tr[m.end():]
            self.clause = self._add("paragraph", tok, f"{parent.path}({tok})", parent, rest, status)
            self.subclause = self.subsub = None
            return
        if base in ("subclause", "subpara"):
            parent = self.clause or self.sub or self.sec
            if parent is None:
                return
            m = NUM_SUBCLAUSE.match(tr) or NUM_SUBPARA.match(tr)
            if not m:
                self._append(tr)
                return
            tok = m.group(1)
            self.subclause = self._add("subparagraph", tok, f"{parent.path}({tok})", parent, tr[m.end():], status)
            self.subsub = None
            return
        if base in ("subsubclause", "subsubpara"):
            parent = self.subclause or self.clause
            if parent is None:
                return
            m = NUM_SUBSUB.match(tr)
            tok = m.group(1) if m else str(self.ordinal)
            rest = tr[m.end():] if m else tr
            self.subsub = self._add("clause", tok, f"{parent.path}({tok})", parent, rest, status)
            return
        if base in ("preamble", "paranoindt", "parawindt", "parawindt2", "equation"):
            self._append(tr)
            return
        self.issues.append(f"unhandled style {style}")
        self._append(t)

    def _defn_open(self) -> bool:
        if self.defn is None:
            return False
        last = self.provisions[-1]
        return last is self.defn or (last.parent_path or "").startswith(self.defn.path)

    def _child_of(self, parent: Provision, t: str, status: str) -> None:
        m = NUM_CLAUSE.match(t)
        tok = m.group(1) if m else str(self.ordinal)
        self._add("paragraph", tok, f"{parent.path}({tok})", parent, t[m.end():] if m else t, status)

    def _append(self, t: str) -> None:
        target = self.subsub or self.subclause or self.clause or self.sub or self.sec
        if target is None:
            self.ordinal += 1
            path = f"heading:{self.ordinal}"
            p = Provision(self.source_id, "heading", "", path, t[:80], text=t,
                          parent_path=self.part.path if self.part else None, status=IN_FORCE, ordinal=self.ordinal)
            self.provisions.append(p)
            return
        body, hist = _split_history(t)
        target.text = _clean(target.text + " " + body)
        if hist:
            target.history = (target.history + "; " + hist).strip("; ")


def extract(docx_path: Path, source_id: str) -> tuple[list[Provision], dict, list[str]]:
    d = docx.Document(str(docx_path))
    parser = OntarioParser(source_id)
    for p in d.paragraphs:
        parser.feed(p.style.name if p.style is not None else "Normal", p.text)
    # Tables (rare in e-Laws exports) are kept as plain rows attached as headings for search.
    for ti, table in enumerate(d.tables):
        for ri, row in enumerate(table.rows):
            cells = [normalize_ws(c.text) for c in row.cells]
            line = " | ".join(c for c in cells if c)
            if line and line != "Français" and "CONTENTS" not in line:
                parser.ordinal += 1
                path = f"table:{ti + 1}:{ri + 1}"
                parser.provisions.append(Provision(source_id, "table-row", str(ri + 1), path, f"Table {ti + 1}, row {ri + 1}",
                                                   text=line, status=IN_FORCE, ordinal=parser.ordinal))
    return parser.provisions, parser.meta, parser.issues
