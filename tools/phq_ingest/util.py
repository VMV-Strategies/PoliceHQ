"""Small shared helpers. Standard library only."""
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import unicodedata
from pathlib import Path
from typing import Any


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def run(cmd: list[str], timeout: int = 600) -> str:
    """Run a command and return stdout as text (errors are tolerated, stderr dropped)."""
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=timeout)
    return res.stdout.decode("utf-8", errors="replace")


def pdf_page_count(path: Path) -> int:
    out = run(["pdfinfo", str(path)])
    m = re.search(r"^Pages:\s+(\d+)", out, re.M)
    return int(m.group(1)) if m else 0


def pdf_info(path: Path) -> dict[str, str]:
    out = run(["pdfinfo", str(path)])
    info: dict[str, str] = {}
    for line in out.splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            info[k.strip()] = v.strip()
    return info


def pdf_text(path: Path, first: int | None = None, last: int | None = None,
             crop: tuple[int, int, int, int] | None = None, layout: bool = False) -> str:
    cmd = ["pdftotext", "-enc", "UTF-8"]
    if first:
        cmd += ["-f", str(first)]
    if last:
        cmd += ["-l", str(last)]
    if crop:
        x, y, w, h = crop
        cmd += ["-x", str(x), "-y", str(y), "-W", str(w), "-H", str(h)]
    if layout:
        cmd.append("-layout")
    cmd += [str(path), "-"]
    return run(cmd)


def normalize_ws(text: str) -> str:
    text = unicodedata.normalize("NFC", text)
    text = text.replace(" ", " ").replace("\t", " ")
    text = re.sub(r"[    ]+", " ", text)
    return text.strip()


def slug(text: str) -> str:
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    text = re.sub(r"[^A-Za-z0-9]+", "-", text).strip("-").lower()
    return text or "x"


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=False)
        f.write("\n")
    os.replace(tmp, path)


def read_json(path: Path) -> Any:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


FRENCH_MARKERS = re.compile(
    r"\b(le|la|les|des|du|une|est|dans|pour|qui|aux|sont|toute|personne|paragraphe|alinéa|article)\b",
    re.I,
)
ENGLISH_MARKERS = re.compile(r"\b(the|and|of|to|shall|any|person|section|subsection|which|who)\b", re.I)


def language_ratio(text: str) -> tuple[int, int]:
    return len(ENGLISH_MARKERS.findall(text)), len(FRENCH_MARKERS.findall(text))
