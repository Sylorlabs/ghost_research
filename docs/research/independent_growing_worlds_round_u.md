# Round U / U3 — Independent Growing Worlds

**Classification:** DONE — CONTROLLED GROWING-WORLD FOUNDATION. This is a
world-side substrate and isolation result, not intelligence, open-ended growth,
or evidence that a learner transfers.

## Question and separation

Can an evaluator grow viable and structurally varied raw worlds without a
named task family, text, a human curriculum, or reuse of the learner's
topology?

`sparse_poly_discovery/independent_growing_worlds_round_u.zig` implements a
locally original seeded byte-field stencil. Its world genotype is six scalar
growth coordinates plus a seed: active dimensions, ring-history delay,
interaction radius, composition depth, distraction channels, and observation
mask. Execution is a fixed evaluator-side delayed array sweep. It does not
import or inspect U1, a learner cell graph, mutation operator, mechanism bytes,
or Ghost Engine code. The deliberate shared-topology sentinel is rejected.

The installed bias is explicit: byte arithmetic, a maximum eight-channel field,
four history slots, the mutation ranges, rollout length, and fixed admission
thresholds are human supplied. Therefore this result cannot establish
self-created worlds without a substrate.

## Lifecycle and evaluator boundary

Forty-eight candidates begin in scratch and are derived from retained lineage.
Admission uses only measured outcome balance (neither free nor empty), reachable
response diversity, distinguishing power against the parent, and duplicate /
contamination rejection. There is no policy-visible target, answer, family,
solution trajectory, or world seed.

Only after the lineage closes does the evaluator combine a separately seeded
root with an opaque frozen-mechanism digest and generate the fresh holdout. The
public ledger exposes neither its ID, seed, genotype, response signatures, nor
metrics. Raw channel permutation and invertible affine byte re-encoding are
performed and checked privately.

This follows Ghost's evidence discipline conceptually: scratch candidates are
discardable, accepted lineage commits, and the closure is a replayable
snapshot. No Ghost source or solution primitive is imported or modified.

## Result

Canonical ledger: `results/independent_growing_worlds_round_u.csv`.

- 48 candidate descendants measured; **41 committed**, **7 rejected**.
- Growth spans dimensions, delayed effects, interaction radius, composed
  updates, distractors, and partial observation masks.
- Five free/trivial and two empty/impossible candidates were rejected.
- The independently derived holdout was created after freeze and stayed private.
- Normal replay is byte-identical; collapsed growth, replayed descendants, and
  deliberately shared learner topology each admit zero descendants.

The high admission rate means this deterministic fixture readily makes viable
variants; it is not evidence of unbounded novelty or escalating difficulty.

## Adversarial controls

| Control | Result |
|---|---|
| Deterministic lineage | byte-identical normal ledgers |
| Collapsed growth | all 48 rejected |
| Replayed descendants | all 48 rejected as duplicates |
| Shared-topology sentinel | all 48 rejected |
| Trivial / impossible | 5 / 2 rejected in canonical run |
| Raw permutation / affine re-encoding | three private signatures remain distinct |
| Private-field scan | no answer, mechanism bytes, learner cells, or private seed tokens |
| Hidden holdout | generated after freeze; identity, genotype, metrics and signatures withheld |

## Reproduce

```bash
mkdir -p /tmp/u3-zig-global /tmp/u3-zig-local
env ZIG_GLOBAL_CACHE_DIR=/tmp/u3-zig-global ZIG_LOCAL_CACHE_DIR=/tmp/u3-zig-local \
  zig build-exe sparse_poly_discovery/independent_growing_worlds_round_u.zig \
  -O ReleaseSafe -femit-bin=/tmp/u3
/tmp/u3 selftest
/tmp/u3 run results/independent_growing_worlds_round_u.csv
```

## Verdict and dependency

U3 passes its bounded foundation gate: independently implemented worlds grow
along all required axes, measurement-based admission and adversarial controls
replay, and a post-freeze holdout stays evaluator-private. U3 supplies no claim
that U1 can solve or transfer across these worlds. U4 should unlock only if the
coordinator also verifies that U1's actual representation shares no generator
structure and transfers under the raw permutation/re-encoding controls, and U2
establishes earned rather than inherited experience.
