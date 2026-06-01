#!/usr/bin/env python3
"""Prep a Wylie Yogācārabhūmi (or similar śāstra) source file into
the Milarepa-style segment structure expected by tibetan-cat.el.

Pipeline:
  1. Extract the `* Tibetan Text' body.
  2. For each blank-line-separated paragraph:
     a. Pull inline `[F:DNaM]' folio markers aside.
     b. Normalise OCR shad variants (`;;' → `//', `;' → `/').
     c. Split at `//' (double-shad) → one Wylie unit per segment.
     d. Convert each Wylie unit to Tibetan Unicode via pyewts.
  3. Emit `*** Segment N' headings (renumbered from 1) under the
     preserved `* Tibetan Text' section, attaching any folio
     markers the segment touched as a `:FOLIO: Dx..., Dy...'
     org property.
  4. Preserve: document-level `#+KEYWORD:' metadata, `* Document Info',
     and any trailing sections after `* Tibetan Text'.

Dependencies:
  pip3 install --break-system-packages --user --no-build-isolation pyewts

Usage:
  doc-prep/tibetan-ybh-prep.py path/to/source.org           # stdout
  doc-prep/tibetan-ybh-prep.py path/to/source.org --in-place

Provenance:
  Written 2026-04-20 to prepare the Gotrapaṭala chapter of the
  Bodhisattvabhūmi (D4037 fols. 1a-7a) for the Tibetisch IV class.
  Input was Wylie with Derge folio markers inline; output is
  Tibetan Unicode in the `* Tibetan Text → *** Sentence → **** Segment'
  layout used by Milarepa-prepared.org.
"""

import pyewts
import re
import sys
import argparse
from pathlib import Path


FOLIO_RE = re.compile(r"\[F:D(\d+[ab]\d+)\]")

# Single and double shad variants (order matters: match `;;`/`//` before `;`/`/`).
DOUBLE_SHAD = "//"
SINGLE_SHAD = "/"


def normalise_shads(text: str) -> str:
    """Normalise `;;' → `//' and standalone `;' → `/' (OCR variants)."""
    # `;;` → `//` first (longest match)
    text = text.replace(";;", "//")
    # Standalone `;` in the middle of text → `/`
    text = text.replace(";", "/")
    return text


def extract_folios(text: str) -> tuple[str, list[str]]:
    """Remove `[F:DNaM]' markers from TEXT; return (stripped_text, folios)."""
    folios = []
    def _sub(m):
        folios.append(m.group(1))
        return ""
    stripped = FOLIO_RE.sub(_sub, text)
    # Collapse multiple spaces from removal.
    stripped = re.sub(r"[ \t]{2,}", " ", stripped).strip()
    return stripped, folios


def split_paragraph_into_segments(paragraph: str) -> list[tuple[str, list[str]]]:
    """Split a Wylie paragraph into (wylie_unit, folios) at `//'.

    Folio markers are extracted per-unit: each returned tuple carries the
    folio identifiers that appeared within that unit.
    """
    # Step 1: normalise OCR shad variants.
    text = normalise_shads(paragraph)

    # Step 2: split at `//' but keep the `//' attached to the preceding
    # segment so the Wylie converter emits a trailing double-shad.
    parts = text.split("//")
    # Re-attach `//' to every non-final part (the final one has whatever
    # punctuation it ended with, usually empty after paragraph-terminating //).
    units = []
    for i, p in enumerate(parts):
        s = p.strip()
        if not s:
            continue
        if i < len(parts) - 1:
            s = s + " //"
        units.append(s)

    # Step 3: extract folio markers from each unit.
    results = []
    for unit in units:
        stripped, folios = extract_folios(unit)
        if stripped:
            results.append((stripped, folios))
    return results


def convert_wylie(converter, wylie: str) -> str:
    """Convert Wylie TEXT to Tibetan Unicode via pyewts, then tidy."""
    unicode = converter.toUnicode(wylie)
    # Collapse multiple tshegs (U+0F0B) that pyewts sometimes emits.
    unicode = re.sub(r"་{2,}", "་", unicode)
    return unicode.strip()


def process_body(body: str, converter) -> list[tuple[int, str, list[str]]]:
    """Return a list of (segment_number, unicode_text, folios) tuples."""
    # Split body into paragraphs on blank lines.
    paragraphs = [p.strip() for p in re.split(r"\n\s*\n", body) if p.strip()]
    segments = []
    n = 0
    for para in paragraphs:
        for wylie_unit, folios in split_paragraph_into_segments(para):
            n += 1
            unicode_text = convert_wylie(converter, wylie_unit)
            segments.append((n, unicode_text, folios))
    return segments


def format_segment(n: int, unicode_text: str, folios: list[str]) -> str:
    """Emit one `*** Segment N' heading with optional `:FOLIO:' property."""
    out = [f"*** Segment {n}"]
    if folios:
        out.append(":PROPERTIES:")
        out.append(f":FOLIO: {', '.join('D' + f for f in folios)}")
        out.append(":END:")
    out.append(unicode_text)
    out.append("")  # trailing blank line
    return "\n".join(out)


def split_source(source: str) -> tuple[str, str, str]:
    r"""Split SOURCE into (prefix, body, suffix) around `* Tibetan Text' block.

    prefix — everything up to and including `* Tibetan Text\n' (+ blank)
    body   — from there up to the next `^\* ' heading or EOF
    suffix — everything from that next heading to EOF (or empty)
    """
    # Find the `* Tibetan Text' heading line.
    m = re.search(r"(?m)^\* Tibetan Text\s*$", source)
    if not m:
        raise ValueError("Source has no `* Tibetan Text' heading")
    heading_end = m.end()
    # Skip trailing newline(s) after the heading line.
    rest = source[heading_end:]
    # Find the next `^\* ' heading in the rest.
    m2 = re.search(r"(?m)^\* ", rest)
    if m2:
        body = rest[:m2.start()]
        suffix = rest[m2.start():]
    else:
        body = rest
        suffix = ""
    prefix = source[:heading_end] + "\n"
    # Strip leading newlines from body (we'll add our own).
    body = body.lstrip("\n")
    return prefix, body, suffix


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source", type=Path, help="Path to gotrapatala.org")
    ap.add_argument("--in-place", action="store_true",
                    help="Overwrite source; otherwise write to stdout")
    args = ap.parse_args()

    source_text = args.source.read_text(encoding="utf-8")
    prefix, body, suffix = split_source(source_text)

    converter = pyewts.pyewts()
    segments = process_body(body, converter)

    segment_blocks = [format_segment(n, u, f) for (n, u, f) in segments]

    output = prefix + "\n".join(segment_blocks) + "\n"
    if suffix:
        output = output.rstrip("\n") + "\n\n" + suffix

    if args.in_place:
        args.source.write_text(output, encoding="utf-8")
        print(f"Wrote {len(segments)} segments to {args.source}", file=sys.stderr)
    else:
        sys.stdout.write(output)
        print(f"\n[{len(segments)} segments]", file=sys.stderr)


if __name__ == "__main__":
    main()
