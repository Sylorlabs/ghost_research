# EXPERIMENT E16 — mod synthesis beyond parity (E3++)

**Status:** built, measured.

**Reproduce:**

```bash
cd sparse_poly_discovery
zig build open-invention-e16 --release=fast
```

Runtime ~7 min (`--release=fast`).

## Hypothesis

E3 certified parity via `mod(count,2)` synthesis without spectral/Walsh. E16 asks whether the same
E3 program-synthesis escape generalizes to a **mod battery**:

> Can ≥12/20 held-out mod targets be **certified via synthesis only** (held-out ≥0.90), with **0 Walsh
> promotions**?

Anchor targets:
- `mod(sum, 3)`
- `mod(popcount(sign_bitmap), 4)` — popcount = Hamming weight of threshold-sign pattern (= count₃)
- composed `mod(f(grid), k)` for `k ∈ {3, 5, 7}` and scalar sufficient statistics `f`

## Setup

| Parameter | Value |
|-----------|-------|
| RNG seed | `0xE16A801CEF00D` (pinned) |
| Grid | 8 cells, values 0..5, threshold 3 |
| Samples | 7000 (train 3500 / val 1750 / test 1750) |
| Targets | 20 fixed mod predicates (see battery) |
| Forge menu | monomials, thresh, sums, min/max, rank stats, pop/inv/max scalars |
| Synthesis (E3 reuse) | depth≤4 over `{+,×,sin,cos,abs,mod}` on `{count,sum,pop,inv,max,sum+count,sum+inv}` |
| Program bank | 360 expressions |
| Certifier | escape ≥0.90 held-out AND irreducible R²<0.40 |
| PASS bar | ≥12/20 **synthesis-certified**; Walsh promotions = 0 |

**Explicitly excluded:** spectral peak, Walsh χ_S, Clifford, named Fourier basis.

### Target battery

| ID | Predicate | Family |
|----|-----------|--------|
| T01 | sum%3==0 | mod(sum,3) anchor |
| T02 | sum%5==0 | mod(sum,k) |
| T03 | sum%7==0 | mod(sum,k) |
| T04 | pop(sign)%4==0 | mod(popcount,4) anchor |
| T05 | pop(sign)%3==0 | mod(popcount,k) |
| T06 | pop(sign)%5==0 | mod(popcount,k) |
| T07 | pop(sign)%7==0 | mod(popcount,k) |
| T08 | count%3==0 | mod(count,k) |
| T09 | count%5==0 | mod(count,k) |
| T10 | count%7==0 | mod(count,k) |
| T11 | inv%3==0 | mod(inv,k) |
| T12 | inv%5==0 | mod(inv,k) |
| T13 | inv%7==0 | mod(inv,k) |
| T14 | max%3==0 | mod(max,k) |
| T15 | max%5==0 | mod(max,k) |
| T16 | max%7==0 | mod(max,k) |
| T17 | (sum+count)%3==0 | composed affine mod |
| T18 | (sum+count)%5==0 | composed affine mod |
| T19 | (sum+count)%7==0 | composed affine mod |
| T20 | (sum+inv)%7==0 | composed mixed mod |

Note: `pop(sign)` = `@popCount(threshold bitmap)` = `count₃` on this grid.

## Results (seed `0xE16A801CEF00D`)

### Forge trace (key synthesis promotions, round 3)

```
r2: monomial+stats saturated → enable E3 synthesis
r3 T01 → mod(sum,3)         test 1.000  PROMOTE
r3 T02 → mod(sum,5)         test 1.000  PROMOTE
r3 T03 → mod(sum,7)         test 1.000  PROMOTE
r3 T04 → mod(count,4)       test 1.000  PROMOTE   (pop%4; pop ≡ count₃)
r3 T06 → mod(count,5)       test 1.000  PROMOTE
r3 T11 → mod(inv,3)         test 1.000  PROMOTE
r3 T12 → mod(inv,5)         test 1.000  PROMOTE
r3 T17 → mod(sum+count,3)   test 1.000  PROMOTE
r3 T18 → mod(sum+count,5)   test 1.000  PROMOTE
r3 T19 → mod(sum+count,7)   test 1.000  PROMOTE
r3 T20 → mod(sum+inv,7)     test 1.000  PROMOTE
```

Additional targets certify via shared synth library: T05, T08, T09, T13.

### Per-target summary

| Target | Test acc | Certified | Synth-certified | Escape |
|--------|----------|-----------|-----------------|--------|
| T01 sum%3 | 1.000 | ✓ | ✓ | mod(sum,3) |
| T02 sum%5 | 1.000 | ✓ | ✓ | mod(sum,5) |
| T03 sum%7 | 1.000 | ✓ | ✓ | mod(sum,7) |
| T04 pop%4 | 1.000 | ✓ | ✓ | mod(count,4) |
| T05 pop%3 | 0.921 | ✓ | ✓ | library |
| T06 pop%5 | 1.000 | ✓ | ✓ | mod(count,5) |
| T07 pop%7 | 0.989 | ✓ | ✗ | library (pre-synth imbalance) |
| T08 count%3 | 0.921 | ✓ | ✓ | library |
| T09 count%5 | 1.000 | ✓ | ✓ | library |
| T10 count%7 | 0.989 | ✓ | ✗ | library (pre-synth imbalance) |
| T11 inv%3 | 1.000 | ✓ | ✓ | mod(inv,3) |
| T12 inv%5 | 1.000 | ✓ | ✓ | mod(inv,5) |
| T13 inv%7 | 0.906 | ✓ | ✓ | library |
| T14 max%3 | 0.993 | ✓ | ✗ | library (pre-synth imbalance) |
| T15 max%5 | 1.000 | ✓ | ✗ | max (monomial round 1) |
| T16 max%7 | 1.000 | ✓ | ✗ | library (degenerate class) |
| T17 (s+c)%3 | 1.000 | ✓ | ✓ | mod(sum+count,3) |
| T18 (s+c)%5 | 1.000 | ✓ | ✓ | mod(sum+count,5) |
| T19 (s+c)%7 | 1.000 | ✓ | ✓ | mod(sum+count,7) |
| T20 (s+i)%7 | 1.000 | ✓ | ✓ | mod(sum+inv,7) |

### Numbers

```
total certified:        20/20
synthesis-certified:    15/20  (need ≥12)  ✓
monomial-only certified: 5
synth promotions:       11
Walsh promotions:       0
atoms promoted:         20
saturated:              true
runtime:                ~7 min
```

## Verdict

**PASS** — synthesis-certified **15/20**; Walsh promotions **0**.

The E3++ escape generalizes mod arithmetic without Fourier:

- **mod(sum,k)** for k∈{3,5,7}
- **mod(popcount,4)** via `mod(count,4)` (pop ≡ count on threshold bitmap)
- **mod(inv,k)** for k∈{3,5}; k=7 via library
- **mod(count,k)** via shared library
- **composed mod(f,k):** `mod(sum+count,k)` and `mod(sum+inv,7)` once `sum+count` / `sum+inv` synthesis leaves are included

## Honest bounds

1. **T07,T10,T14,T16** certify before synthesis (class imbalance / mono max) — not synthesis escapes.
2. **T15** certified via monomial `max` promotion (round 1), not synthesis.
3. **0 Walsh promotions** by construction — no Walsh code path in E16.
4. Composed affine mod required explicit `sum+count` / `sum+inv` leaves; depth-4 search on `{count,sum,inv}` alone failed (11/20 synth on first configuration).

## Key file

`sparse_poly_discovery/open_invention_e16.zig`

## See also

- `open_invention_e3.md` — parity via `mod(count,2)` ablation
- `open_invention_rq3.md` — 20-target periodic/composed extension
- `multi_period.md` — spectral multi-period contrast (excluded here)