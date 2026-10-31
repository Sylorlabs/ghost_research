# Ghost Scientist Foundry-0

Foundry-0 is the novelty and falsification dossier for the proposed Ghost
Scientist v6 work. It answers the question that must precede implementation:
is there a scientifically defensible experiment here, or only another library
learning and compiler-search system?

## Decision

`FOUNDRY_0_GO_NARROWED`

A meaningful research question survives, but the broad claims do not. Ghost
Scientist must not claim primitive invention, first-of-kind library learning,
first automatic rewrite inference, first reusable equality-saturation
strategy, first LLM-free derived-tool construction, first semantics-aware
reusable instruction discovery, or first real tensor-compiler optimization.

The surviving question is:

> Can an LLM-free system autonomously induce verified typed tensor
> abstractions whose *complete* discovery and verification cost is repaid by
> behaviorally demonstrated reuse on post-freeze, independently sourced,
> heterogeneous real-compiler workloads, while beating compute-matched
> library-learning, rule-synthesis, strategy-synthesis, replay, fixed, and
> per-instance-search controls?

This question is narrower than the original Foundry proposal and materially
harder to pass.

## Files

- `FOUNDRY_0_DOSSIER.md` — novelty audit, claim matrix, surviving gap, and
  go/no-go decision.
- `FALSIFICATION_PROTOCOL.md` — predeclared v6 experiment and failure
  conditions.
- `SOURCE_LEDGER.tsv` — primary external sources and local evidence used.
- `decision.json` — machine-readable claim boundary and prerequisites.
- `verify_foundry_0.py` — stdlib-only structural audit for the dossier.
- `GOAL_CLOSURE.md` — completed-goal verdict and verification evidence.

Run:

```bash
python3 -B ghost_scientist/foundry_0/verify_foundry_0.py
```

The verifier checks documentary integrity. It does not turn a literature
review into proof of global novelty. The literature conclusion remains
bounded to the sources and search date recorded in the dossier.
