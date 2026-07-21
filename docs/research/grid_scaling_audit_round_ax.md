# AX3 — Parallel grid scaling / variety audit

**Status:** DIVERSITY AUDIT READY — not a correctness or invention result.

AX3 measures whether a larger population is doing genuinely varied work, rather
than creating renamed copies of the same tool.  It deliberately has no sealed
task answers, evaluator score, outcome field, LLM, network access, Python, or
claim of improved correctness.

Three equal-cost configurations are compared.  Each has nine workers, six
steps per worker, and the identical slot/step CPU-memory schedule (54 receipts
total):

| configuration | worker flavours | purpose |
|---|---:|---|
| 1x1 homogeneous | one repeated flavour | duplicate baseline; display names differ but canonical tool hashes do not |
| 2x2 corners | four distinct corner flavours | coarse diverse population |
| 3x3 lattice | corners plus explicit interior mixtures | finer population variety |

For every receipt AX3 records the canonical tool-source hash, frontier branch,
task-kind grammar touched, repair transition, and resource hash.  Aggregates
are derived from those receipt rows: unique canonical tools, unique branches,
grammar coverage, duplicate receipts, repairs, and equal-resource evidence.
Aliases are ignored for deduplication, so `worker_7_renamed_tool_0` cannot
inflate diversity.

Fresh self-test emits two ledgers and requires byte-identical replay.  It also
injects unequal-compute and unequal-resource cases and requires rejection.

Run:

```sh
zig run sparse_poly_discovery/grid_scaling_audit_round_ax.zig -- selftest
zig run sparse_poly_discovery/grid_scaling_audit_round_ax.zig -- run results/grid_scaling_audit_round_ax.csv
```

**Interpretation limit:** more hashes, branches, or grammar coverage means only
that the population attempted more distinct measurable work under equal cost.
It does not establish that diversity improves correctness.  AX1's sealed
evaluator must score a real integrated population before that question is even
asked.
