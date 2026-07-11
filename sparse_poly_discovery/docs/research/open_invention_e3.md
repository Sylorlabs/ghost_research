# EXPERIMENT E3 — "No spectral in codebase" ablation

**Status:** built, measured. Reproduce:

```bash
cd sparse_poly_discovery
zig build-exe -OReleaseFast open_invention_e3.zig -femit-bin=zig-out/bin/ghost_open_invention_e3
./zig-out/bin/ghost_open_invention_e3
```

Or (if sibling E-targets compile): `zig build open-invention-e3 --release=fast` (~72 s).

## Hypothesis

Prior forks (inner_forge, unified_invention) escape parity-of-count by routing to **hand-named**
spectral (`cos(ω·count)`, ω≈π) or Walsh (χ_S) operators. E3 asks the decisive question:

> Can parity be **certified** (held-out test ≥0.90) using only an open menu with **no** spectral peak,
> Walsh transform, Clifford, or any named Fourier basis?

Allowed primitives:
- Centered monomials φ_S and threshold-sign monomials χ_S
- Threshold signs, sums (pair/triple/all), count
- Min/max and rank indicators (k3_order_escape patterns)
- Optional depth≤4 program synthesis over `{+,×,sin,cos,abs,mod}` on **count only**

## Setup

| Parameter | Value |
|-----------|-------|
| RNG seed | `0xE3A801CEF00D` (pinned) |
| Grid | 8 cells, values 0..5, threshold 3 |
| Samples | 7000 (train 3500 / val 1750 / test 1750) |
| Targets | parity-of-count + 10 random Boolean χ_S (|S|∈1..4) |
| Certifier | escape ≥0.90 held-out AND irreducible R²<0.40 |
| Program bank | 320 synthesized count expressions |

**Explicitly excluded:** `discoverSpectral`, `discoverWalsh`, `operator_menu_lib` routing, Clifford g2.

## Results (2026-06-30)

```
round 0:  parity=0.51  χ_*=0.48–0.53  → 0/11

round 1: 10 random χ_S targets → monomial / χ_mono promotions (atoms 9→18)
round 2: parity stuck at 0.51 → monomial+stats SATURATED
round 3: parity → mod(count,2) escape 1.00 R²=−0.12 → PROMOTE

final: 11/11 certified; atoms 19; saturated=true
  parity test acc: 1.000
  random Boolean: 10/10
```

**Parity escape primitive:** `mod(count,2)` — discovered by count program synthesis, not by a
named Fourier operator.

## Verdict

**PASS** — parity certified without hand-named spectral/Walsh.

The open menu + synthesis **can** discover periodic structure on count when `mod` is in the
synthesis algebra. The escape is `count % 2`, which is the correct Z₂ readout of parity —
functionally equivalent to spectral separation but **not** pre-named in the codebase.

## Honest bounds

1. **Synthesis leaf is only count** — the system does not search programs over the full 8-cell
   sign pattern. Parity happens to live on a 1-D sufficient statistic (count), so this is fair
   for parity but not a general Boolean-Fourier replacement.
2. **Random χ_S targets are easy** for this menu — they are low-degree threshold monomials;
   10/10 is expected, not surprising.
3. **Contrast with inner_forge:** inner_forge saturates at 0.50 on parity with monomials alone;
   E3 adds sums/stats/synthesis and finds `mod(count,2)`. unified_invention still needs the
   named spectral menu for parity when synthesis is absent.
4. A **FAIL** on parity (without mod in the synthesis ops) would also be a valid finding — it
   would confirm that Z₂ periodic structure requires Fourier-class operators not reachable from
   polynomials alone.

## Key file

`sparse_poly_discovery/open_invention_e3.zig`

## See also

- `inner_forge.md` — monomial saturation at 4/5; spectral menu escape (Fork 1)
- `spectral_discovery.md` — named spectral peak baseline
- `boolean_fourier.md` — Walsh universal operator (excluded here)
- `k3_order_escape.zig` — rank-stat patterns reused in menu