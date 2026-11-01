"""Content-package creation, signing and verification.

Container format (".phqpkg"), designed so the iPhone app can read it with
Foundation only (no third-party unzip library):

    bytes 0..7    magic  b"PHQPKG01"
    bytes 8..15   uint64 big-endian: length N of the index JSON
    bytes 16..    index JSON (UTF-8): {"entries": [{"path", "offset", "length", "size",
                                          "compression": "none"|"deflate-raw"}]}
    then          entry payloads at the stated offsets (relative to the payload start)

The index is NOT trusted. Trust comes from two entries:
    manifest.json   — package metadata and, for every other file, its SHA-256 and size
    manifest.sig    — Ed25519 signature (base64) over the exact bytes of manifest.json

Verification (both here and in the app): signature valid for a trusted public key ->
schema/app compatibility -> every listed file present with matching size and SHA-256
-> no unlisted files. A valid signature shows the package came from the holder of the
signing key and was not altered. It says nothing about legal correctness.

Usage:
    python -m phq_ingest.package keygen --out-private ~/phq-keys/signing.key --out-public content/trusted_keys/dev.pub
    python -m phq_ingest.package build --src build/package --key ~/phq-keys/signing.key --key-id dev-2026 \
        --version 2026.11.01 --min-app 1.0 --out dist/PoliceHQ-2026.11.01.phqpkg
    python -m phq_ingest.package verify --pkg dist/....phqpkg --public content/trusted_keys/dev.pub
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import struct
import zlib
from datetime import datetime, timezone
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey

MAGIC = b"PHQPKG01"
FORMAT_VERSION = 1
COMPRESS_SUFFIXES = {".sqlite", ".json", ".txt", ".md", ".doc", ".html"}


def keygen(out_private: Path, out_public: Path) -> None:
    key = Ed25519PrivateKey.generate()
    out_private.parent.mkdir(parents=True, exist_ok=True)
    out_private.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                              serialization.NoEncryption()))
    out_private.chmod(0o600)
    raw_pub = key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    out_public.parent.mkdir(parents=True, exist_ok=True)
    out_public.write_text(base64.b64encode(raw_pub).decode() + "\n")


def _load_private(path: Path) -> Ed25519PrivateKey:
    key = serialization.load_pem_private_key(path.read_bytes(), password=None)
    if not isinstance(key, Ed25519PrivateKey):
        raise SystemExit("signing key is not Ed25519")
    return key


def _deflate_raw(data: bytes) -> bytes:
    c = zlib.compressobj(level=9, wbits=-15)
    return c.compress(data) + c.flush()


def build(src: Path, key_path: Path, key_id: str, version: str, min_app: str, out: Path,
          description: str = "") -> dict:
    files = sorted(p for p in src.rglob("*") if p.is_file() and p.name not in ("manifest.json", "manifest.sig"))
    entries_meta = []
    for p in files:
        rel = p.relative_to(src).as_posix()
        data = p.read_bytes()
        entries_meta.append({"path": rel, "size": len(data), "sha256": hashlib.sha256(data).hexdigest()})
    info = {}
    db = src / "content.sqlite"
    if db.exists():
        import sqlite3
        con = sqlite3.connect(db)
        info = dict(con.execute("SELECT key, value FROM package_info").fetchall())
        con.close()
    manifest = {
        "format": "phq-content-package",
        "format_version": FORMAT_VERSION,
        "package_version": version,
        "schema_version": int(info.get("schema_version", "1")),
        "min_app_version": min_app,
        "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "signing_key_id": key_id,
        "description": description,
        "content_info": info,
        "files": entries_meta,
        "statement": ("A valid signature establishes only that this package was produced by the holder of the signing key "
                      "and has not been altered since signing. It does not establish legal correctness, currency or review."),
    }
    manifest_bytes = json.dumps(manifest, ensure_ascii=False, indent=1, sort_keys=True).encode("utf-8")
    sig = _load_private(key_path).sign(manifest_bytes)
    payloads: list[tuple[str, bytes, int, str]] = [
        ("manifest.json", manifest_bytes, len(manifest_bytes), "none"),
        ("manifest.sig", base64.b64encode(sig) + b"\n", len(base64.b64encode(sig)) + 1, "none"),
    ]
    for p in files:
        data = p.read_bytes()
        if p.suffix.lower() in COMPRESS_SUFFIXES:
            comp = _deflate_raw(data)
            payloads.append((p.relative_to(src).as_posix(), comp, len(data), "deflate-raw"))
        else:
            payloads.append((p.relative_to(src).as_posix(), data, len(data), "none"))
    index = {"entries": []}
    offset = 0
    for path, blob, size, comp in payloads:
        index["entries"].append({"path": path, "offset": offset, "length": len(blob), "size": size, "compression": comp})
        offset += len(blob)
    index_bytes = json.dumps(index, separators=(",", ":")).encode("utf-8")
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(out.suffix + ".tmp")
    with open(tmp, "wb") as f:
        f.write(MAGIC)
        f.write(struct.pack(">Q", len(index_bytes)))
        f.write(index_bytes)
        for _, blob, _, _ in payloads:
            f.write(blob)
    tmp.replace(out)
    return manifest


class VerificationError(Exception):
    pass


def read_container(pkg: Path) -> tuple[dict, bytes, int]:
    raw = pkg.read_bytes()
    if raw[:8] != MAGIC:
        raise VerificationError("not a Police HQ package (bad magic)")
    (n,) = struct.unpack(">Q", raw[8:16])
    if n > 50_000_000 or 16 + n > len(raw):
        raise VerificationError("corrupt index length")
    index = json.loads(raw[16:16 + n].decode("utf-8"))
    return index, raw, 16 + n


def extract_entry(raw: bytes, base: int, e: dict) -> bytes:
    start = base + int(e["offset"])
    end = start + int(e["length"])
    if start < base or end > len(raw):
        raise VerificationError(f"entry out of bounds: {e.get('path')}")
    blob = raw[start:end]
    if e["compression"] == "deflate-raw":
        d = zlib.decompressobj(wbits=-15)
        data = d.decompress(blob) + d.flush()
    elif e["compression"] == "none":
        data = blob
    else:
        raise VerificationError(f"unknown compression {e['compression']}")
    if len(data) != int(e["size"]):
        raise VerificationError(f"size mismatch for {e['path']}")
    return data


def verify(pkg: Path, public_keys: list[bytes], supported_schema: int = 1, extract_to: Path | None = None) -> dict:
    index, raw, base = read_container(pkg)
    entries = {e["path"]: e for e in index["entries"]}
    for required in ("manifest.json", "manifest.sig"):
        if required not in entries:
            raise VerificationError(f"missing {required}")
    for e in index["entries"]:
        p = e["path"]
        if p.startswith("/") or ".." in Path(p).parts:
            raise VerificationError(f"unsafe path {p}")
    manifest_bytes = extract_entry(raw, base, entries["manifest.json"])
    sig = base64.b64decode(extract_entry(raw, base, entries["manifest.sig"]).strip())
    ok = False
    for pk in public_keys:
        try:
            Ed25519PublicKey.from_public_bytes(pk).verify(sig, manifest_bytes)
            ok = True
            break
        except Exception:
            continue
    if not ok:
        raise VerificationError("signature not valid for any trusted key")
    manifest = json.loads(manifest_bytes)
    if manifest.get("format") != "phq-content-package" or manifest.get("format_version") != FORMAT_VERSION:
        raise VerificationError("unsupported package format")
    if manifest.get("schema_version") != supported_schema:
        raise VerificationError(f"incompatible schema {manifest.get('schema_version')}")
    listed = {f["path"]: f for f in manifest["files"]}
    extra = set(entries) - set(listed) - {"manifest.json", "manifest.sig"}
    if extra:
        raise VerificationError(f"unlisted files present: {sorted(extra)[:5]}")
    for path, f in listed.items():
        if path not in entries:
            raise VerificationError(f"missing file {path}")
        data = extract_entry(raw, base, entries[path])
        if len(data) != f["size"] or hashlib.sha256(data).hexdigest() != f["sha256"]:
            raise VerificationError(f"hash mismatch for {path}")
        if extract_to is not None:
            dest = extract_to / path
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(data)
    if extract_to is not None:
        (extract_to / "manifest.json").write_bytes(manifest_bytes)
    return manifest


def _read_pub(path: Path) -> bytes:
    return base64.b64decode(path.read_text().strip())


def main() -> None:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    k = sub.add_parser("keygen")
    k.add_argument("--out-private", type=Path, required=True)
    k.add_argument("--out-public", type=Path, required=True)
    b = sub.add_parser("build")
    b.add_argument("--src", type=Path, required=True)
    b.add_argument("--key", type=Path, required=True)
    b.add_argument("--key-id", required=True)
    b.add_argument("--version", required=True)
    b.add_argument("--min-app", default="1.0")
    b.add_argument("--description", default="")
    b.add_argument("--out", type=Path, required=True)
    v = sub.add_parser("verify")
    v.add_argument("--pkg", type=Path, required=True)
    v.add_argument("--public", type=Path, nargs="+", required=True)
    v.add_argument("--extract-to", type=Path, default=None)
    a = ap.parse_args()
    if a.cmd == "keygen":
        keygen(a.out_private, a.out_public)
        print(f"private key -> {a.out_private} (keep outside the repository)\npublic key  -> {a.out_public}")
    elif a.cmd == "build":
        m = build(a.src, a.key, a.key_id, a.version, a.min_app, a.out, a.description)
        print(f"built {a.out} ({len(m['files'])} files, package {m['package_version']})")
    else:
        m = verify(a.pkg, [_read_pub(p) for p in a.public], extract_to=a.extract_to)
        print(f"OK: package {m['package_version']} signed by key '{m['signing_key_id']}', {len(m['files'])} files verified")


if __name__ == "__main__":
    main()
