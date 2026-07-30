# Ghost Scientist

This directory is the project boundary for Ghost Scientist. The active
real-graph Tensor v4 research bundle is under `tensor_v4/`. The exact
polynomial Round BA bundle remains intact as the prior baseline.

## Active Tensor v4 entry points

- Protocol and claim boundary: `tensor_v4/PROTOCOL.md`
- Candidate: `tensor_v4/ghost_tensor_candidate_v4.py`
- Constructor: `tensor_v4/ghost_tensor_constructor_v4.py`
- Evaluator: `tensor_v4/ghost_tensor_evaluator_v4.py`
- Genuine equality saturation: `tensor_v4/ghost_tensor_egraph_v4.py`
- Independent verifier: `tensor_v4/ghost_tensor_verify_v4.py`
- Trial runner: `tensor_v4/ghost_tensor_trial_v4.py`
- Freeze gate: `tensor_v4/ghost_tensor_freeze_v4.py`
- Heldout report: `tensor_v4/results/heldout/RESULTS.md`
- Goal receipt: `tensor_v4/results/heldout/goal_closure_v4.txt`

Run from the repository root:

```bash
python3 -B ghost_scientist/tensor_v4/ghost_tensor_freeze_v4.py verify
```

The prospective heldout trial is already complete. Its frozen source/evidence
record, raw ledger, summary, provenance audit, negative validation run, and
scoped report live together in `tensor_v4/results/`.

## Prior polynomial baseline

Round BA remains under `candidate/`, `evaluator/`, `protocol/`,
`containment/`, `docs/`, and the top-level `results/`. Its freeze verifier is:

```bash
./ghost_scientist/protocol/verify_ghost_ruler_freeze_v3.sh
```
