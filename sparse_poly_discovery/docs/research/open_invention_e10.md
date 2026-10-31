# EXPERIMENT E10 — Novelty-only forge vs usefulness (wcore tension)

**Status:** measured (2026-06-30). **Verdict: tension confirmed**

## Question

If the open monomial forge promotes atoms by **algebraic irreducibility alone** (held-out R²<0.40,
no escape / no target accuracy), how useful are the resulting atoms on **random** monomial-sign
targets the forge never optimized for? Contrast with the **usefulness-driven** forge from
`inner_forge.zig` (irreducible **and** escape ≥0.90 on an unsolved zoo target).

This is the wcore **novelty ↔ usefulness tension** (§21–22, `alien_novelty_limit.md`) measured
with numbers instead of a 3-round sidebar.

## Protocol

| Phase | What happens |
|-------|----------------|
| **A — novelty-only forge** | Start from 8 singletons; each round promote the **most-irreducible** non-atom φ_S (deg 2–4) if R²<0.40. **No target**, no escape cert. Stop at saturation or atom cap. |
| **B — random battery** | 128 unique random `sign(φ_S)` targets (deg 2–4), seed-pinned. Score each with logistic readout over the forged library; hit = held-out test ≥0.90. |
| **Control — useful forge** | Same grid; inner_forge objective (irreducible **and** escape) on structured zoo T1–T5. |
| **Zoo check** | T1–T5 coverage with each library (parity T5 is not a monomial sign). |

**Seeds:** grid `0xF0235A11CE0FF1CE`, battery `0xE10BA771E0000001`  
**Splits:** train/val/test = 3500/1750/1750  
**Certifier (forge):** irreducible R²<0.40 only  
**Usefulness threshold:** held-out test acc ≥0.90

## Reproduce

```bash
cd sparse_poly_discovery && zig build open-invention-e10 --release=fast
```

(~45 s, `--release=fast`)

## Phase A — novelty-only forge

```
promoted (beyond singletons): 16
final atom count:             24  (saturated at cap)
```

The driver filled the atom budget with high-degree irreducible monomials **without** consulting any
target. This is strictly more promotion pressure than the 3-round contrast in `inner_forge.md`.

## Phase B — random-target battery

| Library | hits | rate |
|---------|------|------|
| singletons only (8 deg-1) | 0/128 | **0.0%** |
| novelty-forged (24 atoms) | 14/128 | **10.9%** |
| useful-forged (11 atoms) | 2/128 | **1.6%** |

## Structured zoo (T1–T5)

| Library | solved |
|---------|--------|
| novelty-forged | **2/5** |
| useful-forged | **4/5** |

Useful forge matches `inner_forge.md` monomial phase (4/4 monomial signs + T4 base-covered; T5 parity
still at chance without operator menu).

## Tension metrics

| Metric | novelty-only | useful (control) |
|--------|--------------|------------------|
| **promoted count** | **16** | **3** |
| **random-battery hit rate** | **10.9%** (14/128) | **1.6%** (2/128) |
| **zoo hit rate** | **40%** (2/5) | **80%** (4/5) |
| **zoo per promotion** | 12.5% | 133% |

## Verdict: **tension confirmed**

1. **Novelty-only produces many atoms, few structured solves.** Sixteen promotions yield only **2/5**
   on the inner_forge zoo — vs **3 promotions → 4/5** for the fused objective. Per-promotion zoo
   efficiency: **12.5%** vs **133%**.

2. **Random-battery hits are low and misleading if read naïvely.** 10.9% on 128 random monomial signs
   is not “useful invention” — it is mostly **breadth overlap** from promoting many high-degree masks
   (more atoms ⇒ more accidental mask collisions). The **useful** library scores **lower** on the random
   battery (1.6%) because it concentrated on **three** zoo-aligned masks (0x24, 0x4A, 0xB1), not on
   covering random sign(φ_S).

3. **Singleton baseline is zero** on deg≥2 random targets — any hit requires promoted atoms; novelty
   promotion does not collapse to uselessness on *every* random task, but it does **not** substitute for
   task-grounded escape on structured or adversarial targets.

4. **Replicates wcore §21–22 in this substrate:** one fitness gives open-ended relative novelty
   (irreducibility) **or** concentrated usefulness (escape) — fusing both (`inner_forge` objective)
   sharpens the climb; neither repeals the monomial bottom (T5 still needs the operator menu).

## Honest caveats

- Novelty forge ran to **atom cap (24)**; useful forge stopped at monomial saturation (11 atoms).
- Random battery uses **monomial-sign** targets only — same family as the forge primitives, so 10.9% is
  an upper-friendly measure; cross-family targets (parity, Walsh) would score lower without menu escape.
- Battery logistic fit uses 80 epochs (forge/zoo use 150) — separations are 0/1.0 so this is not
  load-bearing.

## See

`inner_forge.md` (3-round novelty contrast, 1/5 zoo), `inventable_substrate_design.md` (tension
design), `wcore/docs/research/alien_novelty_limit.md` §21–22, `CLOSURE_PRINCIPLE.md`.