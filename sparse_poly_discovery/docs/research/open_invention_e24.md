# Experiment E24 — k≥3 aliens with order-stats

**Status:** built, measured. Reproduce:

```bash
cd sparse_poly_discovery
zig build open-invention-e24 --release=fast
```

Or direct:

```bash
zig build-exe open_invention_e24.zig -OReleaseFast -femit-bin=zig-out/bin/ghost_open_invention_e24
./zig-out/bin/ghost_open_invention_e24
```

## The question

E6 showed **0/16** random alien solves with a k≥3 open forge (mono + modK + order-stats) and **no Walsh**.
`k3_order_escape.zig` (Fork 6) showed the **same substrate family** breaks the **designed** T6 median wall
via rank indicators (6/6 on the fixed T1–T6 zoo).

E24 asks:

> Does the **k3_order_escape** forge protocol — not just the atom menu, but its training schedule and
> promotion certifier — solve **E6's certified alien distribution** without injecting Walsh/Fourier?

## Setup

| piece | detail |
|---|---|
| Alien targets | **E6** distribution: 8 certified aliens per k, seed `0xE601CEF0A6B33D00` (+k grid offset) |
| Substrate | **k3_order_escape** `.full` pool: mono + modK pair/triple/global + order-stats |
| Excluded | Walsh, spectral count-Fourier, Boolean Fourier menu |
| Certifier | escape ≥0.90 held-out test AND irreducible R² < 0.40 (same as E6 / Fork 6) |
| Pass bar | **≥4/16** certified promotions |

### Contrast with E6

| | E6 | E24 |
|---|---|---|
| Targets | E6 certified aliens | **Same** E6 aliens |
| Forge | E6 `runOpenForge` (80-epoch coverage) | **k3_order_escape** `runAlienForge` (150-epoch) |
| Pool | E6 atoms (+ `spread3` at k=4) | k3_order_escape atoms (no `spread3`) |
| Walsh | none | none |

## Results (pinned seed, 2026-06-30)

### k=3 aliens (same as E6)

```
A1: parity_high        → final 0.49  (best: med==1 escape 0.50 — skip)
A2: range(5,6,3)==1    → final 0.51  (best: max−mid escape 0.72 R²=0.50 — skip)
A3: count(c==1)==3     → final 0.69
A4–A8: aff/range/parity → 0.49–0.67

forge: 0/8 solved; saturated round 1; atoms stayed 8
```

### k=4 aliens (same as E6)

```
A1: count(c==3)==2     → final 0.65
A2–A3,A6–A7: parity_high → final 0.51
A4: sq_mod(2,2)==2     → final 0.63
A5: count(c==0)==2     → final 0.69  (best escape 0.70 — below 0.90 bar)
A8: count(c==1)==2     → final 0.64

forge: 0/8 solved; saturated round 1; atoms stayed 8
```

### Aggregate

```
solve rate:                 0/16  (0.0%)
certified promotions:       0/16
non-monomial promotions:    0
pass bar (≥4 promotions): FAIL
```

Notable near-misses (not certified): `max−mid(3,5,6)` at 0.72 on A2 (R²=0.50);
`aff(2,5)==0` candidate hit 0.90 val escape but failed irreducibility (R²=−0.04, still no promotion
because escape on held-out test did not clear 0.90).

## Verdict

**FAIL** — k3_order_escape does **not** solve E6's 16 aliens without Walsh.

The Fork 6 substrate breaks the **designed** T6 median wall (6/6 on T1–T6) but produces **0/16**
certified promotions on E6's random alien families. Saturates immediately, same as E6.

## Honest scope

- Alien families and certification are **imported from E6** — not re-drawn.
- Only the **forge engine** changes to k3_order_escape.
- Success would mean order-stats + modK escape crosses **random** multiplicative/affine/parity families;
  failure confirms the closure law extends from Boolean forge to k≥3 even after T6 wall breakage.

## See also

`open_invention_e6.zig`, `k3_order_escape.zig`, `open_invention_e6.md`, `parallel_forks_2026.md`, `CLOSURE_PRINCIPLE.md`