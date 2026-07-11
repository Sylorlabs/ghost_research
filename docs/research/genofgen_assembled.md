# F5 — assembled generator-of-generators

> **Belongs to Round 2026-07-11b, experiment F5.** Harness:
> `sparse_poly_discovery/genofgen_assembled.zig`.

## Verdict

**The assembled autonomous loop coheres, but does not equal the hand oracle and
does not yet establish a generator-of-generators ceiling win.** Across three
fixed seeds it reproduces the hand arm on all established batteries (B 10/11,
C 11/11, D 11/11) and on the frontier (8/10), while solving 18/30 family-pool
targets versus the hand arm's 19/30. That is 58/73 total versus 59/73. Removing
smart generation collapses the frontier to 3/10 and the family pool to 1--2/30;
the representability-expansion stage is therefore load-bearing. Removing the
router preserves the 58/73 ceiling but raises mean evaluations by 48.3%, so the
router contributes aim/efficiency rather than reach.

This is a positive integration result and a negative autonomy-equivalence
result. The machine assembles and promotes useful families in one pass, but the
remaining one-target gap, the inherited novelty-gate error, and a blind control
that also crosses the conjunction wall prevent the stronger claim.

## Protocol

The harness runs a 73-target battery: established B/C/D (11 each), 30 labeled
minority targets used to make family routing learnable, and 10 fresh frontier
targets. All arms share the same 7,000 examples, 3,500/1,750/1,750
train/validation/test discipline, 0.90 certification bar, novelty basis, and
per-family candidate budget. Three deterministic seeds were run.

The four arms are:

- `hand`: oracle-select the target's true family.
- `autonomous`: learned family ranking, structural-signature probe, exhaustive
  family search, certification, and within-pass promotion.
- `auto_nosmartgen`: autonomous with no family discovery/promotion.
- `auto_norouter`: smart generation with fixed family order.

"Equal budget" here means equal candidate budget when a family is searched,
not equal total evaluations. The hand arm has oracle routing and is consequently
much cheaper; the ablations measure the autonomous loop's actual search cost.

## Three-seed results

| arm | B | C | D | family pool | frontier | total | mean evals |
|---|---:|---:|---:|---:|---:|---:|---:|
| hand | 10/11 | 11/11 | 11/11 | 19/30 | 8/10 | **59/73** | 12,738 |
| autonomous | 10/11 | 11/11 | 11/11 | 18/30 | 8/10 | **58/73** | 30,546 |
| auto_nosmartgen | 10/11 | 11/11 | 11/11 | 1--2/30 | 3/10 | **36--37/73** | 29,137 |
| auto_norouter | 10/11 | 11/11 | 11/11 | 18/30 | 8/10 | **58/73** | 45,029 |

The learned router's leave-one-out top-1 accuracy was 0.651, 0.683, and 0.619
(mean 0.651). Despite modest top-1 classification, its ordered search reduces
mean evaluations from 45,029 to 30,546 (32.2%) without reducing solved count.
Conversely, smart generation adds 21--22 solved targets over `auto_nosmartgen`:
16--17 family-pool targets and five frontier targets.

### Frontier detail

All three seeds give the same frontier count and qualitative result:

- The autonomous loop certifies MIXMOD1, RATIO1, ORDER2,
  ORDER2_MOD3, RANK2_MOD3, and all three distinct-count wall targets.
- ORDER2, previously described as an E1 logistic-family frontier, is exactly
  GF(2)-linear under the assembled dictionary; integration resolves it at
  1.000 test accuracy. ORDER2_MOD3 and RANK2_MOD3 require the promoted rank
  family and also reach 1.000.
- MIXMOD2 remains below the certification bar even for the hand oracle
  (test accuracy 0.755--0.766), so this is representability/search failure,
  not router failure.
- RUN1's run-family candidate reaches 1.000 test accuracy in the hand arm but
  is rejected by the inherited single-column R2 novelty gate (R2 0.605). This
  is the exact over-rejection independently diagnosed by F3; F5 preserves it
  rather than changing the gate after seeing the result.

## Structural-steering diagnostic

On WALL_HARD, the signature-steered conjunction search certifies exactly at
1.000 validation/test accuracy after 404 evaluations. However, all three blind
equal-post-probe-budget controls also certify (0.9754 validation,
0.9794 test). Thus the assembled experiment does **not** reproduce E3's claimed
blind-versus-steered reach gap in this grid analogue. Steering improves the
witness quality, but is not necessary to cross this particular wall.

## Interpretation

The clean causal result is:

1. Family discovery/promotion supplies reach: without it, frontier coverage is
   3/10; with it, 8/10.
2. Learned routing supplies efficiency: the same 58/73 ceiling at 32.2% fewer
   evaluations than fixed ordering.
3. The components do not destructively interfere: established B/C/D coverage
   and frontier coverage are seed-stable.
4. Full hand equivalence is not reached: autonomous remains one family-pool
   target behind, and total work is 2.40x the oracle arm because oracle routing
   is intentionally free in the baseline.

The appropriate next test is to rerun with F3's multi-feature COVER
reconstruction gate frozen in advance, then replace the labeled family router
with F1's genuinely inferred prior selector. Until then, call F5 an assembled
proof of coherence with strong ablation evidence, not a fully autonomous
generator-of-generators victory.

## Reproduction

From `sparse_poly_discovery/` with Zig 0.14.1:

```sh
zig build-exe genofgen_assembled.zig -O ReleaseFast
./genofgen_assembled selftest
./genofgen_assembled diag ../results/genofgen_diag_2026_07_11.csv
./genofgen_assembled run all ../results/genofgen_assembled_2026_07_11.csv --seeds=3
```

Artifacts:

- `results/genofgen_assembled_2026_07_11.csv` — target-level rows, router
  diagnostics, and per-arm summaries for all three seeds.
- `results/genofgen_diag_2026_07_11.csv` — steered and blind WALL_HARD
  diagnostic.
