# AW2 — Sealed multi-task real-artifact corpus

**Status:** READY FOR INTEGRATION — this is corpus/evaluator infrastructure, not an inventor result.

## What is sealed

Four existing Git-tracked local artifacts are copied into opaque `instance-00` through `instance-03` directories. The candidate sees a payload, a task contract, and a per-instance token. It does **not** receive the original repository path, expected value, evaluator source, score, progress, or answer key. The evaluator recomputes expected values from its separately mounted originals at runtime.

| Family | Artifact kind | Partition | Candidate task |
|---|---|---|---|
| Agent-loop source | Zig source | train | Count non-comment public function declarations. |
| Verified-synthesis result | 6,001-row real CSV | train | Strictly parse and count malformed-width rows. |
| Adversarial-loop source | Zig source | held out | Identify blocking sleeps inside a loop: a static performance-risk proxy. |
| Verification CLI source | Zig source | held out | Identify explicit missing-input failure branches. |

These are deliberately modest, inspectable structural/property tasks. They require reading real artifacts and can motivate a scanner/parser, but they are **not** bug discoveries, semantic understanding, web research, or proof of autonomous invention.

## Boundary and attacks

The implementation rejects traversal, absolute paths, evaluator/answer/expected/score/progress requests, and `.git` access. It checks distinct source hashes, distinct train/held-out partitions, deterministic staging, and byte-identical ledgers. The claims protocol is `CLAIM <token_hex> <unsigned_value>`; the evaluator accepts/rejects only after receiving the complete claim file and never returns the hidden expected values.

For a real run, the evaluator executable and original repository must be outside the Bubblewrap candidate mount. The candidate mount may contain only a staged corpus root, its own tool/scratch directory, and required runtime libraries. This source file must not be mounted there. A source-reading candidate cannot be honestly sealed if it can read this evaluator source or the original repository; that is an operational deployment requirement, not something a Zig function can magically guarantee.

## Reproduction

```bash
zig run sparse_poly_discovery/sealed_multitask_corpus_round_aw.zig -- selftest
zig run sparse_poly_discovery/sealed_multitask_corpus_round_aw.zig -- stage /tmp/round-aw-sealed
zig run sparse_poly_discovery/sealed_multitask_corpus_round_aw.zig -- run results/sealed_multitask_corpus_round_aw.csv
# After a complete candidate claim file exists, evaluator only:
zig run sparse_poly_discovery/sealed_multitask_corpus_round_aw.zig -- evaluate claims.txt results/sealed_multitask_receipts_round_aw.csv
```

Expected self-test: `real_tracked_artifacts=4 train=2 heldout=2 denials=6 byte_identical_ledger=true evaluator_answers_runtime_only=true`.

## Limit

This prepares the first serious multi-task trial. It has no candidate policy, no baseline comparison, and no claimed score; therefore it cannot be a positive result by itself. AU3's equal-budget harness and the future isolated inventor integration must consume the same staged corpus and sealed receipt protocol.
