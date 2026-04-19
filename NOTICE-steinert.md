# Notice — Steinert dictionary integration

`tibetan-cat.el` bundles an **optional** SQLite index built from the
Tibetan–English–Sanskrit dictionary collection compiled and published by

> **Christian Steinert** — https://dictionary.christian-steinert.de/
> Source repository (text files): https://github.com/christian-steinert/dictionary

The aggregated database contains entries drawn from ~60 individual
glossaries. **Copyright in each underlying dictionary remains with its
respective compiler / publisher.** Christian Steinert's collection is
distributed under the terms stated on the project's website and
repository; inclusion here is intended for scholarly and research use.

## What this project adds

* `scripts/build-steinert-db.py` — a build script that reads the
  pipe-separated `wylie|entry` text files from
  `_input/dictionaries/public/` and emits a SQLite file at
  `data/dictionaries/steinert.db`.
* `core/tibetan-steinert.el` — an Emacs-Lisp lookup layer.
* Hook points in `core/tibetan-vocabulary-detailed.el` that surface
  Sanskrit equivalents in the Detailed Dictionary view.

## How to rebuild

```sh
# 1. place (or clone) Christian Steinert's dictionary repo into steinert-src/
git clone https://github.com/christian-steinert/dictionary steinert-src

# 2. build the SQLite index
make build-steinert
# -> data/dictionaries/steinert.db  (~220 MB, ~800k entries)
```

## Per-source classification

Sanskrit extraction is tuned per source:

* **Canonically Sanskrit-indexed** (gloss = Sanskrit equivalent):
  21-Mahavyutpatti-Skt, 22-Yoghacharabhumi-glossary, 46-84000Skt,
  49-LokeshChandraSkt, 15-Hopkins-Skt1992, 15-Hopkins-Skt2015.
* **Sanskrit-rich but noisy** (raw articles with IAST interleaved):
  50-NegiSkt.
* **Embedded markers** (`[Skt.] foo`, `Sanskrit: foo`): general
  Hopkins / Berzin / 84000 glosses.
* **Scan-page-only sources** (skipped entirely — headwords without
  usable gloss): 63-Mahavyutpatti-Scan-1989,
  64-sgra-sbyor-bam-po-gnyis-pa, 65-ChandraDas_Scan, 66-Jaeschke_Scan.

## License

The lookup code in this repository is licensed under the same terms as
the rest of `tibetan-cat.el` (GPL). The dictionary *data* is not
relicensed by that code — it remains the intellectual property of the
individual compilers acknowledged on
https://dictionary.christian-steinert.de/ .

When redistributing the built `steinert.db`, keep this NOTICE alongside
it.
