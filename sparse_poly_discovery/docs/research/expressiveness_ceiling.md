# Research note: is the world-model stuck in a linear basin?

**Status:** built, measured, **hypothesis falsified and corrected.** Reproduce
with `zig build probe` (means over 8 seeds × 8000 steps, error averaged over the
final fifth).

## The question

The agent's forward model is **XOR-affine**: it predicts `S_next = bind(S_t,
rule_a)` — the state XORed with a learned per-action offset. `bind`/`permute` are
**GF(2)-linear**. The project already has a theorem-grade precedent: the mul-free
mixer champions were all affine maps, so their statistical failure was a
Cayley–Hamilton consequence, not bad luck (`affine_closure`). The hypothesis here
was the analogue: the agent's *world model* is trapped in the same linear basin,
so it cannot predict nonlinear dynamics — and that caps how intelligent it can get.

**Predicted:** on synthetic XOR-affine dynamics (`S_next = bind(S_t,
true_offset_a)`), which are *inside* the model's representable class, error should
collapse to ~0; on the battery's real (non-affine) dynamics it should stay high.

## Results

```
  dynamics                     | steady-state pred error
  -----------------------------+------------------------
  xor_affine (stock rule)      | 0.2423
  xor_affine (pure attraction) | 0.0445
  battery_linear (stock rule)  | 0.4210
  battery_nonlinear            | 0.4338
```

## What actually happened — two ceilings, not one

**The prediction was wrong: the XOR-affine control floored at 0.2423, not ~0.**
The model could *not* fit dynamics it is perfectly capable of representing. The
cause is the **learning rule**, not the substrate:

`connectome.attractVectorsPtr` contains a *"forcefield repulsion if dist < 0.25"*
— a concept-separation mechanism that pushes two vectors apart once they get
within 0.25. Applied to forward-model learning it is self-defeating: the rule can
never converge closer than ~0.25 to its target, so prediction error is **floored
at ~0.25 regardless of the dynamics.**

The control case proves it: rerun the *same* XOR-affine learning with **pure
attraction** (repulsion removed) and error collapses **0.2423 → 0.0445** (5.4×).
The learner *can* reach near-zero error on representable dynamics; the stock rule
forbids it.

So there are two ceilings, in order of dominance:

1. **Learning-rule ceiling (~0.24, dominant, FIXABLE).** The 0.25 repulsion
   forcefield. Proven by the pure-attraction control (0.04).
2. **Representational gap (~0.18, secondary).** Battery_linear (0.42) sits above
   the affine-stock floor (0.24): real grid dynamics are not XOR-affine, so
   `bind`/`permute` cannot express them exactly. And `battery_nonlinear` (0.43) >
   `battery_linear` (0.42) — added nonlinear coupling costs a little more, the
   affine-closure effect, but it is small next to the learning-rule floor.

## Implication for "intelligence level"

The path to a better world-model (and thus to planning and higher competence) is
now ordered by evidence, not guesswork:

- **First, fix the learning rule** for forward-model offsets: the repulsion
  forcefield belongs to keeping *concept* vectors distinct, not to *prediction*.
  Removing/relaxing it for rule learning unlocks ~5× lower prediction error for
  free (CP3 tests whether that improves control).
- **Then** the GF(2) representational gap becomes the binding constraint, and the
  affine-closure prediction comes back into force: a genuinely nonlinear world
  will need a non-XOR binding or a nonlinear readout, because no amount of
  attraction makes a linear map fit a nonlinear function.

The honest contribution of this probe is the *ordering*: the obvious suspect
(GF(2)-linearity) is real but currently **masked** by a more proximate, cheaper
defect that an instrument — built to test the wrong hypothesis — surfaced anyway.
