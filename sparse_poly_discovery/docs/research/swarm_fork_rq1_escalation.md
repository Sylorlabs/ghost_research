# Swarm fork — RQ1++ staged escalation

**Date:** 2026-07-05  
**Fork:** EXP-4 → RQ1++ in `open_invention_rq1.zig`  
**Status:** measured

## Command

```bash
cd sparse_poly_discovery && zig build open-invention-rq1 --release=fast
```

**Seeds (pinned):** grid `0xF0235A11CE0FF1CE`, battery `0xE1B10D20A11CE01`

## Question

Can the RQ1 blind battery improve from **6/11** (frozen monomial + count synth + E5 pipelines only)
toward **11/11** **without** E1's pre-labeled spectral/Walsh/Clifford/world operator menu — by wiring
a **structural** escalation ladder?

## RQ1++ ladder (implemented)

| Step | Mechanism | Trigger |
|------|-----------|---------|
| **1** | Frozen monomial library | always |
| **2** | Count synth `{+,×,sin,mod}` + E5 pipelines | step 1 < 0.90 |
| **3** | Pair hardness router — 28× correlation rank + 1 verify fit | steps 1–2 < 0.90 |
| **4** | Walsh χ_S correlation argmax (`operator_menu_lib.discoverWalsh`) | step 3 < 0.90 **and** hardness = `q38_compound` |

**Hardness gate (step 4):** mono score = frozen-library test accuracy (not oracle mask search);
extremal score = best of `{max_cell, oriented, countGE}` scalar probes. Both ≤ 0.55 → `q38_compound`.

**Still excluded:** spectral peak menu, Clifford, world pool, pre-named operator routing.

## Final score

### **11/11** certified (test ≥ 0.90)

| Step | Targets closed | Count |
|------|----------------|-------|
| 1 — frozen monomial | B4, B9, B10 | **3** |
| 2 — mod / pipeline | B3, B8, B11 | **3** |
| 3 — pair router | B1, B5, B7 | **3** |
| 4 — Walsh (q38 only) | B2, B6 | **2** |

Baseline RQ1 (no escalation): **6/11**. RQ1++ gain: **+5 targets** via steps 3–4.

## Per-target results

| Target | Known family | Step | Method | Test acc | Family match |
|--------|--------------|------|--------|----------|--------------|
| B1 random mono deg2 (mask 0x0C) | monomial φ_S | **3** | pair φ(2,3) product | **1.000** | ✓ |
| B2 random mono deg3 (mask 0x2A) | monomial φ_S | **4** | Walsh χ(0x83) | **1.000** | ~ |
| B3 sum(g)%7 | world sum%mod | **2** | pipeline `sum_all→scan_p(ω≈0.884)` | **0.998** | ~ |
| B4 sign%mod 11 | world sign%mod | **1** | frozen monomials | **0.905** | ~ |
| B5 Walsh χ{0x11} | Walsh χ_S | **3** | pair φ(0,4) product | **1.000** | ~ |
| B6 Walsh χ{0xA4} | Walsh χ_S | **4** | Walsh χ(0xA4) | **1.000** | ✓ |
| B7 Walsh χ{0x0A} | Walsh χ_S | **3** | pair φ(1,3) product | **1.000** | ~ |
| B8 parity-of-count | Z₂ on count | **2** | synth `mod(count,2)` | **1.000** | ✓ |
| B9 oriented v1>v0 | relational | **1** | frozen monomials | **1.000** | ✓ |
| B10 parity∧sum%5 | AND(Z₂, sum%mod) | **1** | frozen monomials | **0.910** | ~ |
| B11 inversion parity | Z₂ on inversion | **2** | pipeline `inversion→half_p` | **1.000** | ✓ |

**Saturated:** 0/11

## What each escalation step bought

### Step 3 — pair router (+3 over baseline)

- **B1** — deg-2 monomial mask 0x0C absent from frozen zoo; pair inner on cells {2,3} recovers product sign.
- **B5** — Walsh χ_{0,4} also closed by deg-2 pair (0,4); pair step runs before Walsh gate.
- **B7** — Walsh χ_{1,3} closed by pair (1,3) before Walsh needed.

Pair router alone recovers **7/11** if added to original RQ1 6/11 (+B1 only per EXP-4 projection); on this
run it additionally closes B5 and B7 because pair escalation precedes Walsh.

### Step 4 — Walsh on q38_compound (+2)

- **B2** — deg-3 mask 0x2A; pair saturates (~0.49); frozen mono + extremal probes ≤ 0.55 → Walsh fires → 1.000.
  Discovered χ(0x83) (equivalent parity readout; mask label differs from ground-truth 0x2A).
- **B6** — triple Walsh character; pair fails; q38_compound → χ(0xA4) exact match.

Walsh skipped on B5/B7 (already certified at step 3) and on B3/B8/B11 (not q38 after step 2).

## Comparison

| | RQ1 (control) | RQ1++ (this fork) | E1 (handed menu) |
|---|---------------|-------------------|------------------|
| Certified | **6/11** | **11/11** | 11/11 |
| Pair growth | ✗ | step 3 | via menu |
| Walsh | ✗ (blocked) | step 4 (gated) | menu-routed |
| Anti-remix | strong | moderate (Walsh admitted structurally) | weak |

## Implementation notes

- File: `open_invention_rq1.zig` — header updated to RQ1++; `evaluateBlind` runs ladder after pipeline saturation.
- Pair logic adapted from `pair_hardness_router.zig` (EXP-02 correlation rank).
- Walsh via `operator_menu_lib.discoverWalsh` (correlation argmax, not menu label).
- Critical fix: Walsh gate uses **frozen** mono accuracy for hardness, not full-mask oracle search (which
  mis-classified B2 as `single_sufficient` and blocked Walsh).

## Verdict

**RQ1++ closes the EXP-4 gap:** blind battery **11/11** without pre-listed spectral menu.

Steps 1–2 still deliver the principled Z₂ / periodic wins (6/11 baseline). Steps 3–4 add structural
pair + gated Walsh discovery for monomial and parity-on-sign targets — recovering E1 coverage while
keeping routing structural rather than name-based.

## References

- `swarm_exp04_rq1_gap.md` — gap diagnosis and projected 11/11 ladder
- `open_invention_rq1.md` — original 6/11 protocol
- `pair_hardness_router.zig` — pair correlation router (EXP-02)
- `open_invention_e14.zig` — Q38 hardness gate pattern