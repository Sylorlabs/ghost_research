# H3 — direct grammar proposer under equal candidate budget

**Verdict: constrained positive, with an important ceiling.** The generic
failure signature admitted a directed grammar and validation selection found an
exact candidate on all three measurement seeds and the held-out structural
variant. It defeated the global threshold menu at equal *evaluation calls*.
Against an equally budgeted blind directed search, it was deterministic (4/4)
where random exact-hit frequency was 0.484–0.734 across 64 trials per data
set. That is meaningful aiming inside the supplied grammar, but not escape
from a 1,270-member search space: blind search is still competitive whenever
it happens to draw the exact member.

This scoped H3 harness tests a narrow proposition: after the pre-existing
global threshold menu fails, can labelled *failure behaviour* open a generic
directed-partition grammar and select its parameters without an inference-time
target name, formula, family, anchor, or residue? It is not primitive
invention: the compare/partition/count/modulo alphabet is frozen human input.

## Pre-registered contract

- 6,000 iid eight-cell grids per run; fixed 3,000/1,500/1,500
  train/validation/test slices.
- Three measurement seeds plus a held-out structural variant: the measurement
  label is a rank-mod-3 predicate and the holdout changes both pivot and
  modulus. The generator creates labels; `propose([]Sample)` cannot receive
  either definition or any semantic target metadata.
- Grammar admission requires two generic behavioural observations only: best
  global threshold-count candidate <0.75 validation accuracy and a symmetric
  singleton orientation-probe response >=0.75. This admits a *grammar class*,
  not an anchor or answer.
- If admitted, the directed grammar is enumerated symmetrically over 254 masks
  and all mod-2/mod-3 residues: exactly 1,270 validation evaluations.
- **Equal-budget controls:** fixed menu receives 1,270 evaluation calls
  (cycling its legal global threshold members); random directed search receives
  1,270 iid legal candidates. All arms record their raw ledger. Because blind
  random may occasionally hit the exact member, 64 additional equal-budget
  random trials report its exact-hit frequency; a one-off random tie is not
  treated as evidence that random routing is reliable. Selection reads
  validation only.
- G1-compatible certification evidence is a candidate-excluded multi-feature
  reconstruction proxy (global threshold count + global inversion residue,
  trained on the train slice) evaluated only on test. Its decision rule matches
  the v6 direction: COVER >=0.90 rejects as remix; below COVER admits. It is a
  local proxy, **not** a claim that G1's live greedy COVER has been wired.

## Required gates

Binary base rate must be strictly 0.10–0.90; the direct proposal must pass its
signature, reach >=0.90 on validation and test, beat both equal-budget arms,
and remain below candidate-excluded COVER 0.90. A no-signature ablation may
only retain the fixed threshold menu. Any failed gate makes the result a
negative/inconclusive instrument outcome, never a promotion.

## Reproduction

```bash
cd /home/micah/Desktop/Sylorlabs/ghost_research/sparse_poly_discovery
zig build-exe direct_proposer_round_h.zig -O ReleaseFast -femit-bin=direct_proposer_round_h
./direct_proposer_round_h
```

The executable writes `results/direct_proposer_round_h.csv`; its summary rows
are the authoritative outcome and its preceding rows are the raw three-arm
candidate ledger.

## Results

| split | selected mask / mod / residue | validation | test | fixed-menu validation | one random draw | random exact-hit rate (64 x 1,270) | excluded-cover proxy | gates |
|---|---|---:|---:|---:|---:|---:|---:|---|
| measurement `...0001` | `0x08 / 3 / 1` | 1.000 | 1.000 | 0.637 | 0.673 | 0.484 | 0.695 | pass |
| measurement `...0002` | `0x08 / 3 / 1` | 1.000 | 1.000 | 0.644 | 1.000 | 0.641 | 0.705 | pass |
| measurement `...0003` | `0x08 / 3 / 1` | 1.000 | 1.000 | 0.649 | 1.000 | 0.641 | 0.681 | pass |
| held-out pivot/modulus variant `...00A4` | `0x20 / 2 / 0` | 1.000 | 1.000 | 0.611 | 0.628 | 0.734 | 0.606 | pass |

The two one-off random ties are retained in the raw ledger. They are why the
claim is not “direct search beats random on every run.” The correct result is
reliability: failure-guided grammar admission reaches the selected member in
all four fixed data sets, while blind equal-budget sampling reaches it in
roughly one-half to three-quarters of trials. Fixed threshold search never
approaches the direct candidate.

## Ablation and limits

The no-signature ablation is restricted to the pre-existing threshold menu and
therefore remains near the listed fixed values; it cannot silently open the
directed grammar. The candidate-excluded reconstruction proxy remains below
G1's `COVER=0.90` rejection bar in all four runs, so the candidate is admitted
under the proxy. This is compatible with G1's intent, not a live v6
integration claim.

This remains a constrained grammar-level result. The human supplied the
partition/comparison/modulo primitives, the generic orientation probe, and the
finite candidate grammar. The held-out case is a structural *variant*, not a
new primitive family. H5 must still measure live gate-v6 behaviour, and an
end-to-end wave may use this result only as a proposer option—not proof that
the human structural-language limitation is gone.
