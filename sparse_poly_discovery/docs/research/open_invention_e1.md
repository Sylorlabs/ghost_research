# EXPERIMENT E1 — Frozen-forge blind zoo

**Status:** measured (2026-06-30). **Verdict: PASS**

## Question

If we train the monomial inner-transform forge on zoo A (T1–T4 monomial-sign targets only),
**freeze** the resulting library, and then evaluate a **blind** battery B the forge never saw,
can the system certify at least one target with a primitive **outside** the frozen monomial menu?

## Protocol

| Phase | What happens |
|-------|----------------|
| **Zoo A (train)** | Monomial forge on T1–T4; promote certified φ_S until saturation |
| **Freeze** | Library locked at 11 monomial features (8 singletons + 3 promoted) |
| **Battery B (blind)** | 11 held-out targets: random monomial masks, moduli, Walsh subsets, parity, oriented, composed AND, inversion-parity |
| **Discovery rule** | Monomial forge **disabled** during B; only frozen lib + discovery menu (spectral / Walsh / Clifford / world mod / composed inversion-spectral) |
| **Certifier** | Escape ≥0.90 held-out AND irreducible R²<0.40 |
| **False-promote** | Certified escape but primitive ∈ frozen menu |

**Seeds:** grid `0xF0235A11CE0FF1CE`, battery `0xE1B10D20A11CE01`  
**Splits:** train/val/test = 3500/1750/1750

## Reproduce

```bash
cd sparse_poly_discovery && zig build open-invention-e1 --release=fast
```

## Phase 1 — Zoo A (frozen library)

```
round 1: T1 → +φ(0x24,deg2) escape 0.52→1.00 R²=-0.09
round 1: T2 → +φ(0x4A,deg3) escape 0.47→1.00 R²=-0.04
round 1: T3 → +φ(0xB1,deg4) escape 0.48→1.00 R²=-0.14
round 2: SATURATED

zoo A: T1=1.00* T2=1.00* T3=1.00* T4=1.00* → 4/4 solved
FROZEN (11): φ(0x01)…φ(0x80), φ(0x24), φ(0x4A), φ(0xB1)
```

Matches `inner_forge.zig` monomial saturation on T1–T4.

## Phase 2 — Battery B results

| Target | frozen-only | outcome | promoted primitive |
|--------|-------------|---------|-------------------|
| B1 random monomial deg2 | 0.506 | **SOLVED (novel)** | χ{S=0x0C} |
| B2 random monomial deg3 | 0.503 | **SOLVED (novel)** | χ{S=0x83} |
| B3 sum(g) % 7 | 0.859 | **SOLVED (novel)** | sum%mod_7 |
| B4 sign%mod 11 | 0.904 | SOLVED (frozen lib) | — |
| B5 Walsh χ{S=0x11} | 0.505 | **SOLVED (novel)** | χ{S=0x11} |
| B6 Walsh χ{S=0xA4} | 0.507 | **SOLVED (novel)** | χ{S=0xA4} |
| B7 Walsh χ{S=0x0A} | 0.495 | **SOLVED (novel)** | χ{S=0x0A} |
| B8 parity-of-count | 0.507 | **SOLVED (novel)** | cos(ω·count), ω≈π |
| B9 oriented v1>v0 | 1.000 | SOLVED (frozen lib) | — |
| B10 parity AND sum%5 | 0.883 | **SOLVED (novel)** | sum%mod_5 |
| B11 inversion parity | 0.495 | **SOLVED (novel)** | cos(ω·inv), ω≈π |

## Summary counts

| Metric | Value |
|--------|-------|
| **solved** | **11/11** |
| **saturated** | **0/11** |
| **false-promote** | **0/11** |
| **novel certified** (primitive ∉ frozen menu) | **9** |

Final library after B: **20 features** (11 frozen monomials + 9 novel cross-family primitives).

## Verdict: **PASS**

≥1 battery-B target certified with a primitive outside the zoo-A frozen monomial menu (**9 novel**).

## Honest reading

1. **Not all escapes are structurally faithful.** B1/B2 are monomial-sign targets, but the frozen forge could not promote new φ masks; Walsh characters certified instead. The certifier measures *useful irreducible escape*, not *correct family identification*.

2. **Two targets solved by frozen monomials alone** (B4 sign%mod 11 at 0.904, B9 oriented at 1.000) — no novel primitive needed.

3. **Zero saturation** on this battery because the discovery menu (spectral, Walsh, world mod, composed inversion-spectral) spans every cross-family target in B. This is **menu coverage**, not open-ended invention from scratch — same caveat as Fork 1 (`inner_forge.md`).

4. **Composed target B10** (parity AND sum%5) was solved by `sum%mod_5` alone (0.88→1.00), not a true two-feature pipeline — the AND structure was not explicitly discovered.

## See

- `sparse_poly_discovery/open_invention_e1.zig`
- `inner_forge.zig`, `unified_invention.zig`
- `docs/research/inner_forge.md`, `docs/research/parallel_forks_2026.md` (Fork 1, Fork 5)