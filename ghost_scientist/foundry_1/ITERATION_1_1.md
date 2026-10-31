# Foundry-1.1 native-deduplication iteration

Foundry-1's first post-readiness iteration attacks `P5` on the actual frozen
v5.1 tensor plans.

For all 24 selected plans, the audit alpha-renames plan nodes and compares
candidate and stock pre-lowering IR. It then selects one representative per
distinct candidate/stock signature pair, compiles both through TorchInductor,
normalizes generated source, and records sufficient byte-level duplicate
witnesses.

Sparse representatives that TorchInductor rejects for both candidate and stock
are retained as `required_unsupported_sparse`; they count as audited coverage,
not as compiler-equivalence evidence.

Generated-code equality is strong evidence that two paths reduce to the same
native code. Inequality is not proof of novelty: harmless scheduling or naming
differences can produce different source. Consequently this iteration can
advance the dedup component without declaring `P5` complete for future tools.

Run:

```bash
python3 -B ghost_scientist/foundry_1/phase4_tensor_dedup.py
python3 -B ghost_scientist/foundry_1/recompute_iteration_1_1.py
```
