# Experiment E6 — k≥3 substrate open forge (kary_frontier regime)

**Status:** built, measured. Reproduce:
`cd sparse_poly_discovery && zig build-exe open_invention_e6.zig -OReleaseFast -femit-bin=zig-out/bin/ghost_open_invention_e6 && ./zig-out/bin/ghost_open_invention_e6`
(~2–3 min). Build step: `zig build open-invention-e6 --release=fast` (may fail if unrelated e4 target is broken).

## The question

`kary_frontier.md` names the **k≥3 cliff**: closure lattices jump to a continuum — no finite Post fingerprint.
`k3_substrate.zig` / `k3_order_escape.zig` show a **richer handed pool** (modK + order-stats) can escape
*designed* targets (T5 mod3, T6 median) while still **saturating**.

E6 asks the next question: with that richer pool and an **open** certified-promotion forge (as in
`inner_forge.zig`), but **without** the Boolean Fourier / Walsh operator menu, can the forge solve
**random alien targets** drawn from families outside the pool (multiplicative, affine, parity-on-count,
range, lex, …)?

## Setup

| piece | detail |
|---|---|
| Substrates | k=3 and k=4 grids, 8 cells, 5000 samples |
| Pool | Centered monomials (deg≤4) + modK pair/triple/global + order-stats (median, rank, min, max, spread) |
| **Excluded** | Spectral count-Fourier, Walsh χ_S (`inner_forge.zig` Fork 1 escape hatch) |
| Targets | 8 random aliens per k, seed `0xE601CEF0A6B33D00` (+k offset for grid) |
| Alien cert | Structural (family ∉ pool) + base singleton coverage < 0.70 + non-degenerate class balance |
| Promotion | Irreducible (held-out R² < 0.40) AND useful (lifts target ≥ 0.90 test) |

### Alien families (outside handed pool)

- `mul_mod(i,j)==t`, `prod_mod(i,j,k)==t` — multiplicative modK
- `aff(i,j)==t` — `(2·c_i + c_j) mod K`
- `sq_mod(i,j)==t` — `(c_i²+c_j²) mod K`
- `range(i,j,k)==t` — max−min on triple
- `count(c==v)==n` — global counting
- `parity_high` — parity of #{cells ≥ K/2}
- `c_i > c_j` — lexicographic comparison

## Results (pinned seed)

### k=3 aliens

```
A1: parity_high        base=0.49  → final 0.49
A2: range(5,6,3)==1    base=0.51  → final 0.51  (best candidate spread−mid escape 0.86 — not certified)
A3: count(c==1)==3     base=0.69  → final 0.69
A4: aff(5,2)==2        base=0.60  → final 0.60
A5: aff(1,7)==1        base=0.66  → final 0.66
A6: aff(2,5)==0        base=0.67  → final 0.67
A7: range(1,3,0)==1     base=0.52  → final 0.52
A8: parity_high        base=0.49  → final 0.49

forge: 0/8 solved; saturated round 1; atoms stayed 8
```

### k=4 aliens

```
A1: count(c==3)==2     base=0.65  → final 0.65
A2–A3,A6–A7: parity_high  base=0.51  → final 0.51
A4: sq_mod(2,2)==2     base=0.63  → final 0.63
A5: count(c==0)==2     base=0.69  → final 0.69
A8: count(c==1)==2     base=0.64  → final 0.64

forge: 0/8 solved; saturated round 1; atoms stayed 8
```

### Aggregate

```
solve rate:                 0/16  (0.0%)
certified alien promotions: 0 (no non-monomial primitive promoted)
```

## Verdict

**FAIL for open invention in the k≥3 regime without Fourier.**

The handed k-ary pool solves the **curated** zoo in `k3_substrate.zig` (6/6 with full pool) but solves
**none** of 16 random aliens from cross-family generators (multiply, affine, count, parity-on-threshold).
Promotion saturated immediately: candidates were found (e.g. `spread−mid` at 0.86 on A2) but none met the
certified escape bar (≥0.90 held-out test + irreducibility).

**Honest reading:** Uncountable clones (Janov–Mučnik) describe *where the map ends*; they do **not** grant
unbounded forge growth. Richer substrate moves the ceiling on **designed** targets; **random** aliens still
need generators outside the pool — the same closure law as Boolean `inner_forge.md`, now at k≥3.

**No certified alien primitive.** Zero promotions passed both certifiers. The forge did not mint a new
family; it never left the 8 singleton base.

## Contrast with related forks

| experiment | substrate | menu | targets | solve rate |
|---|---|---|---|---|
| inner_forge | k=2-ish cells 0..5 | **Walsh/spectral** | fixed T1–T5 | 5/5 with menu |
| k3_substrate | k=3 pool | none | fixed T1–T6 | 6/6 full pool |
| **E6** | k=3,4 pool | **none** | random aliens | **0/16** |

k≥3 richness is necessary but not sufficient for open invention on unknown predicates.

## Honest scope

- Targets are random within **named alien families**, not plain English.
- Alien certification is **structural** (family ∉ atom enum), not an exhaustive solo-feature scan.
- No Walsh/Fourier was offered by design — this is the ablation point.
- Empirical probe of `kary_frontier.md`, not a proof about Rosenberg clones.

## See also

`k3_substrate.zig`, `k3_order_escape.zig`, `kary_frontier.md`, `inner_forge.md`, `open_invention_e3.zig`
(no-Fourier ablation on Boolean), `CLOSURE_PRINCIPLE.md`, `inventable_substrate_design.md`.