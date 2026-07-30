# AT1 — Frozen Knownness / Research Broker

## Verdict

**GATE READY — deterministic offline evidence and scope triage; not web search, truth verification, semantic understanding, or invention.**

AT1 prevents an inventor from spending a large invention budget on a claim that
is already directly demonstrated in its approved evidence corpus.  It takes a
precommitted claim ID and returns one of five explicit statuses:

| Status | Meaning | Required next action |
|---|---|---|
| `known_directly_applicable` | Frozen evidence exactly matches the declared scope and includes a retained reproduction record. | Reuse only after a separate worker reproduces it. |
| `known_but_mismatched` | Related evidence exists, but its scope does not match. | Test the mismatch; do not import the claim. |
| `claimed_unverified` | An exact-scope claim exists without retained method/replication evidence. | Treat it as a hypothesis and reproduce independently. |
| `not_found` | No matching frozen evidence exists. | Explore, while recording that this is corpus-relative. |
| `inconclusive` | The request is intentionally too broad to classify. | Narrow the claim before allocating work. |

## What is actually implemented

[`knownness_broker_round_at.zig`](../../sparse_poly_discovery/knownness_broker_round_at.zig)
contains three fixed local citation fixtures, five precommitted claim queries,
and no networking code.  Every candidate-visible row contains only citation
provenance, scope metadata, a hash of limited evidence text, and the policy
`EVIDENCE_NOT_TRUTH_REPRODUCE_WITH_SEPARATE_WORKER`.  It exposes no evaluator
verdict, score, task answer, hidden path, or citation body.

The companion ledger is
[`results/knownness_broker_round_at.csv`](../../results/knownness_broker_round_at.csv).
It is a deterministic snapshot, not a record of live web results.

The interface is deliberately closed: only precommitted IDs (`Q-STATIC-ZIG`,
`Q-DYNAMIC-ZIG`, `Q-TRACE-COMPACTION`, `Q-NOT-IN-CORPUS`, and `Q-AMBIGUOUS`)
are accepted.  Arbitrary prompt text such as `answer`, `score`, `hidden-verdict`,
file reads, or a web-search request is rejected because it is not a query ID.

## Reproduction

```bash
zig build-exe sparse_poly_discovery/knownness_broker_round_at.zig -O ReleaseSafe \
  --cache-dir /tmp/zig-at-cache --global-cache-dir /tmp/zig-at-global \
  -femit-bin=/tmp/knownness_at

/tmp/knownness_at selftest
/tmp/knownness_at results/knownness_broker_round_at.csv
/tmp/knownness_at replay results/knownness_broker_round_at.csv /tmp/knownness_at.replay.csv
cmp results/knownness_broker_round_at.csv /tmp/knownness_at.replay.csv
/tmp/knownness_at query Q-DYNAMIC-ZIG
```

Expected self-test receipt:

```text
round_at_at1 selftest PASS classes=5 hostile_queries_denied=5 replay=byte_identical network=disabled verdict=GATE_READY
```

## Attack checks and boundaries

The self-test checks all five classifications, denies five hostile/non-interface
request shapes, verifies two cached replays are byte-identical, and rejects an
output containing an answer-key or evaluator-verdict field.  The implementation
contains no HTTP client, credentials, POST/mutation path, embeddings, LLM, or
hidden answer labels.

This is not a real web-search system.  It cannot establish that a claim is true,
complete, novel, or applicable outside the declared scope.  A web claim remains
evidence, not truth: only a separately isolated worker can reproduce it, and a
hidden evaluator must judge any final invention claim.
