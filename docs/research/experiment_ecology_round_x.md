# Round X / X3 — downstream experiment ecology

**Verdict: VALID NEGATIVE.** A lineage selected without grounding, prediction,
novelty, task, curriculum, or human-usefulness scores acquired experiment bytes
with a real downstream contribution, but it did **not** beat the strong fixed
experimenter on independent post-freeze worlds. This is not evidence of adaptive
intelligence or autonomous experiment birth.

## Question

Can an experiment-maker reproduce solely because its descendants later maintain
energy, organization, low damage, persistence, and reproductive balance—without
ever receiving body-map accuracy or another semantic intermediate reward?

The local Zig harness starts 24 raw 16-byte experiment genomes, mutates them for
28 generations, freezes the winner, and evaluates it on 32 worlds drawn from a
seed domain disjoint from evolution. The frozen bytes control probe count,
schedule, address traversal, observation reduction, comparison direction,
stopping, and descendant mutation rate. The organism receives only anonymous
physiological changes. The evaluator owns the immutable ledger and lineage
selection.

## Result

| Frozen policy | Viable ticks / 3072 | Resource balance | Reproductive worlds / 32 |
|---|---:|---:|---:|
| Evolved experiment lineage | 1786 | 5538 | 9 |
| Strong fixed experimenter | **1964** | 5253 | **12** |
| Random actions | 1455 | 2157 | 1 |
| Birth-world replay | 1210 | 2173 | 4 |
| Shuffled experiment heredity | 743 | 481 | 0 |
| No experiment | 1236 | 2802 | 7 |
| Experiment bytes ablated | 1429 | 4150 | 7 |
| Favorable-birth oracle | 2214 | 6653 | 15 |

The evolved bytes are causally useful: removing them drops reproductive transfer
from 9/32 to 7/32, while shuffling their heredity drops it to 0/32. They also
beat random, replay, and no-experiment controls. But the acceptance gate requires
an exact advantage over **all** non-oracle strong controls. The fixed experimenter
reproduces in 12/32 worlds and stays viable for 178 more ticks, so X3 fails that
gate.

Resource balance alone does not reverse the verdict. Although the evolved arm
has a higher aggregate balance than fixed (5538 versus 5253), fewer descendants
remain viable and reproduce. The ecology's actual outcome is not reducible to a
single flattering scalar.

## What was and was not supplied

No LLM, text/token model, embedding, language input, named task feature, supplied
body map, grounding score, novelty reward, prediction score, curriculum, or
preloaded Rune participates.

The harness still has important human-installed reachability biases:

- eight discrete raw effector addresses;
- an interpreter that assigns bytes to schedule, traversal, reducer, comparison,
  stopping, and mutation fields;
- additive buffers and integer comparison as available experiment physics;
- fixed energy, organization, damage, metabolism, reproduction, and byte costs;
- tournament reproduction at the lineage boundary;
- fixed population, generation, and episode horizons.

Those are universe/VM choices, not learned concepts. Consequently, even a win
would have established only bounded experiment evolution inside this byte
interpreter. The loss to fixed probing shows that downstream selection did not
overcome the installed experiment geometry here.

## Controls and attacks

- **Random/fixed/replay/shuffled/no-experiment:** measured under the same 32
  post-freeze worlds and tick budget.
- **Favorable birth:** labelled an invalid oracle control; it may inspect world
  effects and therefore cannot support a discovery claim.
- **Copied transcript:** performs identically to replay and does not transfer.
- **Causal ablation:** zeroing experiment bytes reduces reproduction from 9 to 7.
- **Ledger rewriting:** 1454 attempts are denied; no organism output can mutate
  resource accounting.
- **Evaluator leak:** policy has no map, accuracy, component score, private seed,
  or evaluator-state input.
- **Duplicate evidence:** a distinct world digest is required for reproductive
  evidence.
- **Post-freeze mutation:** frozen genome digest is rechecked before transfer.
- **Bloat:** all 16 genome bytes and experiment steps are charged.
- **Shared generator:** evolution and post-freeze evaluation use disjoint seed
  domains.
- **Lineage collapse:** population and parent digests are part of the audit
  record; survival or diversity alone is never treated as intelligence.
- **Deterministic replay:** two complete runs are byte-identical.

## Earned experience and Ghost grounding

The experiment uses Ghost's Rune/Sigil ideas only as an audit discipline. A
candidate genome is disposable scratch; its exact bytes freeze before transfer;
the CSV is the replayable evidence snapshot. No Ghost code, Rune content, Sigil
parser, solution menu, shard, LLM path, or VSA path is imported. A lineage earns
standing only through independent post-freeze physiology, never because a human
names its behavior useful.

## Reproduce

```bash
rm -rf /tmp/x3-local /tmp/x3-global
ZIG_GLOBAL_CACHE_DIR=/tmp/x3-global \
ZIG_LOCAL_CACHE_DIR=/tmp/x3-local \
zig build-exe sparse_poly_discovery/experiment_ecology_round_x.zig \
  -O ReleaseSafe -femit-bin=/tmp/experiment_ecology_round_x
/tmp/experiment_ecology_round_x selftest
/tmp/experiment_ecology_round_x run results/experiment_ecology_round_x.csv
```

Expected self-test: deterministic replay passes and the canonical closure row is
`VALID_NEGATIVE:no_exact_advantage_over_all_strong_controls`.

## Consequence for Round X

X3 does not unlock X4. The useful signal is narrower: downstream physiology can
assign causal selection pressure to experiment bytes without a semantic reward,
but the resulting lineage is not yet competitive with a small fixed probing
procedure. The next architectural question is whether the experiment interpreter
itself—buffer form, comparison operation, and probe/action construction—must
become mutable rather than merely its 16 control bytes.
