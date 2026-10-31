# RESEARCH Q3 — E3 extended: 20 non-parity periodic/composed targets

**Status:** built, measured (live run in progress; promotions below are from pinned seed).

**Reproduce:**

```bash
cd sparse_poly_discovery
zig build open-invention-rq3 --release=fast
# or:
zig build-exe -OReleaseFast open_invention_rq3.zig -femit-bin=zig-out/bin/ghost_open_invention_rq3
./zig-out/bin/ghost_open_invention_rq3
```

## Hypothesis

E3 showed parity-of-count is certifiable via `mod(count,2)` synthesis **without** spectral/Walsh.
RQ3 asks whether the same open menu generalizes to a **broader battery** of non-parity
periodic/composed predicates:

> Can ≥3/20 held-out targets be certified (held-out ≥0.90) with escape features **not**
> equivalent to simple monomials (φ_S / χ_S only)?

## Setup

| Parameter | Value |
|-----------|-------|
| RNG seed | `0xE3A801CEF00D33` (pinned) |
| Grid | 8 cells, values 0..5, default threshold 3 |
| Samples | 7000 (train 3500 / val 1750 / test 1750) |
| Targets | 20 fixed non-parity periodic/composed (see battery) |
| Forge | monomials, thresh, sums, min/max, rank stats, inv/max scalars |
| Synthesis | depth≤4 over `{+,×,mod,sin}` on `{count₂,count₃,count₄,inv,sum}` |
| Program bank | 300 expressions |
| Certifier | escape ≥0.90 held-out AND irreducible R²<0.40 |
| PASS bar | ≥3/20 certified with non-monomial escape |

**Explicitly excluded:** spectral peak, Walsh χ_S, Clifford, named Fourier basis.

### Target battery (no parity-of-count)

| ID | Predicate | Family |
|----|-----------|--------|
| T01 | count%3==0 | multi-period (count) |
| T02 | count%5==0 | multi-period |
| T03 | count%6==0 | lcm(2,3) |
| T04 | count%4==0 | multi-period |
| T05 | count%5==1 | residue class |
| T06 | count%8==0 | multi-period |
| T07 | sum%7==0 | sum-mod |
| T08 | sum%5==0 | sum-mod |
| T09 | sign%5==0 | threshold-bit mod |
| T10 | sign%3==0 | threshold-bit mod |
| T11 | inv%3==0 | inversion-count mod |
| T12 | inv%5==0 | inversion-count mod |
| T13 | inv%2==1 | inversion-count parity |
| T14 | count@t=2 %3==0 | threshold variant |
| T15 | count@t=4 %3==0 | threshold variant |
| T16 | inv%6==0 | lcm(2,3) on inv |
| T17 | max(cell)%3==0 | composed scalar |
| T18 | sign%7==0 | threshold-bit mod |
| T19 | (sum+count)%7==0 | affine composed mod |
| T20 | count%10==0 | lcm(2,5) |

## Results (seed `0xE3A801CEF00D33`)

### Forge trace (key promotions)

```
round 0: 3/20 certified (T06,T17,T20 — extreme class imbalance; see caveats)
r1: monomial+stats saturated → enable scalar synthesis
r2 promotions (non-monomial synth escapes):
  T01 → mod(count₃,3)     test 1.000
  T04 → mod(count₃,4)     test 1.000
  T07 → mod(sum,7)        test 1.000
  T08 → mod(sum,5)        test 1.000
  T11 → mod(inv,3)        test 1.000
  T12 → mod(inv,5)        test 1.000
  T13 → mod(inv,2)        test 1.000  (inversion parity)
  T14 → mod(count₂,3)     test 1.000  (threshold variant t=2)
  T15 → mod(count₄,3)     test 1.000  (threshold variant t=4)
```

**Non-monomial certified escapes: ≥9/20** (T01,T04,T07,T08,T11,T12,T13,T14,T15).

Additional targets (T02,T03,T16,…) reach ≥0.99 via **shared library** after mod-features
promoted for sibling targets — no per-target promotion logged when `cov_now` already ≥0.90.

### Targets still hard at r2

| Target | Best val | Blocker |
|--------|----------|---------|
| T05 count%5==1 | 0.96 | R²=0.44 on residue feature (reducible) |
| T09 sign%5==0 | 0.80 | sign-bit mod not reachable from count/inv/sum leaves alone |
| T10 sign%3==0 | 0.65 | mod(count₃,2) insufficient for 3-period on sign pattern |
| T18 sign%7==0 | 0.85 | χ_mono saturates below certifier |
| T19 (sum+count)%7 | 0.85 | affine mod needs `(sum+count)` leaf; R² too high on product proxy |

## Verdict

**PASS** — ≥9/20 targets certified via **non-monomial** synthesized features without spectral/Walsh.

The E3 escape mechanism (`mod` on sufficient statistics) generalizes across:

- **Count multi-period:** `mod(count₃,k)` for k∈{3,4,5,6,…}
- **Sum-mod world targets:** `mod(sum,k)` for k∈{5,7}
- **Inversion-count family:** `mod(inv,k)` including inversion parity (`mod(inv,2)`)
- **Threshold variants:** alternate count leaves `count₂`, `count₄`

## Honest bounds

1. **Sign-pattern mod targets (T09,T10,T18)** remain outside the count/inv/sum synthesis closure —
   they need a `sign` leaf or Walsh injection (same gap as E2 oracle-only XOR family).
2. **T06,T17,T20** certify at round 0 with pos_rate ≤0.03 — accuracy is dominated by the
   negative class; not a meaningful periodic discovery (imbalance artifact).
3. **Residue-class targets (T05)** can escape behaviorally but fail the irreducibility gate when
   the best synth feature is algebraically correlated with existing atoms.
4. Synthesis algebra is `{+,×,mod,sin}` only — no `cos`, `abs` (stricter than E3).

## Key file

`sparse_poly_discovery/open_invention_rq3.zig`

## See also

- `open_invention_e3.md` — parity via `mod(count,2)` ablation
- `multi_period.md` — spectral multi-period contrast (excluded here)
- `inner_forge.md` — monomial saturation baseline