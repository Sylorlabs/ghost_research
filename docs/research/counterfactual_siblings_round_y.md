# Round Y / Y2 — counterfactual sibling development

**Verdict: VALID NEGATIVE.** Counterfactual sibling development is executable,
fully charged, deterministic, and causally relevant, but the organism-selected
paired policy does not beat the equal-cost controls. More importantly, the
fixture necessarily supplies a finite structural edit-address axis and a
subtraction operation over resource histories. This is a human-installed credit
shape, not autonomous developmental responsibility.

## Question and boundary

The experiment asks whether an organism can spend its own resource budget to
develop two siblings from the same birth state, vary one organism-selected
structural byte, and preserve edits whose later ordinary resource histories
differ reproducibly. It imports no language model, text/token process,
embedding, named task feature, semantic port, hidden answer, preloaded Rune, or
intermediate correctness, grounding, prediction, novelty, or usefulness reward.

The immutable evaluator exposes only energy, organization, damage, persistence,
and reproduction. Pair construction, raw edit selection, exploration length,
stride, stopping, and subsequent mutation are genome bytes. Both siblings are
charged: every policy pays **9,216 sibling ticks** before the 3,072-tick frozen
transfer evaluation.

This is a bounded local fixture. The eight raw edit addresses are anonymous to
the organism, but their existence and the operation that subtracts one sibling's
resource history from the other's are supplied by the harness. They are not an
earned representation.

## Construction

Each development begins from an evaluator-private raw world. A pair shares the
same birth perturbation, delay, raw-address permutation, and physical response
field. The changed sibling receives exactly one raw structural edit. The
organism never receives the response table, permutation, seed, physical edit
identity, or an edit-quality label.

The paired policy accumulates downstream resource-history differences across 48
independent contexts, freezes its selected raw edit, and enters 32 newly seeded
worlds. Training and transfer seeds are disjoint. The genome is mutated for 192
bounded proposals using only aggregate later resource histories. The canonical
comparison includes:

- unpaired births;
- random raw edits;
- a fixed exhaustive edit schedule;
- replay of the frozen source choice;
- shuffled pair correspondence;
- a favorable-birth oracle, explicitly invalid as a deployable policy;
- an equal-cost static edit;
- causal removal of the edit;
- copied transcript/source choice;
- evaluator rewrite attempts.

## Measured result

| Policy | Viable ticks / 3,072 | Resource balance | Reproductive worlds / 32 | Frozen raw edit |
|---|---:|---:|---:|---:|
| organism-selected paired | 1,935 | 3,629 | 16 | 6 |
| unpaired | **2,429** | **5,814** | **22** | 0 |
| random edit | **2,429** | **5,814** | **22** | 0 |
| fixed schedule | 2,283 | 4,629 | 19 | 7 |
| replay | 1,935 | 3,629 | 16 | 6 |
| shuffled pairs | 2,173 | 4,666 | 18 | 4 |
| equal-cost static | 2,100 | 4,410 | 17 | 3 |
| edit removed | 916 | 509 | 0 | — |
| raw recoding + new delays | 2,223 | 5,459 | 19 | 6 |

The causal ablation confirms that structural edits materially affect survival:
removing the edit drops reproduction from 16/32 to 0/32. That does **not** rescue
the claim. The paired policy loses to unpaired, random, and fixed scheduling on
all three principal downstream measures. Shuffling pairs also fails to remove a
unique advantage because there is no paired advantage to begin with.

Raw recoding changes which physical effect an address reaches and materially
changes the result. Thus the retained choice is an address-level artifact, not
an invariant functional responsibility representation.

## Hostile controls

The canonical ledger records these attacks:

1. pair-world private state never enters the organism; only ordinary histories
   return;
2. duplicate contexts cannot count as independent evidence because context
   digests are required;
3. all genome bytes and both sibling executions are charged;
4. the genome digest is frozen and rechecked before fresh evaluation;
5. 32 evaluator rewrite attempts are denied;
6. no language, named feature, target, answer, or text surface exists;
7. copied source choices and transcripts receive no special evidence status;
8. fresh raw re-encoding and delay changes expose address dependence.

## Interpretation

Paired siblings are a useful experimental instrument: sharing a birth state can
remove favorable-birth noise, and deleting the chosen edit demonstrates causal
effect. But this implementation does not discover the experiment axis. Humans
installed both the menu of one-byte edits and the operation for comparing their
histories. Even inside that supplied axis, self-selected pairing is inferior to
strong equal-cost controls.

The result therefore blocks Y2 promotion. It is an experimental negative, not
an agent or infrastructure failure. Round Y should not release inheritance or
accumulation on the basis of Y2.

## Reproduction

```bash
zig build-exe sparse_poly_discovery/counterfactual_siblings_round_y.zig \
  -O ReleaseSafe --cache-dir /tmp/y2-cache \
  --global-cache-dir /tmp/y2-global \
  -femit-bin=/tmp/counterfactual_siblings_round_y
/tmp/counterfactual_siblings_round_y selftest
/tmp/counterfactual_siblings_round_y run \
  results/counterfactual_siblings_round_y.csv
```

The self-test writes two independent ledgers and requires byte-identical replay,
all controls, all hostile attacks, and the exact valid-negative closure.
