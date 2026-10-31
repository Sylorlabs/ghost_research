# Swarm EXP-16 (E39) — Escape-corollary counterexample hunt

**Date:** 2026-07-06  
**Status:** **COMPLETE** — five pathological cases constructed; four measured on fresh runs.  
**RQ:** E39 — Is there a closure where adding the **obvious** out-of-closure generator does **NOT** escape?

## Commands

```bash
# CE-1 synergy-only (single op fails, pair succeeds)
cd sparse_poly_discovery && zig build-exe -OReleaseFast synergy.zig -femit-bin=/tmp/ghost_synergy && /tmp/ghost_synergy

# CE-2 wrong generator on dual-band (SUM is obvious from single-band; fails here)
cd sparse_poly_discovery && zig build-exe -OReleaseFast dual_band_test.zig -lc -femit-bin=/tmp/dual_band_test && /tmp/dual_band_test

# CE-4 encoding mismatch (symmetric pairwise ≠ oriented predicate)
cd sparse_poly_discovery && zig build-exe -OReleaseFast antisymmetric_relational.zig -femit-bin=/tmp/antisym && /tmp/antisym

# CE-5 wrong outer + readout ceiling (band predicate outside XOR closure)
cd sparse_poly_discovery && zig build-exe -OReleaseFast dynamics_probe.zig -femit-bin=/tmp/probe && /tmp/probe

# CE-3 partial escape (ADD vs MUL) — documented; 05_meta_synthesis build blocked on missing core/src/absolute_final.zig
# Prior measured: 05_meta_synthesis/docs/07/closure_escape_mixer.md
```

---

## The corollary under test

From `CLOSURE_PRINCIPLE.md`:

> **Escape corollary.** Adding one out-of-closure generator collapses the plateau.

We hunt cases where a learner **has** a genuine closure ceiling, practitioners add what looks like the obvious escape generator, and the plateau **does not** fully collapse.

---

## Five pathological cases

| ID | Failure mode | Closed substrate | “Obvious” generator | Measured outcome | Counterexample? |
|----|--------------|------------------|---------------------|------------------|-----------------|
| **CE-1** | Synergy-only | Affine `{XOR,SHL,SHR,NOT}` | AND **or** SUB alone | `x&(x-1)`: neither single reaches; only `{AND,SUB}` pair does | **YES** (naive single-op corollary) |
| **CE-2** | Wrong generator | XOR VSA + single-band intuition | SUM readout | Dual-band: sum **83.31** fail/1k; `(sum,max)` **83.30**; best pair `(left,max)` **35.40** | **YES** |
| **CE-3** | Wrong outer / partial | Pure GF(2)-affine (SAC theorem) | ADD (carry) as “the” nonlinear | SAC-error: affine **0.50** → MUL-free+ADD **0.127** → +MUL **0.021** | **Partial** — escapes but does not collapse to ideal |
| **CE-4** | Encoding mismatch | XOR bundle + symmetric 2nd-order | Real pairwise `C₀⊙C₁` | Oriented `sign(v₁−v₀)`: pairwise **0.583** ≈ chance; grade-2 **1.000** | **YES** |
| **CE-5** | Wrong outer (two plateaus) | XOR/bundle readout closure | SUM feature (`mb_mass`) | Readout: XOR agents **33–163** → mb_mass **11.02**; task: tuned thermostat **0.00** | **YES** (if outer = task performance) |

---

## CE-1 — Synergy-only: obvious singles do not escape

**Harness:** `synergy.zig` (exact 256-input exhaustive, MAXL=3). Fresh run 2026-07-06.

Affine base reaches **0/5** nonlinear targets (closure ceiling confirmed). Emergent pair escapes:

```
  EMERGENT: x&(x-1)  via base+{AND,SUB}  — NOT base+{AND}, NOT base+{SUB}
  EMERGENT: x|(x*x)  via base+{OR,MUL}   — NOT base+{OR},  NOT base+{MUL}
```

Single-op power on `x&(x-1)`:

| Op added | Reaches target? |
|----------|-----------------|
| AND | no |
| SUB | no |
| AND+SUB pair | **yes** |

Greedy one-op growth on isolated `{x&(x-1)}`: **0/1** (never starts — components useless alone). Pair-search: **1/1**.

**Reading:** Each component **is** out-of-closure relative to affine, and each is the “obvious” nonlinear op to try. Adding either **alone** leaves the plateau intact. The true generator is an **irreducible pair** — a known refinement from `emergent_escape.md`, now re-verified.

---

## CE-2 — Wrong generator: SUM on dual-band

**Harness:** `dual_band_test.zig` (5000 steps × 4 seeds). Fresh run 2026-07-06.

Task: `total_mass ∈ [16,48]` **and** `left_mass ∈ [6,22]`.

| Policy | fail/1k | vs sum alone |
|--------|---------|--------------|
| mb_mass(**sum**) | **83.31** | — (plateau) |
| mb_mass(left_mass) | **39.02** | best single |
| mb_mass2(**sum, max_cell**) | **83.30** | **no gain** |
| mb_mass2(sum, left_mass) | **83.30** | no gain |
| mb_mass2(**left_mass, max_cell**) | **35.40** | true escape |

**Reading:** SUM is the canonical escape generator for single-band control (`closure_escape_control.md`: 162 → 11 fail/1k). On dual-band it is the **wrong** generator — the closure relative to the **new predicate** needs `(left_mass, max_cell)`, not sum. Adding the “obvious” generator from the parent task does not move the needle (~83 fail/1k on every sum-containing pair).

---

## CE-3 — Wrong outer: ADD partially escapes SAC, MUL completes it

**Harness:** `closure_escape_mixer` (blocked build; numbers from `05_meta_synthesis/docs/07/closure_escape_mixer.md`, 12k iters × 6 seeds).

| Mode | mean SAC-error | best SAC-error |
|------|----------------|----------------|
| Pure GF(2)-affine (theorem) | **0.500** | 0.500 |
| MUL-free (+ ADD carry) | **0.127** | 0.033 |
| MUL-enabled | **0.021** | 0.017 |

**Reading:** If the identified closure is “GF(2)-affine” and the obvious escape is “any nonlinear op,” ADD **does** escape the 0.5 theorem pin — but plateaus an order of magnitude above ideal. If the practitioner’s **outer goal** is “good SAC mixer” and they stop at ADD, the plateau has **not** collapsed. The load-bearing generator for full collapse is **MUL**, not ADD. This is a **partial** counterexample: escape started, collapse incomplete.

---

## CE-4 — Encoding mismatch: right order, wrong symmetry

**Harness:** `antisymmetric_relational.zig`. Fresh run 2026-07-06.

Predicate: `y = sign(v₁ − v₀)` (oriented; chance ≈ 0.577).

| Feature | test acc |
|---------|----------|
| Real pairwise sym `C₀⊙C₁` | **0.583** ← fails |
| Clifford grade-2 `geo[e₁₂]` | **1.000** ← wins |
| Ground truth `sin(θ(v₁−v₀))` | **1.000** |

On symmetric XOR sanity, grade-2 correctly scores **0.510** (useless).

**Reading:** Second-order binding is the right **degree** — but real pairwise product is **symmetric** and orientation-blind. It is the obvious generator if you only know “need interaction” without checking antisymmetry. It does **not** escape. Clifford grade-2 works because encoding (shared-basis angles) and predicate (orientation) share algebraic structure (`swarm_exp03_clifford_relational.md`).

---

## CE-5 — Wrong outer: SUM escapes readout closure, not task closure

**Harness:** `dynamics_probe.zig` + `swarm_exp10_thermostat.md`. Probe fresh run 2026-07-06; thermostat numbers from EXP-10.

### Readout closure (XOR substrate cannot see band)

| Readout | random enc | ordinal enc |
|---------|------------|-------------|
| nearest-prototype | 0.502 | 0.504 |
| best linear (8192b) | 0.513 | 0.510 |
| sum-threshold | **1.000** | **1.000** |

### Control performance (single-band `[16,48]`)

| Policy | fail/1k |
|--------|---------|
| XOR agents (`mb_safety` etc.) | 33–163 |
| **mb_mass (SUM)** | **11.02** |
| Grid-tuned thermostat | **0.00** |

**Reading:** SUM is out-of-closure for the **XOR readout** and collapses that plateau (chance → 11.02). Relative to **task-optimal control**, SUM does **not** escape — a one-line mass thermostat at 0.00 crushes mb_mass. Conflating “readout escape” with “beats hand-coded control” was the EXP-10 strawman correction. The generator was right for one outer, wrong for another.

---

## Synthesis: what breaks, what survives

### Counterexamples found?

**YES — four honest counterexamples to the naive corollary** (“add the obvious single generator → plateau gone”):

1. **Synergy-only** — singles fail, pair required (CE-1).
2. **Wrong generator for the predicate** — SUM on dual-band (CE-2).
3. **Encoding–predicate mismatch** — symmetric pairwise on oriented task (CE-4).
4. **Wrong outer identification** — SUM escapes XOR readout, not task optimum (CE-5).

CE-3 is a **partial** case: ADD escapes the theorem pin but not the practitioner’s target SAC.

### Does the closure principle survive?

**YES — with three refinements the hunt sharpens rather than falsifies:**

1. **Identify the correct closure *for the target*.** The generator obvious in one task (SUM on single-band) may be inert on another (dual-band). The ceiling is representational; the escape must match the **predicate**, not folklore from a sibling task.

2. **Generators can be irreducible tuples.** Some walls need **simultaneous** ops (`{AND,SUB}`). The escape corollary should read: “adding the needed generator **set** collapses the plateau,” with pair-search when greedy singles stall (CE-1, `emergent_escape.md`).

3. **Generator ⊗ encoding ⊗ predicate must align.** Leaving GF(2) escapes mass (Hadamard ≈ Clifford ≈ 0.97); oriented predicates need antisymmetric features, not generic second-order products (CE-4). Partial escapes (ADD vs MUL) mean “out-of-closure” is graded, not binary (CE-3).

### Practical decision rule (revised)

> When a plateau persists after adding a plausible generator, **before** abandoning the closure principle, check:
> - Is the generator correct for **this** predicate (not a parent task)?
> - Is a **pair** required (greedy 0/1, pair-search 1/1)?
> - Does the encoding expose the generator’s **symmetry class**?
> - Which **outer** are you measuring (readout accuracy vs control vs SAC)?

---

## Verdict

| Question | Answer |
|----------|--------|
| Counterexamples to naive escape corollary? | **YES** (4 strong + 1 partial) |
| Counterexamples to closure principle? | **NO** — every case is mis-identified generator, pair requirement, encoding mismatch, or wrong outer |
| Principle survives? | **YES**, refined: escape requires the **minimal correct generator set** aligned with predicate structure |

The valuable outcome is not breaking the principle but **bounding** it: “obvious generator” is not a well-defined operation without closure diagnosis. EXP-16 turns E39 from a falsification hunt into a **specification tightening** for the escape corollary.

---

## References

- `CLOSURE_PRINCIPLE.md` — statement + emergent-pair refinement
- `sparse_poly_discovery/docs/research/emergent_escape.md` — CE-1 origin
- `sparse_poly_discovery/docs/research/swarm_exp09_two_feature.md` — CE-2 dual-band
- `05_meta_synthesis/docs/07/closure_escape_mixer.md` — CE-3 ADD/MUL ladder
- `sparse_poly_discovery/docs/research/swarm_exp03_clifford_relational.md` — CE-4 encoding
- `sparse_poly_discovery/docs/research/swarm_exp10_thermostat.md` — CE-5 wrong outer