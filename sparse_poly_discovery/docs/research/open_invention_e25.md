# EXPERIMENT E25 — Novelty-usefulness Pareto (E10++)

**Status:** measured (2026-06-30). **Verdict: FAIL** (sweep flat; no pass point)

## Question

Can tuning the certifier knobs — **R² irreducibility gate** and **escape coverage threshold** —
find a Pareto-sweet spot that beats the E10 tension? Specifically: a fused (useful) forge that
achieves **≥5×** the novelty-only random-battery hit rate **while** promoting at **≥3 atoms per
100** random battery targets.

Extends E10 by sweeping `{0.2,0.3,0.4,0.5} × {0.85,0.90,0.95}` instead of the single E10 point
(R²<0.40, escape≥0.90).

## Protocol

| Piece | Detail |
|-------|--------|
| **Substrate** | E10 centered monomials; shared grid seed `0xF0235A11CE0FF1CE` |
| **Battery** | 128 random `sign(φ_S)` targets, seed `0xE10BA771E0000001` |
| **Control** | Novelty-only forge at each R² gate (target-agnostic) |
| **Fused** | `inner_forge` objective: irreducible ∧ escape at each (R², escape) |
| **Ratio** | `useful_random_ratio` = (useful battery hit rate) / (novelty battery hit rate) |
| **Throughput** | `prom_per_100` = useful promotions × 100 / 128 |
| **Pass** | ∃ grid point with ratio ≥ **5×** AND prom/100 ≥ **3** |

**Reproduce:**

```bash
cd sparse_poly_discovery && zig build open-invention-e25 --release=fast
```

(~7 min, `--release=fast`)

## Sweep results (12/12 grid points — **all identical**)

| R² | escape | nov_prom | nov_rand | use_prom | use_rand | zoo | ratio | prom/100 |
|----|--------|----------|----------|----------|----------|-----|-------|----------|
| 0.2–0.5 | 0.85–0.95 | **16** | **14/128** | **3** | **2/128** | **4/5** | **0.14×** | **2.34** |

Every `(R², escape)` pair reproduces the E10 default outcome:

- **Novelty-only:** 16 promotions → 14/128 random hits (**10.9%**)
- **Useful-forged:** 3 promotions → 2/128 random hits (**1.6%**)
- **Zoo:** 4/5 structured targets (T1–T4 monomial signs; T5 parity still unsolved)
- **Ratio:** 2/14 = **0.14×** (useful forge is **7× worse** than novelty on random battery)
- **Throughput:** 3 × 100/128 = **2.34** promotions/100 targets (needs ≥3)

## Pareto frontier

All 12 points are **mutually non-dominated only because they are identical** — the sweep surface
is **flat**. There is no tradeoff curve: R² gate and escape threshold do not move promotions,
random-battery hits, or zoo coverage on this substrate.

**Best (tied) Pareto point:** R²=**0.4**, escape=**0.90** (E10 baseline) — or any grid cell.

| Metric | Value |
|--------|-------|
| Useful promotions | 3 |
| Random battery hits | 2/128 (1.6%) |
| Zoo solved | 4/5 |
| Useful/novelty ratio | 0.14× |
| Promotions/100 targets | 2.34 |

## Verdict: **FAIL**

1. **Pass bar not met.** No point reaches useful/random ≥5× (best **0.14×**) or prom/100 ≥3
   (best **2.34**). The fused objective cannot simultaneously match novelty breadth on random
   targets and maintain promotion throughput.

2. **Certifier knobs are inert here.** Loosening R² to 0.5 or tightening escape to 0.95 does
   not change which atoms promote — the zoo pins the same three masks (0x24, 0x4A, 0xB1) and
   novelty forge saturates the atom cap at every R² gate tested.

3. **Reconfirms E10 tension quantitatively.** Novelty-only wins random-battery breadth
   (10.9% vs 1.6%); useful-forge wins zoo concentration (4/5 vs 2/5). Fusing irreducibility
   with escape **cannot be tuned into** a point that beats novelty on random hits — the
   objectives are genuinely opposed on this monomial substrate.

4. **Honest reading of 0.14×.** The useful library scores lower on random battery because it
   promoted **zoo-aligned** masks, not breadth-covering high-degree atoms. More R²/escape tuning
   without a different target distribution or operator menu will not flip this.

## See

`open_invention_e10.md` (E10 baseline), `inner_forge.zig` (fused objective), `inventable_substrate_design.md`
(novelty↔usefulness design), `wcore/docs/research/alien_novelty_limit.md` §21–22.