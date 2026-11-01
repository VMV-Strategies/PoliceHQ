"""Seed (or refresh) the curated source registry from an inventory.

Metadata is established from document content (cover pages, e-Laws banners,
embedded document properties, by-law numbers printed in the text). Where the
only evidence is an upload filename, the field is marked as such and
"Not verified". Verification against official publishers is a separate step
(see update_check.py) and is never implied here.

The registry is committed to the repository (it contains metadata only, no
legal text). Existing manual edits are preserved on refresh: an existing
entry's fields win unless they are empty.
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path

from .util import read_json, slug, write_json

NV = "Not verified"
UNKNOWN = "Unknown"

ABBREVIATIONS = {
    "Criminal Code": ["CC", "Cr. Code"],
    "Controlled Drugs and Substances Act": ["CDSA"],
    "Youth Criminal Justice Act": ["YCJA"],
    "Immigration and Refugee Protection Act": ["IRPA"],
    "Proceeds of Crime (Money Laundering) and Terrorist Financing Act": ["PCMLTFA"],
    "Canada Evidence Act": ["CEA"],
    "Canadian Victims Bill of Rights": ["CVBR"],
    "Sex Offender Information Registration Act": ["SOIRA"],
    "Highway Traffic Act": ["HTA"],
    "Provincial Offences Act": ["POA"],
    "Compulsory Automobile Insurance Act": ["CAIA"],
    "Community Safety and Policing Act, 2019": ["CSPA"],
    "Mental Health Act": ["MHA"],
    "Child, Youth and Family Services Act, 2017": ["CYFSA"],
    "Liquor Licence and Control Act, 2019": ["LLCA"],
    "Freedom of Information and Protection of Privacy Act": ["FIPPA"],
    "Municipal Freedom of Information and Protection of Privacy Act": ["MFIPPA"],
    "Personal Health Information Protection Act, 2004": ["PHIPA"],
    "Health Care Consent Act, 1996": ["HCCA"],
    "Substitute Decisions Act, 1992": ["SDA"],
    "Residential Tenancies Act, 2006": ["RTA"],
    "Family Law Act": ["FLA"],
    "Children's Law Reform Act": ["CLRA"],
    "Children’s Law Reform Act": ["CLRA"],
    "Provincial Animal Welfare Services Act, 2019": ["PAWS Act"],
    "Dog Owners' Liability Act": ["DOLA"],
    "Dog Owners’ Liability Act": ["DOLA"],
    "Smoke-Free Ontario Act, 2017": ["SFOA"],
    "Special Investigations Unit Act, 2019": ["SIU Act"],
    "Towing and Storage Safety and Enforcement Act, 2021": ["TSSEA"],
    "Fire Protection and Prevention Act, 1997": ["FPPA"],
    "Trespass to Property Act": ["TPA"],
    "Cannabis Control Act, 2017": ["CCA"],
    "Municipal Act, 2001": ["MA"],
    "Missing Persons Act, 2018": ["MPA"],
}

FED_CITATION = re.compile(r"^(R\.S\.C\.,? \d{4}, c\. [\w\-]+(?: \(\d\w+ Supp\.\))?|S\.C\. \d{4}, c\. [\w\-]+(?:, s\. \d+)?|SOR/\d{2,4}-\d+|C\.R\.C\., c\. \d+)$")
BYLAW_NO = re.compile(r"By-?[Ll]aw\s+(?:Number\s+|No\.\s*|NUMBER\s+)?(\d{1,4}-\d{2,4})|BY-LAW (?:NUMBER |NO\. ?)?(\d{1,4}-\d{2,4})", re.I)
ROMAN_SCHED = re.compile(r"S\s?C\s?H\s?E\s?D\s?U\s?L\s?E\s+([IVXL ]+)\b")


def _federal(item: dict) -> dict:
    lines = item.get("cover_lines_english_column") or item.get("first_lines", [])
    title_lines, citation = [], None
    if "CONSOLIDATION" in lines:
        i = lines.index("CONSOLIDATION") + 1
        while i < len(lines) and not FED_CITATION.match(lines[i]) and not lines[i].startswith("Current to"):
            title_lines.append(lines[i])
            i += 1
        if i < len(lines) and FED_CITATION.match(lines[i]):
            citation = lines[i]
    title = " ".join(title_lines).strip()
    is_constitution = title.upper().startswith("THE CONSTITUTION ACTS")
    if is_constitution:
        title = "The Constitution Acts, 1867 to 1982"
    is_reg = bool(citation and (citation.startswith("SOR/") or citation.startswith("C.R.C.")))
    return {
        "title": title or UNKNOWN,
        "title_basis": "cover page of the PDF",
        "citation": citation or ("Constitution Act, 1867 (U.K.), 30 & 31 Vict., c. 3; Constitution Act, 1982, being Schedule B to the Canada Act 1982 (UK), 1982, c. 11"
                                 if is_constitution else UNKNOWN),
        "citation_basis": "cover page of the PDF" if citation else ("standard citation (editorial)" if is_constitution else UNKNOWN),
        "doc_type": "constitutional document" if is_constitution else ("regulation" if is_reg else "Act"),
        "level": "constitutional" if is_constitution else "federal",
        "jurisdiction_label": "Constitutional — Canada" if is_constitution else "Federal — Canada",
        "issuing_authority": ("Imperial Parliament (1867) and Parliament of the United Kingdom / Parliament of Canada (1982) — editorial description"
                              if is_constitution else ("Government of Canada (regulation); making authority not recorded" if is_reg
                                                       else "Parliament of Canada")),
        "territorial_application": "Canada",
        "publisher_status": "publisher-issued (Justice Laws Website consolidation PDF)",
        "consolidation_current_to": item.get("current_to") or UNKNOWN,
        "last_amended": item.get("last_amended_on") or ("Not stated in document" if is_constitution else UNKNOWN),
        "language_handling": "Bilingual two-column PDF; English (left column) extracted; French preserved in original only",
    }


def _ontario(item: dict, meta: dict | None) -> dict:
    emb = item.get("embedded_title") or ""
    subj = item.get("embedded_subject") or ""
    is_reg = "O. Reg." in emb
    title, citation = UNKNOWN, UNKNOWN
    m = re.match(r"^(.*?), ((?:R\.S\.O\.|S\.O\.) .*)$", emb)
    if m:
        title, citation = m.group(1).strip(), m.group(2).strip()
    if is_reg:
        m2 = re.match(r"^(.*?) - (O\. Reg\. \d+/\d+)", emb)
        if m2:
            citation = m2.group(2)
            parent = m2.group(1).strip().title().replace(", 2019", ", 2019")
            title = (subj.title() if subj else citation)
            title = re.sub(r"\s+-\s+", " — ", title)
    out = {
        "title": title,
        "title_basis": "embedded document title property of the e-Laws Word file",
        "citation": citation,
        "citation_basis": "embedded document title property of the e-Laws Word file",
        "doc_type": "regulation" if is_reg else "Act",
        "level": "provincial",
        "jurisdiction_label": "Provincial — Ontario",
        "issuing_authority": "Lieutenant Governor in Council / Ontario (regulation); making authority not recorded" if is_reg
        else "Legislative Assembly of Ontario",
        "territorial_application": "Ontario",
        "publisher_status": "publisher-issued (Ontario e-Laws Word export)",
        "consolidation_period": item.get("consolidation_period") or UNKNOWN,
        "last_amended": item.get("last_amendment") or UNKNOWN,
        "language_handling": "English version file (e-Laws '_e'); French version not supplied",
    }
    return out


def _municipal(item: dict) -> dict:
    lines = item.get("first_lines", [])
    head = " / ".join(lines[:8])
    markers = item.get("municipal_markers_in_text", [])
    name = item["original_filename"]
    rec: dict = {"level": "municipal", "doc_type": "by-law", "territorial_application": UNKNOWN,
                 "language_handling": "English"}
    bylaw_no = None
    for l in lines[:8]:
        m = BYLAW_NO.search(l)
        if m:
            bylaw_no = m.group(1) or m.group(2)
            break
    rec["bylaw_number"] = bylaw_no or UNKNOWN
    if item.get("reference_conversion"):
        rec["publisher_status"] = "reference conversion (not a publisher-issued PDF; amendment completeness not certified)"
        rec["reference_conversion_retrieved"] = item.get("reference_conversion_retrieved")
        rec["reference_conversion_stated_source"] = item.get("reference_conversion_stated_source")
    else:
        rec["publisher_status"] = "municipal publication (PDF as supplied; publisher not verified)"
    muni = None
    basis = ""
    if "REGIONAL MUNICIPALITY OF PEEL" in head.upper() or "Region of Peel" in head or \
            (item.get("reference_conversion") and "Peel Region" in (item.get("reference_conversion_stated_source") or "peelregion")):
        muni, basis = "peel", "issuing body named in document text"
    elif re.search(r"BY-LAW NO\. 93-93|By-?law 93-93", head, re.I):
        muni, basis = "brampton", ("by-law number 93-93 printed on the schedule; the consolidated text of By-law 93-93 "
                                   "names the City of Brampton")
        rec["parent_bylaw"] = "93-93"
    elif re.search(r"THE TRAFFIC BY-LAW|^TRAFFIC BY-LAW|SCHEDULE 25 TO BY-LAW", head) and "MISSISSAUGA" not in head.upper():
        muni, basis = "mississauga", ("schedule headed 'The Traffic By-law' with numbered schedules matching "
                                      "Mississauga Traffic By-law 0555-2000; municipality not printed on the schedule")
        rec["parent_bylaw"] = "0555-2000"
    elif "CITY OF BRAMPTON" in head.upper() or (markers and "Brampton" in markers and "Mississauga" not in markers):
        muni, basis = "brampton", "City of Brampton named in document text"
    elif "CITY OF MISSISSAUGA" in head.upper() or (markers and "Mississauga" in markers and "Brampton" not in markers):
        muni, basis = "mississauga", "City of Mississauga named in document text"
    rec["municipality"] = muni or UNKNOWN
    rec["municipality_basis"] = basis or "not established from document text"
    labels = {"peel": "Municipal — Peel Region", "brampton": "Municipal — Brampton", "mississauga": "Municipal — Mississauga"}
    rec["jurisdiction_label"] = labels.get(muni, "Municipal — jurisdiction not verified")
    rec["issuing_authority"] = {"peel": "Council of The Regional Municipality of Peel",
                                "brampton": "Council of The Corporation of the City of Brampton",
                                "mississauga": "Council of The Corporation of the City of Mississauga"}.get(muni, UNKNOWN)
    rec["territorial_application"] = {"peel": "Regional Municipality of Peel (regional jurisdiction as stated in the by-law)",
                                      "brampton": "City of Brampton", "mississauga": "City of Mississauga"}.get(muni, UNKNOWN)
    # Title from document text.
    title = None
    if rec.get("parent_bylaw"):
        sm = ROMAN_SCHED.search(head.upper()) or re.search(r"SCHEDULE\s+(\d+[A-Z]?)", head.upper())
        sched = sm.group(1).replace(" ", "") if sm else UNKNOWN
        idx = next((i for i, l in enumerate(lines) if re.search(r"S\s?C\s?H\s?E\s?D\s?U\s?L\s?E", l.upper())), None)
        sname = lines[idx + 1] if idx is not None and idx + 1 < len(lines) else ""
        if sname.upper().startswith("BY-LAW") or sname.upper().startswith("REVISION") or sname.upper().startswith("PAGE"):
            sname = ""
        base = "Brampton Traffic By-law 93-93" if rec["parent_bylaw"] == "93-93" else "Mississauga Traffic By-law 0555-2000"
        title = f"{base} — Schedule {sched}" + (f": {sname.title()}" if sname else "")
        rec["doc_type"] = "by-law schedule"
        rec["schedule_number"] = sched
    else:
        for i, l in enumerate(lines[:8]):
            if re.search(r"by-?law", l, re.I) and not l.upper().startswith(("THE CORPORATION", "BY-LAW /", "REFERENCE")) \
                    and not l.startswith(("Converted from", "(Amended", "(as amended", "(As amended")) and len(l) < 120:
                t = l
                if re.fullmatch(r"(?i)by-?law\s+(number\s+|no\.\s*)?[\d-]+", t.strip()) and i > 0 and \
                        not lines[i - 1].upper().startswith(("THE CORPORATION", "OFFICE CONSOLIDATION")):
                    t = lines[i - 1] + " " + t
                title = t.strip("() ")
                break
    if item.get("reference_conversion"):
        m = re.search(r"By-law number (\d+-\d+)", " ".join(lines))
        rec["bylaw_number"] = m.group(1) if m else rec["bylaw_number"]
        title = None
        for l in lines:
            if l.startswith("A by-law") or l.startswith("A By-law"):
                break
    if not title:
        title = re.sub(r"\.pdf$", "", name).replace("_", " ")
        rec["title_basis"] = "upload filename (not verified)"
    else:
        rec["title_basis"] = "document text"
    rec["title"] = title
    rec["citation"] = (f"By-law {rec['bylaw_number']}" if rec["bylaw_number"] != UNKNOWN else UNKNOWN)
    rec["citation_basis"] = "by-law number printed in document" if rec["bylaw_number"] != UNKNOWN else UNKNOWN
    return rec


def _source_id(rec: dict, item: dict) -> str:
    lvl = rec.get("level")
    if lvl in ("federal", "constitutional"):
        if rec["title"].startswith("The Constitution Acts"):
            return "ca-constitution-acts-1867-1982"
        return "ca-" + slug(rec["title"])[:60]
    if lvl == "provincial":
        if rec["doc_type"] == "regulation":
            return "on-" + slug(rec["citation"])
        return "on-" + slug(rec["title"])[:60]
    muni = rec.get("municipality", "unknown")
    if rec.get("parent_bylaw"):
        return f"{muni}-bylaw-{rec['parent_bylaw']}-sched-{slug(rec.get('schedule_number', 'x'))}"
    num = rec.get("bylaw_number", UNKNOWN)
    base = f"{muni}-bylaw-{num}" if num != UNKNOWN else f"{muni}-{slug(rec['title'])[:40]}"
    return base


def seed(inventory: dict, existing: dict | None, converted_meta: dict | None = None) -> dict:
    existing_by_hash = {v["sha256"]: (k, v) for k, v in (existing or {}).get("sources", {}).items()}
    sources: dict[str, dict] = {}
    duplicates: list[dict] = []
    seen: dict[str, str] = {}
    for item in inventory["items"]:
        if item["format"] not in ("pdf", "doc", "docx"):
            continue
        h = item["sha256"]
        if h in seen:
            duplicates.append({"original_filename": item["original_filename"], "sha256": h, "duplicate_of": seen[h]})
            continue
        if item["format"] == "pdf" and "Minister of Justice" in str(item.get("publisher_banner")):
            rec = _federal(item)
        elif item["format"] in ("doc", "docx"):
            rec = _ontario(item, None)
        else:
            rec = _municipal(item)
        sid = _source_id(rec, item)
        base_sid, n = sid, 2
        while sid in sources:
            sid = f"{base_sid}-{n}"
            n += 1
        rec.update({
            "source_id": sid,
            "original_filename": item["original_filename"],
            "sha256": h,
            "bytes": item["bytes"],
            "format": item["format"],
            "pages": item.get("pages"),
            "abbreviations": ABBREVIATIONS.get(rec.get("title", ""), []),
            "official_url": None,
            "official_url_status": NV,
            "retrieval_date": UNKNOWN,
            "verification_date": None,
            "verification_status": NV,
            "editorial_review_status": "imported",
            "enforcement_responsibility": "Not recorded (see the source's own enforcement provisions)",
            "relationships": [],
        })
        if h in existing_by_hash:
            old_sid, old = existing_by_hash[h]
            for k, v in old.items():
                if v not in (None, "", [], UNKNOWN) or k not in rec:
                    rec[k] = v
            sid = old_sid
            rec["source_id"] = sid
        sources[sid] = rec
        seen[h] = sid
    return {"schema": "phq-source-registry/1", "sources": sources, "duplicates": duplicates}


REG_PARENTS = {
    # regulation source_id -> (parent source_id, basis)
    "on-o-reg-400-23": ("on-community-safety-and-policing-act-2019", "enabling Act named in the regulation's title block"),
    "ca-contraventions-regulations": ("ca-contraventions-act", "enabling Act named in the regulation's text"),
    "ca-constitution-acts-1867-1982": (None, ""),
    "ca-small-vessel-regulations": ("ca-canada-shipping-act-2001", "enabling Act named in the regulation's text"),
    "ca-vessel-operation-restriction-regulations": ("ca-canada-shipping-act-2001", "enabling Act named in the regulation's text"),
    "ca-explosives-regulations-2013": ("ca-explosives-act", "enabling Act named in the regulation's text"),
}


def apply_overrides(reg: dict, overrides: dict) -> dict:
    by_hash = {v["sha256"]: k for k, v in reg["sources"].items()}
    new_sources: dict[str, dict] = {}
    for sid, rec in reg["sources"].items():
        ov = overrides.get(rec["sha256"], {})
        for k, v in ov.items():
            if not k.startswith("_"):
                rec[k] = v
        if ov:
            rec["metadata_overrides_applied"] = sorted(k for k in ov if not k.startswith("_"))
        new_sources[rec["source_id"]] = rec
    reg["sources"] = new_sources
    for d in reg["duplicates"]:
        old = d["duplicate_of"]
        for sid, rec in new_sources.items():
            if rec["sha256"] == d["sha256"]:
                d["duplicate_of"] = sid
    return reg


def compute_relationships(reg: dict) -> None:
    S = reg["sources"]
    for sid, rec in S.items():
        rels = []
        parent = rec.get("parent_bylaw")
        muni = rec.get("municipality")
        if parent:
            parent_id = f"{muni}-bylaw-{parent}"
            kind = "map-of" if rec.get("doc_type", "").startswith("map") else "schedule-of"
            if parent_id in S and parent_id != sid:
                rels.append({"relation": kind, "target": parent_id,
                             "basis": rec.get("municipality_basis", ""),
                             "verified": bool(rec.get("attribution_verified", True)) and kind == "schedule-of"})
        if rec.get("doc_type") == "sign (image)":
            rels.append({"relation": "sign-for", "target": "peel-bylaw-49-2019", "basis": "by-law number printed on the sign",
                         "verified": False})
        if sid == "peel-bylaw-49-2019-original":
            rels.append({"relation": "original-enactment-of", "target": "peel-bylaw-49-2019",
                         "basis": "same by-law number; this file is the as-enacted text", "verified": False})
        if sid in REG_PARENTS and REG_PARENTS[sid][0] in S:
            rels.append({"relation": "regulation-under", "target": REG_PARENTS[sid][0], "basis": REG_PARENTS[sid][1],
                         "verified": False})
        rec["relationships"] = rels


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--inventory", required=True, type=Path)
    ap.add_argument("--registry", required=True, type=Path)
    ap.add_argument("--overrides", type=Path, default=None)
    ap.add_argument("--fresh", action="store_true", help="ignore the existing registry file")
    a = ap.parse_args()
    existing = read_json(a.registry) if a.registry.exists() and not a.fresh else None
    reg = seed(read_json(a.inventory), existing)
    if a.overrides and a.overrides.exists():
        reg = apply_overrides(reg, read_json(a.overrides)["overrides"])
    compute_relationships(reg)
    write_json(a.registry, reg)
    print(f"{len(reg['sources'])} sources, {len(reg['duplicates'])} duplicate uploads -> {a.registry}")


if __name__ == "__main__":
    main()
