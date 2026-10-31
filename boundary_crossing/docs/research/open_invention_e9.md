# EXPERIMENT E9 — real-data compression invention (cross-corpus generalization)

**Status:** built, measured (2026-06-30, crash fixed). Reproduce:
```bash
cd boundary_crossing && zig build open-invention-e9 --release=fast
```
(~2–4 min after stability fixes; previously crashed/hung on full-corpus held-out eval).

## The question

`self_extending_inventor` proved promoted macros compound on a **synthetic** stream. E9 asks: does
self-extension **generalize across corpora** — macros invented on English helping held-out **Chinese**
without re-training?

## Setup

| Phase | Corpus | Bytes | Chunks evaluated |
|-------|--------|------:|-----------------:|
| **Train** | `corpus/train_dw_8mb.txt` | 8,000,000 (cap 2 MiB) | 16 sampled / 64 total |
| **Held-out** | `corpus/chinese_train.txt` | 2,343,840 | 24 / 72 (capped) |
| **Held-out** | `corpus/zh_held_dw.txt` | 316,312 | 10 / 10 |

- **Verifier:** gzip size + exact round-trip reversibility.
- **Train:** vote structural singles (`delta`/`xor`/`stride`/`mtf`) across 16 sampled chunks; promote if ≥2 chunk wins (max 16 macros). Then search with library.
- **Held-out:** compare base gzip vs no-promotion vs self-extend (frozen train library). Budget: 4×10 search per chunk (lighter than train 8×18).
- **Pass (meaningful):** `train library > 0` **AND** `no-promotion bytes − self-extend bytes > 0` on held-out family.

## Results (2026-06-30 re-run, post crash-fix)

```
TRAIN  train_dw_8mb.txt (2 MiB cap, 16 chunks sampled)
  raw gzip 219,906 → invented 219,886
  library after train: 0 macro(s)

HELD-OUT FAMILY (2 files, 34 chunks evaluated)
  base gzip (identity)     522,675
  no-promotion search      522,640
  self-extend (train lib)  522,635

bytes saved (no-promo − self-extend): 5
PASS/FAIL: FAIL (library empty — delta is search noise)
```

Per file:

```
chinese_train.txt   24/72 chunks | base 378,872 | no-promo 378,849 | self-extend 378,846 | Δ 3
zh_held_dw.txt      10/10 chunks | base 143,803 | no-promo 143,791 | self-extend 143,789 | Δ 2
```

## Crash fix (what changed)

Earlier runs **terminated unexpectedly** during held-out on full 82-chunk Chinese eval (OOM/hang).

Fixes in `open_invention_e9.zig`:
1. **Held-out chunk cap** — `HELD_MAX_CHUNKS=24` per file.
2. **Train vote sampling** — 16 chunks, 16 structural singles (not 272 pairs × 64 chunks).
3. **Stable chunk slice** — `chunkIndices` copies into arena alloc (no dangling slice).
4. **Lighter held-out search** — 4×10 vs train 8×18.
5. **Honest pass criterion** — requires non-empty train library.

## Verdict — honest null on cross-corpus macro transfer

**FAIL.** Train library stayed **empty**: no structural pre-gzip transform beat raw gzip on ≥2 English
chunks. `delta`/`mtf` inflate gzip on natural UTF-8 prose (gzip already internalizes LZ77).

- **Micro held-out delta (5 bytes)** is search stochasticity with **empty library**, not macro transfer.
- **Invention on held-out still works** at micro scale: search shaves bytes vs identity gzip.
- **Cross-corpus self-extension does not:** `self-extend` ≡ `no-promotion` when library is empty.

This matches the prior documented null result; the re-run **confirms** after completing held-out eval cleanly.

## What would change the outcome

1. **Binary/sensor streams** where `delta`+`stride` pre-whiten before gzip (synthetic proof regime).
2. **Different certifier** — BPB on downstream model, not gzip-on-compressible text.
3. **Out-of-closure primitive** gzip cannot subsume.

## Honest bound

On real multilingual prose, the reversible filter DSL may discover **nothing worth promoting**;
cross-corpus generalization is **zero** — reported, not hidden.

See: `self_extending_inventor.md`, `autonomous_inventor.md`, `docs/research/open_invention_experiments.md`.