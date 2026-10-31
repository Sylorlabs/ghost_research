# Experiment E27 — Certified stack vs transformer on verifiable tasks

**Status:** built and measured. Reproduce:

```bash
cd sparse_poly_discovery && zig build open-invention-e27 --release=fast
```

Direct compile:

```bash
zig build-exe -OReleaseFast open_invention_e27.zig -femit-bin=zig-out/bin/ghost_open_invention_e27
./zig-out/bin/ghost_open_invention_e27
```

## What this is

Fair comparison **only on tasks with an independent checker** — the regime where the certified stack is designed to operate. No open-ended generation; no BPB-on-prose confound.

| Family | Checker | Stack path | Transformer proxy |
|--------|---------|------------|-------------------|
| **Parity** | Held-out grid label + ≥0.90 accuracy | E3-lite feature forge + logistic certify | 3-shot template prior on task id (no grid features) |
| **Compress** | Reversible program + gzip size | E9/E15-lite invent search | Raw gzip guess ×3 (no search) |
| **Chain** | Independent chain re-verify | dial-three iterative deepening | Binary-method length ×3 |
| **Terminal** | Simulated execution outcome | E8-style invented predicates | Optimistic “ok” template ×3 |

**Protocol**

- **100 tasks** (25/family), seed `0xE27C0FFEE270627`
- **50 train / 50 holdout** (even task id = train)
- **Stack:** invent on train, certify on holdout (verifier runs on every promotion)
- **Transformer proxy:** best-of-3 guesses **without** verifier during guessing; scored post-hoc against checker
- **Pass bar:** stack holdout solve rate ≥ **2×** transformer holdout solve rate

## Measured results (2026-06-30)

```
HOLDOUT certified solve rate:
  Stack (invent+verify):      50/50 = 100.0%
  Transformer proxy (3-shot): 20/50 =  40.0%
  Ratio stack/transformer:    2.50×  (pass bar ≥2.0×)

By family (holdout):
  parity:    stack 12/12, transformer  9/12
  compress:  stack 13/13, transformer  0/13
  chain:     stack 12/12, transformer  4/12
  terminal:  stack 13/13, transformer  7/13
```

**Verdict: PASS**

## Honest limits on the transformer comparison

### What this is NOT

1. **Not a live GPT-2 / DeepSeek run.** There is no transformer API in this repo path. We use an **honest proxy** for “3-shot guess without verifier”:
   - template / fixed-algorithm priors
   - no access to invented features, reversible search, or execution sensors
   - documented GPT-2 BPB numbers are **reference only** for text compression (wrapped **1.9105**, de-wrapped **1.0499** from `boundary_crossing/lm_bpc*.zig`) — **not comparable** to structured solve rate on checked tasks.

2. **Not comparable to BPB benchmarks.** BPB measures next-token surprise on English/Chinese bytes. E27 tasks are **decision problems with sound checkers** (parity label, gzip-after-transform, chain validity, exit code). A model with low BPB can still score ~0% here if it cannot run the checker loop.

3. **Terminal family is simulated.** E8 live runs are expensive and non-deterministic across machines. E27 uses keyword-inferred signatures (`zzz`, `false`, `wc`, …) — same pattern as E8 `--sim`. Live terminal would add noise but not change the core asymmetry: execution sensors vs text-only guess.

4. **Small scale by design.** Addition chains are certified only for \(n \lesssim 500\) in this battery; compress buffers are 128 bytes. The point is **mechanism separation** (verify vs guess), not SOTA on OEIS chains or corpus compression.

### What the proxy fairly represents

| Failure mode | Proxy behavior | Matches real LM weakness? |
|--------------|----------------|---------------------------|
| Parity without Fourier/features | Task-id bit prior | ✓ — template completion without structure |
| Compress without search | Raw gzip only | ✓ — “smaller file” text without reversible program |
| Chain without proof | Binary method | ✓ — rehearsed algorithm, wrong when suboptimal |
| Terminal without execution | Always predict ok | ✓ — optimistic completion bias |

A finetuned transformer with tool use / code execution could narrow this gap — that would be a **different experiment** (tool-augmented LM vs bare stack).

## Why stack wins here

1. **Verifier gate:** Only stack promotions survive independent re-check (chain `verify`, `progReversible`, held-out logistic ≥0.90, terminal predicate match).
2. **Outside generators per family:** mod/χ features (E3), macro search (E9), iterative deepening (dial-3), execution predicates (E8).
3. **Transformer proxy has no checker during inference:** Best-of-3 templates cannot recover from wrong algorithm family (0/13 compress when transform required).

## Cross-links

| Component | File |
|-----------|------|
| E27 source | `sparse_poly_discovery/open_invention_e27.zig` |
| Build step | `open-invention-e27` |
| Parity forge | `open_invention_e3.zig` |
| Compress invent | `boundary_crossing/open_invention_e9.zig` |
| dial-3 chains | `boundary_crossing/dial_three.zig` |
| Terminal invent | `boundary_crossing/open_invention_e8.zig` |
| GPT-2 BPB ref | `boundary_crossing/lm_bpc2.zig`, `gpt2_bpb.py` |

## See also

- `docs/research/open_invention_experiments.md` — master index (add E27 row)
- `boundary_crossing/docs/research/dial_three.md`
- `boundary_crossing/docs/research/verification_learning.md`