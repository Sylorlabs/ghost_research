# AX2 — Diverse invention grids

**Status:** INTEGRATION READY, not an invention result.

AX2 spends the same fixed action budget across 27 deliberately different
candidate configurations: a `3 × 3 × 3` grid over tool grammar
(`source`, `csv`, `control_flow`), exploration allocation (`breadth`,
`balanced`, `depth_repair`), and method-memory trust (`conservative`,
`balanced`, `experimental`). The eight corners are distinct extremes; the
nineteen interior configurations are explicit, precommitted combinations.

Every worker has 48 actions (1,296 total) and records a configuration hash,
tool-grammar hash, action sequence hash, frontier outcome counters, and a
diversity hash. The runner has no task, answer, score, evaluator, network, or
LLM surface. AX1 typed witnesses must be supplied through a separate sealed
protocol before a real task can be scored.

Fresh selftest writes two ledgers and requires byte-identical replay. It rejects
duplicate workers, unequal budgets, post-hoc configuration mutation, duplicate
action plans masquerading as diversity, and any answer/score/task field in the
worker configuration.

This tests scale with variety fairly. It does **not** show that variety improves
invention, that a candidate solved a task, or that a tool is trustworthy.
