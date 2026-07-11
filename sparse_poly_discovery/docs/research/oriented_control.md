# Oriented control — Clifford grade-2 (bivector) readouts on the real grid task
> **Belongs to: Doc gap-fill 2026-07-11 · RESEARCH_TOC §15 (oriented control; follows round-a A10)** — [round index](../../../RESEARCH_TOC.md).

**Status:** built, measured. Reproduce: `cd sparse_poly_discovery && zig build oriented-control`
(80k train / 10k frozen-eval steps, mean of 8 seeds, single-threaded, ~seconds).

## Why this exists (closes an A10 open question)

`a10_clifford_binding.md` showed that a magnitude-carrying (Clifford / real
Hadamard) binding breaks the XOR/bundle 0.51 readout ceiling on the toy band
predicate — but its deflation control found the lever was **"leave GF(2)"**, not
the geometric product specifically, and it explicitly flagged: *Clifford's
grade-2 (bivector / relational) capacity was not exercised on the
mass-symmetric predicate — needs a two-sided/relational task.*

This experiment exercises exactly that. It applies a shared Cl(2,0) encoding
(`C_i = cos(θv_i)e1 + sin(θv_i)e2`, θ=0.40) to the **real** grid-cell battery
control agent — a task whose dynamics **are** oriented (charge → anode(0),
discharge → cathode(15), rest → uniform decay) — and compares a plain pooled
**sum** readout (the mb_mass baseline) against **grade-2 bivector** readouts
that can see local gradients and left–right asymmetry.

Pre-registered hypotheses: H1 sum solves single-band; H2 bivector is irrelevant
on single-band (orientation doesn't matter when the constraint is on total
mass); H3 on dual-band, sum alone struggles and an oriented bivector readout
*might* help because a per-half-grid mass constraint is a distributional feature.

## Result (fail/1k, lower is better; 8-seed mean)

| readout | single-band | dual-band | dim |
|---------|-------------|-----------|-----|
| sum (mb_mass) | **19.80** | **35.10** | 2 |
| biv_chain (15 adjacent bivectors) | 50.70 | 77.73 | 16 |
| biv_lr_mass (sin θ(left−right)) | 55.51 | 83.30 | 2 |
| biv_geo_lr | 55.51 | 83.30 | 2 |
| biv_focal(0,8) | 55.51 | 83.30 | 2 |
| thermostat (hand-coded sum-only) | 20.80 | 83.30 | — |

- **H1 confirmed:** sum solves single-band (19.80, beating the 20.80 thermostat).
- **H2 confirmed:** every bivector readout is far worse than sum on single-band
  (50.70 vs 19.80). Orientation is irrelevant when the constraint is total mass.
- **H3 refuted:** on dual-band the sum readout (35.10) *still* beats every
  bivector readout (best 77.73) — the grade-2 encoding does not help even where
  the dynamics are oriented.

## Verdict

**Clifford grade-2 does not transfer from the toy oriented predicate to the real
control task — and the reason is precise, not a budget artifact.** Grade-2 wins
decisively on a *toy* oriented target (antisymmetric-relational scores 1.000 on
`sign(v1−v0)`, Frontier 3). But the grid task's *measured failure modes* are
mass-band constraints that are predominantly **symmetric aggregates**: even
though the environment's dynamics have orientation (directional charge flow),
what the controller must satisfy is a constraint on total (or per-half) mass, for
which a pooled scalar is the matched readout and orientation is noise.

This is the honest closure of A10's caveat: exercising Clifford's relational
capacity on a real task confirms that **the escape lever was "leave GF(2)," not
the geometric product** — the grade-2 machinery only pays when the *target
constraint itself* is oriented, and the real control constraint is not. Dual-band
would be better served by an explicit `left_mass` scalar (mb_mass left_mass ~39
fail/1k) than by a Clifford bivector. The structural lesson generalizes: an
oriented *environment* does not imply an oriented *objective*; readouts must be
matched to the constraint's symmetry, not the dynamics'.

## Files
- `sparse_poly_discovery/oriented_control.zig` — the experiment (`zig build oriented-control`)
- Links: [[a10_clifford_binding]] (the ceiling-break this refines), the Frontier-3
  antisymmetric-relational toy result it contrasts against.
