# Round AT3 — Frontier explorer / maze experience ledger

**Status:** MECHANICS READY, not an invention result.

This is the ledger layer for an inventor that must take wrong turns, split
competing explanations after surprise, and leave an honest map for a later
attempt. It is a deterministic local Zig program. It uses only synthetic,
opaque worker receipts and has no network, LLM, task label, answer key, or
score signal.

## What it records

Each fork stores a parent link, state (`unexplored`, `tested`, `split`,
`dead_end`, `confirmed`, or `inconclusive`), a hypothesis, a precommitted
falsifier, needed tool, cost, receipt hash, and (for a retry after a dead end)
an explicit reason the retry differs. The receipt chain is append-only and
deterministic. It is a trace-integrity aid, not a cryptographic security claim.

The demo begins with two competing roots. Receipt `91ce` is a surprise and
splits fork 2 into forks 3 and 4. Fork 1 ends in a documented dead end. Fork 3
is inconclusive because the tool was inadequate. Under remaining budget 4,
forks 4 and 5 cannot be reached; the output names them instead of claiming
that reality has no unexplored roads.

## Anti-cheat controls

- No post-hoc conclusion: every fork requires a falsifier and tool before it
  can be recorded.
- No silent repeat after a dead end: a retry requires a nonempty reason.
- No candidate answer channel in the demo: planner inputs are opaque structural
  receipt strings only; no hidden outcome is represented.
- Deterministic replay writes two byte-identical ledgers.
- The output explicitly lists unreached branches and the finite budget scope.

## Run

```bash
zig run sparse_poly_discovery/frontier_explorer_round_at.zig -- selftest
zig run sparse_poly_discovery/frontier_explorer_round_at.zig -- results/frontier_explorer_round_at.csv
```

Expected self-test:

```text
round_at3 selftest PASS deterministic_replay=true opaque_receipts=true append_only_chain=true split=true unreached=4|5 verdict=MECHANICS_READY_NOT_INVENTION_PROOF
```

## Limit

This proves only ledger mechanics. The next integration must connect an
isolated inventor, worker, and evaluator to real held-out local artifacts.
Only then can the inventor's hypotheses and forged programs be tested without
an answer leak.
