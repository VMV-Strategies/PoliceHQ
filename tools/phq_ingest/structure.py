"""Shared structured-provision model and tree builder.

Hierarchy: Document -> Part -> section -> subsection -> paragraph -> subparagraph -> clause.
Every provision keeps verbatim extracted text, its marginal note/headnote, its
in-force status and its amendment history separately, so editorial annotations
and not-yet-in-force amendments never merge into operative text.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from decimal import Decimal, InvalidOperation

ROMAN = re.compile(r"^(?=[ivxlc]+$)m{0,0}(c[md]|d?c{0,3})(x[cl]|l?x{0,3})(i[xv]|v?i{0,3})$")
KIND_ORDER = ["part", "section", "subsection", "paragraph", "subparagraph", "clause", "subclause"]

IN_FORCE = "in-force"
NOT_YET_IN_FORCE = "not-yet-in-force"
ANNOTATION = "annotation"
REPEALED = "repealed"
UNKNOWN = "unknown"


@dataclass
class Provision:
    source_id: str
    kind: str                     # part | heading | section | subsection | paragraph | subparagraph | clause | subclause | definition | schedule | page | note
    number: str                   # token as printed, e.g. "494", "(1)", "(a)"
    path: str                     # e.g. "494(1)(a)" ; parts "part:XVI" ; schedules "schedule:1"
    label: str                    # display label, e.g. "s. 494(1)(a)"
    heading: str = ""             # marginal note / headnote
    text: str = ""                # verbatim extracted text of this unit (excluding children)
    parent_path: str | None = None
    status: str = IN_FORCE
    history: str = ""             # amendment citations printed with the unit
    page_start: int | None = None
    page_end: int | None = None
    notes: list[str] = field(default_factory=list)
    ordinal: int = 0
    lines: list[str] = field(default_factory=list, repr=False)

    @property
    def provision_id(self) -> str:
        suffix = "" if self.status in (IN_FORCE, UNKNOWN, REPEALED) else f"@{self.status}"
        return f"{self.source_id}:{self.path}{suffix}"


def is_roman(token: str) -> bool:
    return bool(token) and bool(ROMAN.match(token))


def roman_to_int(token: str) -> int:
    vals = {"i": 1, "v": 5, "x": 10, "l": 50, "c": 100}
    total = 0
    prev = 0
    for ch in reversed(token):
        v = vals[ch]
        total = total - v if v < prev else total + v
        prev = max(prev, v)
    return total


def int_to_roman(n: int) -> str:
    out = ""
    for v, s in [(100, "c"), (90, "xc"), (50, "l"), (40, "xl"), (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")]:
        while n >= v:
            out += s
            n -= v
    return out


def next_letter(token: str) -> str | None:
    base = token.split(".")[0]
    if len(base) == 1 and base.isalpha() and base != "z":
        return chr(ord(base) + 1)
    return None


def section_decimal(token: str) -> Decimal | None:
    try:
        return Decimal(token)
    except InvalidOperation:
        return None


def dehyphenate_join(lines: list[str], vocabulary: set[str] | None = None) -> str:
    """Join wrapped lines. A trailing '-' between lowercase letters is removed when
    the joined word appears elsewhere in the document's vocabulary (or when no
    hyphenated form appears there). Compound words keep their hyphen."""
    out = ""
    for raw in lines:
        line = raw.strip()
        if not line:
            continue
        if not out:
            out = line
            continue
        m = re.search(r"([A-Za-z]+)-$", out)
        n = re.match(r"([a-z]+)", line)
        if m and n and out[-2].islower():
            joined = (m.group(1) + n.group(1)).lower()
            hyphenated = (m.group(1) + "-" + n.group(1)).lower()
            keep_hyphen = False
            if vocabulary is not None:
                if hyphenated in vocabulary and joined not in vocabulary:
                    keep_hyphen = True
            out = out + line if keep_hyphen else out[:-1] + line
        else:
            out = out + " " + line
    out = re.sub(r"\s+", " ", out).strip()
    out = collapse_letter_spacing(out, vocabulary)
    return out


_SPACED = re.compile(r"(?<![\w(])((?:[A-Za-z] )(?:[a-z] )*[a-z])(?![\w)])")


def collapse_letter_spacing(text: str, vocabulary: set[str] | None = None) -> str:
    """Undo letter-spaced words produced by some PDF text layers ("w i l l" -> "will").
    Sequences of single letters are joined only when the joined word occurs elsewhere
    in the same document (when a vocabulary is supplied), and never for a lone "a"."""
    def fix(m: re.Match) -> str:
        letters = m.group(1).split(" ")
        joined = "".join(letters)
        if all(l.lower() == "a" for l in letters):
            return m.group(1)
        if vocabulary is not None and joined.lower() not in vocabulary:
            return m.group(1)
        return joined
    return _SPACED.sub(fix, text)


def build_vocabulary(text: str) -> set[str]:
    return set(w.lower() for w in re.findall(r"[A-Za-z]+(?:-[A-Za-z]+)*", text))


def label_for(path: str, prefix: str = "s.") -> str:
    if path.startswith("part:"):
        return "Part " + path.split(":", 1)[1]
    if path.startswith("schedule:"):
        return "Schedule " + path.split(":", 1)[1]
    if path.startswith("page:"):
        return "Page " + path.split(":", 1)[1]
    if path.startswith("nif:") or path.startswith("rp:"):
        return path
    return f"{prefix} {path}"
