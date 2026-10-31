# Round BA — machine-inferred algebra tools and prospective proof

**Status:** prospective bounded positive; the declared local gates pass.

## Direct verdict

Ghost Scientist now crosses the specific boundary that stopped AX and AZ:
the candidate's useful rewrite grammar is machine-generated rather than a
menu of agent-authored crossover forms. The evaluator enumerated 29,413 terms,
grouped them into 3,201 exact integer-polynomial semantic classes, inferred
4,403 sound candidate rewrite laws from collisions, and used only development
outcomes to select a reusable 128-rule grammar.

After the candidate, grammar, verifier, controls, containment policy, and
protocol were hash-frozen, a fresh 60-artifact seed was drawn. The contained
candidate reached the independently proven global minimum on **60/60**:

| Arm | Aggregate binary operators |
|---|---:|
| Machine-selected grammar + candidate e-graph | **106** |
| Exhaustive semantic-class search | **106** |
| Strong fixed ring e-graph, 2× e-node allowance | 137 |
| Outcome-blind machine grammar | 140 |
| Random exact 128-rule grammar | 155 |
| Fixed simplification | 452 |
| Exact-input replay | 617 |

Against the strong fixed e-graph, the result is **12 wins / 48 ties / 0
losses**. Those 12 are newly reachable global optima under the declared
budgets. Byte-identical replay passes 60/60. At 42 declared reuses per
artifact, the exact operator-count proxy is 4,452 operations versus 5,754 for
the fixed control.

This is not a claim that the rules, algorithm, or mathematics are new to
humanity. It is a prospective demonstration that this machine constructed and
selected a locally new reusable tool grammar, then used it to reach outcomes
that a compute-favored fixed portfolio did not reach.

## The original boundary questions

| Boundary | Answer after Round BA |
|---|---|
| The machine does not choose or construct the tool grammar | **Crossed within the declared term language.** Individual rewrite laws were not supplied. Exact semantic collisions generated 4,403 candidates and development outcomes selected 128. The operator set, leaves, cost model, and proof semantics are still supplied. |
| AX contains three supplied tool forms, not 27 inventions | **Historical criticism remains correct for AX; BA no longer relies on AX's three forms.** BA freezes 128 inferred laws, only 2 of which are exact-text matches to the 12 supplied forward ring forms. This is not 128 human-novel inventions. |
| No integrated candidate beats a strong fixed portfolio on held-out artifacts | **Crossed for the frozen polynomial battery.** Candidate 106 versus fixed e-graph 137, with the control receiving 10,000 e-nodes per artifact versus 5,000 for the candidate plus its prepass. The 60 inputs were generated after freeze and never mounted into the candidate as a corpus. |
| Synthetic causal learning is not connected to real tool construction | **Connected, but still narrow.** Outcomes from 120 development artifacts causally select a concrete executable rewrite grammar. No-probe reaches 140 and random reaches 155, versus 106 with outcome selection. The domain is exact algebra; the artifacts are evaluator-generated, not external production graphs. |
| Tool reuse has not shown cheaper or newly reachable discoveries | **Crossed under an exact cost model.** One grammar is reused across all 60 artifacts; it reaches 12 optima the fixed e-graph misses. Reusing emitted forms 42 times costs 4,452 declared binary operations versus 5,754. This is an operation-count result, not a wall-clock or hardware-speed claim. |
| Evaluator components exist separately but are not one production research protocol | **Crossed locally.** Freeze verification, post-freeze generation, leakage checks, AP containment, fixed/random/replay/brute/no-memory/no-probe controls, independent proof, mutation rejection, replay, reuse accounting, novelty scope, and aggregation execute in one fail-closed runner. |

## What the machine actually constructs

The supplied metalanguage is deliberately small:

- object variables `x`, `y`, and `z`;
- constants `0`, `1`, and `2`;
- binary `add`, `mul`, and `sub`;
- binary-operator count as extraction cost.

The constructor enumerates metavariable terms over `?a`, `?b`, and `?c`.
Every term is normalized to an exact sparse integer polynomial. Terms with
identical normal forms form semantic classes. A higher-cost member and the
class's lower-cost representative yield a candidate rewrite only when:

1. exact normalization proves equality;
2. the right side introduces no metavariable;
3. the left side is not a leaf; and
4. binary-operator cost strictly falls.

No list of distributive, factoring, cancellation, or constant identities is
used to infer this grammar. Development outcomes rank the inferred rules by
independent support and cost reduction. The selected grammar saved 1,030
operators over the 120-row development set.

This is a Ruler-family strategy, not a new algorithm. Ruler explicitly
developed rewrite-rule inference by combining enumeration, equality
saturation, and semantic validation; BA is a small exact implementation and
application of that prior art. See the [Ruler repository](https://github.com/uwplse/ruler)
and [Ruler paper](https://arxiv.org/abs/2108.10436).

## Genuine equality saturation

The strong control is not a label placed on a bounded rewrite loop. Its
evaluator-owned implementation has:

- hash-consed e-nodes and e-classes;
- union/find;
- congruence rebuilding;
- e-matching;
- bidirectional ring equalities;
- iterative saturation; and
- minimum-cost extraction.

This is the conventional mechanism described by
[egg](https://arxiv.org/abs/2004.03082). The candidate contains a separate,
frozen implementation and applies the learned cost-reducing prepass before its
5,000-e-node saturation. The external control begins from the raw input and
receives 10,000 e-nodes. It exhausted that allowance on every prospective
artifact: 600,000 aggregate e-nodes, versus 506 candidate e-nodes after the
prepass.

This is an independently executable in-repository baseline, not a third-party
`egg` binary. The host had no cached `egg`/`egglog` dependency, so BA does not
claim a cross-library replication.

The AI-compiler connection is concrete but not yet benchmarked: systems such
as [TENSAT](https://arxiv.org/abs/2101.01332) apply equality saturation to
tensor computation graphs. BA establishes the rule-inference and proof loop
needed for that direction; it does not claim a Transformer, ONNX, MLIR, or GPU
speedup.

## Global-optimality proof

The verifier imports none of the candidate, constructor, target generator, or
e-graph code. It:

1. strictly parses the input and emitted expression;
2. independently normalizes both to sparse integer polynomials;
3. rejects any semantic change or false work/cost metadata; and
4. exhaustively builds semantic layers of cost 0, 1, 2, ... in the declared
   grammar.

If a target meaning first appears in layer \(k\), no expression with fewer
than \(k\) binary operators can denote it. Every prospective output equals
that first layer. Four mutations—changed operator, changed input digest, false
cost, and an extra output line—are rejected 4/4.

The proof is global only inside the declared finite grammar and cost metric.
It says nothing about division, exponentiation, floating-point reassociation,
tensor layouts, memory traffic, or latency.

## Prospective chronology

1. Development generator seed:
   `0x00000000000000decafbad1234567890`.
2. Development validation seed:
   `0x00000000000000000123456789abcdef`.
3. Candidate, grammars, evaluator, verifier, AP policies, runner, and
   development artifacts frozen at `2026-07-29T15:43:04-07:00`.
4. Integrated 20-artifact dry run passed after freeze.
5. Fresh prospective seed
   `0x7f3c6fd5bbedcaecd30c35273f2e4aa1` drawn at
   `2026-07-29T15:45:00-07:00`.
6. Frozen runner executed the 60-artifact battery unchanged.

The target SHA-256 is
`a148630ca8e6e1fd36e2d0c0308a9eaf222fb1a42385d6ca4fd95c675872fd95`.
Exact input text and input digests were absent from the only candidate-visible
source, grammar, and development corpus. The target file, family audit, seed,
controls, verifier, and evaluator were never mounted into the candidate.

## AP containment closure

The prior AZ result named two containment gaps: no network namespace and a
default-allow residual. BA closes both on this host:

- outer `unshare --user --map-root-user --net` produces a network namespace
  inode distinct from the host;
- Bubblewrap adds user, PID, IPC, UTS, and mount isolation, read-only runtime
  mounts, empty work/tmp mounts, cleared environment, no capabilities, and
  resource/time limits;
- a launcher-owned default-`EPERM` cBPF filter permits 53 bootstrap syscalls
  and denies process creation, network, namespace/mount mutation, signal send,
  and direct time/sleep;
- the candidate installs a smaller 25-syscall default-`EPERM` allow-list after
  loading its grammar and before constructing a tool; and
- the outer hostile probe observes 5/5 `EPERM`; the final probe observes 6/6,
  including `openat`.

This is measured local containment, not an absolute security proof. The Linux
kernel, Bubblewrap, libseccomp, dynamic loader, Python runtime before the final
filter, and mounted read-only system libraries remain in the trusted computing
base. Physical/vDSO timing residuals are not claimed eliminated.

## Negative results preserved

The successful schedule was not assumed:

- a first hand-corpus grammar performed poorly as a greedy optimizer;
- adding learned equalities directly to saturation enlarged the search and
  lost the compute-favored comparison;
- equal e-node allowances made the early learned e-graph look better, but the
  advantage disappeared when the fixed control received 2× capacity; and
- the promoted composition became: learned cost-reducing prepass, then the
  unchanged fixed equality-saturation schedule.

The prior AZ V1 prospective tie and these BA development failures remain part
of the research record. Only the post-freeze 60-artifact trial supports the BA
prospective claim.

## Novelty audit

The audit deliberately has two verdicts:

- **Local artifact novelty: yes.** The selected 128-rule file is generated,
  hash-frozen, and contains 126 forms not exact-text-identical to the 12
  supplied forward ring laws. It enables 12 new budget-reachable held-out
  optima.
- **Algorithm/human-mathematics novelty: no claim.** Semantic-class rule
  inference is prior art, and many inferred laws are presentations of familiar
  algebra. No literature search can establish that 126 syntactic forms are
  new mathematics.

This avoids turning syntactic difference into an invention claim.

## What remains outside the boundary

BA is not a general Ghost Scientist. It does not yet show:

- autonomous invention of operators, types, semantics, or the cost model;
- advantage on independently sourced production artifacts;
- tensor-shape, noncommutative, floating-point, numerical-stability, layout,
  memory, or hardware reasoning;
- a third-party `egg`/`egglog`/TENSAT replication;
- wall-clock compiler or model speedup;
- new-to-humanity mathematics; or
- absolute hostile containment.

The next scientifically useful goal is a typed tensor-expression edition:
freeze shape/dtype/error semantics, extract graphs from real Transformer or
ONNX/MLIR artifacts before tool selection, infer typed conditional rewrites,
compare against an actual external equality-saturation/compiler baseline, and
measure both proof obligations and end-to-end kernel cost. That is the route
from this exact algebra result to advancing AI systems without defaulting to
"make another LLM."

## Reproduction and evidence

Run:

```bash
./ghost_scientist/protocol/verify_ghost_ruler_freeze_v3.sh
./ghost_scientist/protocol/run_ghost_ruler_prospective_v3.sh
```

Primary artifacts:

- `ghost_scientist/results/ghost_ruler_protocol_freeze_v3.txt`
- `ghost_scientist/results/ghost_ruler_heldout_generation_v3.txt`
- `ghost_scientist/results/ghost_ruler_prospective_v3.tsv`
- `ghost_scientist/results/ghost_ruler_prospective_v3.summary.txt`
- `ghost_scientist/results/ghost_ruler_prospective_v3.audit.txt`
- `ghost_scientist/results/ghost_ruler_selected_grammar_v3.txt`
- `ghost_scientist/evaluator/ghost_poly_verify_v3.py`
- `ghost_scientist/candidate/ghost_ruler_candidate_v3.py`
- `ghost_scientist/protocol/run_ghost_ruler_prospective_v3.sh`
