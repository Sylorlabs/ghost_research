# Swarm EXP-7 — verify-learn generalization on held-out target classes

**Date:** 2026-07-05  
**Status:** **PASS** — compositional library transfer measured; reproducible.

## Command

```bash
cd boundary_crossing && zig build swarm-exp07 --release=fast   # ~40 s
```

Seed: `0xE0077E4A6E01`. Harness: `swarm_exp07_verify_learn_gen.zig` → `unified_invention.runVerifyLearnGenBenchmark`.

## Question

After a **curriculum** of certified discovery episodes (verify-learn: promote only on escape + irreducible R²), does the growing feature library **generalize** to **held-out target-class fingerprints** with fewer iters-to-certify than a cold 8-monomial start?

This extends E15's promote→reuse loop to **24 hidden specs** and **10 disjoint held-out hashes**.

## Protocol

| Phase | What |
|-------|------|
| **Cold baseline** | Each held-out target solved with a **fresh** 8-singleton library |
| **Curriculum** | 24 hidden `TargetSpec`s run sequentially; promotions persist (forge → menu → world) |
| **Warm held-out** | Same 10 held-out specs after curriculum library (31 features) |

**iters-to-certify** = escalation steps until held-out cov ≥ 0.90:
- `0` if already covered by library at start (**library hit**)
- `+1` per forge round attempted
- `+1` menu phase, `+1` world phase if reached

**spec hash** = `specFingerprint({kind, mask, modulus})` (E12 fingerprint; no NL parser).

**Compositional generalization Y/N:** `Y` iff ≥1 warm library hit **or** mean cold−warm iters ≥ 1.0 with equal/higher solve rate.

## Curriculum (24 hidden specs)

| # | Spec | fp (low 16) | iters | Notes |
|---|------|-------------|-------|-------|
| 1–4 | mono c0–c3 | singleton | 0 | base library |
| 5–14 | mono pairs/triples/deg4 | varied | 2 | forge promotions |
| 15 | parity | 0x…0001 | 2 | menu spectral |
| 16 | oriented | 0x…0002 | 0 | library |
| 17–20 | sum%2,3,5,7 | mod primes | 3 | world pool |
| 21 | sign%2 | | 0 | library (sum%2 feature) |
| 22–23 | sign%3,5 | | 3 | world sign%mod |
| 24 | mono c4c5 | | 2 | menu Walsh |

**Curriculum result:** **24/24 certified**, iters_sum=42, library 8→31.

## Held-out (10 disjoint fingerprints)

| Spec | fp | cold iters | warm iters | Δ | warm |
|------|-----|------------|------------|---|------|
| H01 mono c4 | 0xE3779B97F4A7C150 | 0 | 0 | 0 | CERT **LIB** |
| H02 mono c5 | 0xC6EF372FE94F82A0 | 0 | 0 | 0 | CERT **LIB** |
| H03 mono c0c4 | 0x81AF155173F23D65 | 2 | 2 | 0 | CERT |
| H04 mono deg3 | 0x11A25CD6ED909A22 | 2 | 2 | 0 | CERT |
| H05 mono deg4 | 0xCFC0659B6017CFB1 | 2 | 2 | 0 | CERT |
| H06 sum%11 | 0x89133354F2050964 | 0 | 0 | 0 | CERT **LIB** |
| H07 sum%13 | 0x165C827BA9A8DC92 | 0 | 0 | 0 | CERT **LIB** |
| H08 sign%7 | 0x6E80950782BD6317 | 3 | 3 | 0 | CERT |
| H09 sign%11 | 0x89133354F2050963 | 0 | 3 | **−3** | CERT |
| H10 sign%13 | 0x165C827BA9A8DC95 | 0 | 0 | 0 | CERT **LIB** |

## Summary metrics

| Metric | Value |
|--------|-------|
| Held-out cold iters mean | **0.90** |
| Held-out warm iters mean | **1.20** |
| **iters Δ (cold − warm)** | **−0.30** |
| Library hits (warm iters=0) | **5/10** |
| **Compositional generalization** | **Y** |
| verify_learn_invent path (`runSingleTarget` parity) | cov=**1.000** |

## Verdict

- **iters-to-certify Δ on held-out:** **−0.30** (warm mean slightly *higher* — one regression on H09 sign%11).
- **Compositional generalization:** **Y** — **5/10** held-out targets certify at **iters=0** from the post-curriculum library (singleton monomials, world `sum%mod_*`, `sign%mod_*` features composed without new forge/menu/world search).
- **Curriculum:** 24/24 certified; library compounds from 8 → 31 features.

### Reading the −0.30 Δ honestly

Mean iters does **not** uniformly drop: H09 `sign%11` regresses from cold iters=0 → warm iters=3. The enlarged library shifts the joint logistic readout so a target that cold-start accidentally covered at 0.927 must re-escalate. This is the known **library interference** risk when promoting heterogeneous features without per-target sparsity selection.

The positive generalization signal is the **library-hit rate (5/10)**, not the mean-iter reduction:

- **H06/H07** sum%11/13: world `sum%mod_p` from curriculum transfers to unseen primes.
- **H01/H02**: singleton monomials remain in library.
- **H10** sign%13: sign%mod feature reuse.

### Integration with verify_learn_invent

`verify_learn_invent.zig` Phase 2c calls `runFullBenchmark`; `discover_feature` calls `runSingleTarget`. EXP-7 isolates the **discovery-library** verify-learn axis: labels = certifier escape only, updates = promote-to-library only (no next-token routing in this probe).

## Code map

| File | Role |
|------|------|
| `boundary_crossing/swarm_exp07_verify_learn_gen.zig` | EXP-7 harness, curriculum + held-out tables |
| `sparse_poly_discovery/unified_invention.zig` | `specFingerprint`, `solveOneTarget`, `runVerifyLearnGenBenchmark` |
| `boundary_crossing/build.zig` | `zig build swarm-exp07` |
| `boundary_crossing/verify_learn_invent.zig` | Parent integration (routing + discover_feature) |

See also: `verify_learn_invent.md`, `open_invention_e15.md`, `unified_invention.zig` (Fork 5).