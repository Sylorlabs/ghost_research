# Research Round 2026-07-20d (Round AV) — first real local-code trial

**Status:** COMPLETE — operational real-source repair, no learned advantage.

## Test

The candidate wrote and executed actual Python analyzer source against frozen,
read-only copies of two tracked Zig files. A Bubblewrap worker mounted only the
candidate script and corpus copy; the evaluator's expected count was not
mounted. The first raw-token analyzer failed on the training file because
commented function signatures inflated its count. The candidate recorded the
comment hypothesis, wrote a comment-stripping analyzer, and transferred it to
the held-out real source.

## Result

| Policy | Train | Held-out | Verdict |
|---|---:|---:|---|
| Candidate raw-token analyzer | 26 vs hidden 10 | — | fails, then repairs |
| Candidate repaired analyzer | 10 | 3 | operational success |
| Strong fixed comment scanner | — | 3 | ties candidate |
| Weak fixed raw-token scanner | — | 3 | happens to pass this held-out file |

Fresh rerun and replay produced byte-identical ledgers. Candidate source does
not contain the expected numeric answer literal; worker receipts confirm no
expected value is visible in the sandbox.

**Verdict:** this is a real local-code/tool-repair operation, not a toy numeric
fixture. It proves neither learning superiority nor general invention because
the repair family was supplied and an equal-capability fixed scanner tied it.

## Artifacts

- `sparse_poly_discovery/real_local_inventor_trial_round_av.py`
- `results/real_local_inventor_trial_round_av.csv`
- `docs/research/real_local_inventor_trial_round_av.md`

## Next hard gate

Use multiple unrelated real source/data tasks, hold out the failure mechanism,
allow a broader but audited program-forge grammar, and require the accumulated
candidate to beat fixed/broad/replay baselines under identical budgets before
calling anything learned invention.
