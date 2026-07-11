# EXPERIMENT E23 — cross-corpus compression v2 (structurally similar corpora)

**Status:** built, measured (2026-06-30). Reproduce:
```bash
cd boundary_crossing && zig build open-invention-e23 --release=fast
```
(~1–2 min with vote+pair grid + stream self-extension on 32 train chunks).

## The question

E9 tested EN→ZH macro transfer and failed (0 macros; 5-byte search noise). **E23 asks:** is the
blocker **script mismatch**, or does macro transfer fail even on **structurally similar** corpora
(same-language Gutenberg held-out from the same de-wrap pipeline)?

## Setup

| Phase | Corpus | Bytes | Chunks evaluated |
|-------|--------|------:|-----------------:|
| **Train** | `corpus/train_dw_8mb.txt` | 8,000,000 (cap 2 MiB) | 32 sampled / 64 total |
| **Held-out** | `corpus/heldout_eval_dw.txt` | 169,008 | 6 / 6 |
| **Held-out** | `corpus/heldout_eval.txt` | 172,389 | 6 / 6 |

- **Verifier:** gzip size + exact round-trip reversibility.
- **Train library (v2 extensions over E9):**
  1. Vote grid with **272 candidates** (16 singles + 256 pairs), `MIN_VOTES=1`.
  2. **Stream self-extension:** promote per-chunk exhaustive/search winners that beat raw gzip.
- **Held-out:** compare base gzip vs no-promotion vs self-extend (frozen train library). Budget: 4×10 per chunk.
- **Pass bar:** `train library > 4 macros` **AND** held-out transfer `> 0.1%` (no-promo − self-ext)/no-promo.

Shared core: `compression_invent.zig` (factored from `open_invention_e9.zig`).

## Results (2026-06-30)

```
TRAIN  train_dw_8mb.txt (2 MiB cap, 32 chunks)
  raw gzip 438,867 → invented 438,829 (0.009% smaller)
  library after train: 0 macro(s)

STRUCTURED HELD-OUT (2 files, 12 chunks)
  base gzip (identity)     134,491
  no-promotion search      134,475  (0.012% vs base)
  self-extend (train lib)  134,476  (0.011% vs base)

bytes saved (no-promo − self-extend): −1
cross-corpus transfer: −0.001%
PASS/FAIL: FAIL (library 0 < 5 required)
```

Per file:

```
heldout_eval_dw.txt   6/6 chunks | base 65,747 | no-promo 65,738 | self-extend 65,738 | Δ 0
heldout_eval.txt      6/6 chunks | base 68,744 | no-promo 68,737 | self-extend 68,738 | Δ −1
```

## Comparison to E9

| Metric | E9 (EN→ZH) | E23 (EN→EN same-family) |
|--------|------------|-------------------------|
| Train library | 0 | 0 |
| Held-out Δ bytes | +5 | −1 |
| Transfer % | 0.001% | −0.001% |
| Verdict | FAIL | FAIL |

**Conclusion:** Removing the cross-script gap does **not** unlock macro transfer. The bottleneck is
not EN vs ZH — it is that **gzip already internalizes LZ77** on natural UTF-8 prose, so
`delta`/`xor`/`stride`/`mtf` pre-transforms do not beat gzip on enough train chunks to promote
even one macro (vote, pairs, or stream promotion).

## Verdict — honest null on same-family macro transfer

**FAIL.** Train library stayed **empty** despite v2 extensions (pair vote grid, `MIN_VOTES=1`,
stream self-extension). Held-out transfer is **zero to negative** — no meaningful macro
generalization even within the same Gutenberg distribution.

- E9's 5-byte Chinese held-out delta was search stochasticity; E23's −1 byte confirms the same
  at same-family scale.
- Search still shaves micro-bytes vs identity gzip on held-out (0.01% range), but **without
  promoted macros** self-extend ≡ no-promotion.

## What would change the outcome

1. **Binary/sensor streams** where `delta`+`stride` pre-whiten before gzip (synthetic proof regime in `self_extending_inventor`).
2. **Different certifier** — BPB on a downstream model, not gzip-on-compressible text.
3. **Out-of-closure primitive** gzip cannot subsume.

## Honest bound

On real English prose (train and held-out from the same pipeline), reversible-filter macro
libraries **do not form** and **do not transfer** — whether the held-out script matches or not.
The closure is gzip + natural text, not cross-corpus script boundaries.

See: `open_invention_e9.md`, `self_extending_inventor.md`, `autonomous_inventor.md`, `compression_invent.zig`.