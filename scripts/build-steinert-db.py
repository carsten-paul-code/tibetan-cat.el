#!/usr/bin/env python3
"""Build a SQLite database from Christian Steinert's Tibetan dictionary sources.

Input:  steinert-src/_input/dictionaries/public/*
Output: data/dictionaries/steinert.db

Schema:
    entries(id INTEGER PK,
            wylie TEXT,         -- EWTS wylie key (lowercase, spaces preserved)
            wylie_norm TEXT,    -- collapsed key for indexing (no leading/trailing ws)
            gloss TEXT,         -- raw entry text after the '|'
            sanskrit TEXT,      -- extracted Sanskrit (IAST) if any, else NULL
            source TEXT)        -- originating file name

Indexes on wylie_norm.

The Emacs side converts Tibetan Unicode -> wylie with `tibetan-to-wylie`
and queries this DB. This avoids the need to re-implement EWTS in Python.

Per-source Sanskrit extraction:

 * Sanskrit-as-gloss files: the entire gloss IS the Sanskrit equivalent(s).
     21-Mahavyutpatti-Skt, 22-Yoghacharabhumi-glossary, 46-84000Skt,
     49-LokeshChandraSkt, 50-NegiSkt (Sanskrit interleaved; still store),
     63-Mahavyutpatti-Scan-1989 (just page numbers — skip),
     64-sgra-sbyor-bam-po-gnyis-pa (just page numbers — skip),
     15-Hopkins-Skt1992, 15-Hopkins-Skt2015 (marker codes + IAST)

 * Sanskrit-embedded files: look for [Skt.]/[Skt]/(Skt.)/"sanskrit:" markers.
     Most others.

Usage:
    python3 scripts/build-steinert-db.py

Run from repo root. Writes data/dictionaries/steinert.db.
"""
from __future__ import annotations
import os
import re
import sys
import sqlite3
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SRC_DIR   = REPO_ROOT / "steinert-src" / "_input" / "dictionaries" / "public"
OUT_DB    = REPO_ROOT / "data" / "dictionaries" / "steinert.db"

# Files whose gloss is (essentially) the Sanskrit equivalent of the headword.
SANSKRIT_AS_GLOSS = {
    "21-Mahavyutpatti-Skt",
    "22-Yoghacharabhumi-glossary",
    "46-84000Skt",
    "49-LokeshChandraSkt",
    "15-Hopkins-Skt1992",
    "15-Hopkins-Skt2015",
}

# Files with mostly-Sanskrit glosses but noisy (full articles, citations).
# Keep them but don't try to "clean" — Emacs displays the raw text on demand.
SANSKRIT_RICH_NOISY = {
    "50-NegiSkt",
}

# Files with only scan-page numbers as glosses — skip the source entirely
# (headwords are redundant with other sources; page numbers aren't useful
# in-tool without the scans mounted).
SKIP_SOURCES = {
    "63-Mahavyutpatti-Scan-1989",
    "64-sgra-sbyor-bam-po-gnyis-pa",
    "65-ChandraDas_Scan",
    "66-Jaeschke_Scan",
}

# Regexes for extracting Sanskrit from general glosses.
SKT_PATTERNS = [
    # Bracketed markers: [Skt.]foo  [Skt] foo   (Hopkins convention)
    re.compile(r"\[Skt\.?\]\s*([^\[\];,.]+)", re.IGNORECASE),
    # Parenthesised: (Skt. foo)  (Skt: foo)
    re.compile(r"\(Skt\.?[:\s]+([^)]+)\)", re.IGNORECASE),
    # Inline "Sanskrit: foo" / "Skt.: foo"
    re.compile(r"\b[Ss]anskrit:\s*([A-Za-zĀ-ž\u0100-\u024f'\- ]+)"),
    re.compile(r"\bSkt\.?:\s*([A-Za-zĀ-ž\u0100-\u024f'\- ]+)"),
]

# Marker/code stripper for Hopkins-Skt files: entries look like
#   [C]vā; [C]athavā-api
# We keep the IAST forms, drop the bracketed source codes.
HOPKINS_MARKER_RE = re.compile(r"\[[A-Z]{1,4}\]")


def classify_sanskrit(source: str, gloss: str) -> str | None:
    """Return extracted Sanskrit string or None."""
    if not gloss:
        return None
    if source in SANSKRIT_AS_GLOSS:
        cleaned = HOPKINS_MARKER_RE.sub("", gloss).strip()
        # strip leading semicolons / whitespace left from marker removal
        cleaned = re.sub(r"^[\s;]+", "", cleaned)
        return cleaned or None
    if source in SANSKRIT_RICH_NOISY:
        # NegiSkt — keep the raw article; Emacs renderer trims for display.
        return gloss
    # General case: scan for [Skt] etc.
    hits = []
    for pat in SKT_PATTERNS:
        for m in pat.finditer(gloss):
            hits.append(m.group(1).strip(" ;.,"))
    if hits:
        # dedupe preserving order
        seen = set()
        out = []
        for h in hits:
            if h and h not in seen:
                seen.add(h)
                out.append(h)
        return "; ".join(out)
    return None


def iter_entries(src_dir: Path):
    """Yield (wylie, gloss, source) for every valid line in every file."""
    for fp in sorted(src_dir.iterdir()):
        if not fp.is_file():
            continue
        name = fp.name
        if name in SKIP_SOURCES:
            continue
        try:
            with fp.open("r", encoding="utf-8", errors="replace") as fh:
                for raw in fh:
                    line = raw.rstrip("\n").rstrip("\r")
                    if not line or line.startswith("#"):
                        continue
                    if "|" not in line:
                        continue
                    wylie, _, gloss = line.partition("|")
                    wylie = wylie.strip()
                    gloss = gloss.strip()
                    if not wylie or not gloss:
                        continue
                    yield wylie, gloss, name
        except OSError as e:
            print(f"  !! cannot read {fp}: {e}", file=sys.stderr)


def main() -> int:
    if not SRC_DIR.is_dir():
        print(f"ERROR: source dir not found: {SRC_DIR}", file=sys.stderr)
        print("Clone Christian Steinert's repo into steinert-src/ first.", file=sys.stderr)
        return 2

    OUT_DB.parent.mkdir(parents=True, exist_ok=True)
    if OUT_DB.exists():
        OUT_DB.unlink()

    conn = sqlite3.connect(OUT_DB)
    cur = conn.cursor()
    cur.execute("PRAGMA journal_mode = OFF")
    cur.execute("PRAGMA synchronous = OFF")
    cur.execute("""
        CREATE TABLE entries (
            id INTEGER PRIMARY KEY,
            wylie TEXT NOT NULL,
            wylie_norm TEXT NOT NULL,
            gloss TEXT NOT NULL,
            sanskrit TEXT,
            source TEXT NOT NULL
        )
    """)

    batch = []
    total = 0
    with_skt = 0
    per_source: dict[str, int] = {}

    print(f"Reading {SRC_DIR} ...")
    for wylie, gloss, src in iter_entries(SRC_DIR):
        skt = classify_sanskrit(src, gloss)
        norm = wylie.lower().strip()
        batch.append((wylie, norm, gloss, skt, src))
        per_source[src] = per_source.get(src, 0) + 1
        total += 1
        if skt:
            with_skt += 1
        if len(batch) >= 10000:
            cur.executemany(
                "INSERT INTO entries(wylie,wylie_norm,gloss,sanskrit,source) "
                "VALUES (?,?,?,?,?)", batch)
            batch.clear()
    if batch:
        cur.executemany(
            "INSERT INTO entries(wylie,wylie_norm,gloss,sanskrit,source) "
            "VALUES (?,?,?,?,?)", batch)

    print("Indexing ...")
    cur.execute("CREATE INDEX idx_wylie_norm ON entries(wylie_norm)")
    cur.execute("CREATE INDEX idx_source     ON entries(source)")
    cur.execute(
        "CREATE INDEX idx_wylie_norm_has_skt ON entries(wylie_norm) "
        "WHERE sanskrit IS NOT NULL")
    conn.commit()
    conn.close()

    size_mb = OUT_DB.stat().st_size / (1024 * 1024)
    print(f"\nWrote {OUT_DB}  ({size_mb:.1f} MB, {total:,} entries, "
          f"{with_skt:,} with Sanskrit)")
    print("Per source:")
    for src, n in sorted(per_source.items()):
        print(f"  {src:<45} {n:>7,}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
