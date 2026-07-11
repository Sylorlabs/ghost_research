# RESEARCH Q1 — E1 blind battery WITHOUT handed menu

**Status:** measured (2026-06-30). **Verdict: PASS** (6/11 certified ≥0.90)

## Question

E1 solved **11/11** battery-B targets, but **9/11 escapes used the handed menu** (spectral peak,
Walsh χ_S, Clifford, world pool). RQ1 asks:

> With the **same** frozen monomial forge and **same** battery B, can we certify targets using
> **only** count program synthesis `{+,×,sin,mod}` and E5-style composed pipelines — with spectral,
> Walsh, Clifford, and world pool **removed**?

## Protocol

| Phase | What happens |
|-------|----------------|
| **Zoo A (train)** | Monomial forge on T1–T4; promote φ_S until saturation; **freeze** |
| **Battery B (blind)** | 11 E1-pattern targets (seed `0xE1B10D20A11CE01`) |
| **Allowed discovery** | Frozen monomials + count synth (depth≤4, `{+,×,sin,mod}`) + E5 pipelines (7×7 inner₁×inner₂) |
| **Excluded** | Spectral peak, Walsh χ_S, Clifford, world pool, new monomial promotions |
| **PASS bar** | ≥1/11 battery B certified at held-out test ≥0.90 |

**Seeds:** grid `0xF0235A11CE0FF1CE`, battery `0xE1B10D20A11CE01`  
**Splits:** train/val/test = 3500/1750/1750

## Reproduce

```bash
cd sparse_poly_discovery && zig build open-invention-rq1 --release=fast
```

(~30 s ReleaseFast on measured host)

## Phase 1 — Zoo A (frozen)

```
round 1: T1→+φ(0x24)  T2→+φ(0x4A)  T3→+φ(0xB1)
round 2: SATURATED → FREEZE

zoo A: 4/4 solved
FROZEN: 11 monomials (8 singletons + φ(0x24), φ(0x4A), φ(0xB1))
```

Identical to E1 phase 1.

## Phase 2 — Battery B results

| Target | Known family | frozen | best method | test acc | faithful? |
|--------|--------------|--------|-------------|----------|-----------|
| B1 random mono deg2 | monomial φ_S | 0.506 | — | 0.514 | — **SAT** |
| B2 random mono deg3 | monomial φ_S | 0.501 | — | 0.509 | — **SAT** |
| B3 sum(g)%7 | world sum%mod | 0.859 | pipeline `sum_all→scan_p` | **0.998** | ~ (periodic, not mod) |
| B4 sign%mod 11 | world sign%mod | **0.905** | frozen | **0.905** | ~ (accidental monomial?) |
| B5 Walsh χ{0x11} | Walsh χ_S | 0.495 | — | 0.530 | — **SAT** |
| B6 Walsh χ{0xA4} | Walsh χ_S | 0.512 | — | 0.538 | — **SAT** |
| B7 Walsh χ{0x0A} | Walsh χ_S | 0.491 | — | 0.535 | — **SAT** |
| B8 parity-of-count | Z₂ on count | 0.501 | synth `mod(count,2)` | **1.000** | ✓ |
| B9 oriented v1>v0 | relational | **1.000** | frozen | **1.000** | ✓ |
| B10 parity∧sum%5 | AND(Z₂, sum%mod) | **0.910** | frozen | **0.910** | ~ |
| B11 inversion parity | Z₂ on inversion | 0.477 | pipeline `inversion→half_p` | **1.000** | ✓ |

## Summary counts

| Metric | RQ1 (no menu) | E1 (handed menu) |
|--------|---------------|------------------|
| **certified ≥0.90** | **6/11** | 11/11 |
| **saturated** | **5/11** | 0/11 |
| **faithful family match** | **3/6** | partial (Walsh mislabels on monomials) |

### Certified escapes by mechanism

| Mechanism | Targets | Primitives discovered |
|-----------|---------|----------------------|
| Frozen monomial only | B4, B9, B10 | (no new primitive) |
| Count synthesis | B8 | `mod(count,2)` |
| E5 pipeline | B3, B11 | `sum_all→scan_p(ω≈0.884)`; `inversion→half_p` |

## Verdict: **PASS**

≥1/11 battery B certified without spectral/Walsh/Clifford/world menu (**6/11**).

## Honest reading

### What works without the handed menu

1. **Z₂ / parity structure** — B8 and B11 are the clean wins. `mod(count,2)` (E3 path) and
   `inversion→half_p` (E5 path) discover the correct readout **without** named Fourier routing.
   This replicates E3 + E5 on battery-relevant targets.

2. **Periodic sum structure** — B3 `sum%7` escapes via `sum_all→scan_p` (cos ω·S). This is
   allowed under E5 pipelines but is **spectral-class** readout on a scalar — not `sum%mod_7`
   from the world pool. Useful escape, wrong family name.

3. **Some targets accidentally in frozen monomial closure** — B4 (sign%mod 11), B9 (oriented),
   B10 (parity∧sum%5) reach ≥0.90 on frozen monomials alone. B10 at 0.910 is surprising and may
   reflect label correlation on this grid seed, not principled AND decomposition.

### What fails (expected)

1. **Walsh χ_S family (B5–B7)** — all saturate at ~0.50. Without Walsh generator or χ_mono
   promotion, linear readout on monomials + count synth + pipelines cannot recover arbitrary
   parity functions on sign patterns.

2. **Unseen monomial masks (B1–B2)** — forge is frozen; no new φ_S promotions. Synth and
   pipelines cannot substitute for the missing monomial degree.

### Comparison to E1

| | E1 | RQ1 |
|---|----|-----|
| Solve rate | 11/11 | 6/11 |
| Novel primitives | 9 | 2 principled (`mod(count,2)`, `inversion→half_p`) + 1 periodic pipeline |
| Walsh / world | handed menu | **blocked → saturate** |
| Anti-remix claim | weak (handed) | **stronger** for Z₂; gap exposed for Walsh/world |

### Research conclusion

**PASS on the bar, PARTIAL on coverage.** Removing the handed menu drops solve rate from
**100% → 55%**. The 5 saturated targets are exactly the families that required Walsh, world mod,
or new monomial masks in E1. The surviving escapes (parity, inversion, periodic-sum) are
**principled** — discovered via synthesis and pipelines, not operator-menu routing.

RQ1 confirms: **E1's broad blind success was substantially menu-assisted**; E3+E5 alone suffice
for Z₂ and some periodic scalars but **cannot** invent Walsh or mod-world families from void.

## References

- `open_invention_e1.md` — full battery with handed menu (11/11)
- `open_invention_e3.md` — `mod(count,2)` without Fourier menu
- `open_invention_e5.md` — composed pipeline discovery
- `docs/research/open_invention_experiments.md` — master experiment index