# AX4 — real staged-artifact typed-witness integration

**Status:** COMPLETE — valid protocol/coverage result; **not** an invention or
autonomy result.

## Question

Can the 3×3×3 AX population run on AW's four staged, real tracked artifacts
and receive credit only for task-typed evidence—not for an accidentally equal
number?

## Setup

The coordinator stages AW2's four copied payloads (two train, two held-out),
then starts 27 equal identities. Each identity is assigned one native tool
grammar—source structure, strict CSV width, or control-flow—and emits a
`WITNESS_V1` envelope only for tasks that grammar can actually address. The
separate reduction mode independently rebuilds the canonical witness from each
payload. It rejects `NO_WITNESS`, scalars, malformed envelopes, wrong token,
kind, hash, count, or location witness.

The coordinator command is:

```bash
scripts/run_round_ax_integration.sh
```

## Result

The evaluator accepted **36/108** worker-task attempts: **9/27** on each of the
four tasks. That is exactly the compatible grammar cohort for each task: nine
source workers cover declarations and MissingArg; nine CSV workers cover CSV;
and nine control-flow workers cover sleep-in-loop. The other 72 attempts were
not scored as failures-to-invent or guessed answers—they submitted no typed
witness because their grammar did not fit the task.

Replay was byte-identical. After changing the staged declaration payload while
keeping all original claims, the accepted total fell from **36/108 to 27/108**:
all 27 claims for that task rejected. So the score is bound to the exact
payload/witness, not a reusable scalar.

## What this proves

- The AW scalar-coincidence failure is closed for these four structural task
  families: a source scanner cannot receive CSV or sleep credit merely because
  it prints the same integer.
- The population has task coverage: each task has a concrete typed tool path
  and all accepted outcomes contain independently reconstructed evidence.

## What it does not prove

This does **not** show that 27 agents invented 27 tools, discovered an unknown
bug, beat a strong fixed portfolio, or selected the right grammar on their own.
The current tool grammars and their task compatibility are still supplied by
the harness; worker labels make 27 hashes, but there are only three underlying
tool forms. Candidate and evaluator are separate processes but are not
OS-isolated in this local coordinator run. This is a trustworthy replacement
for AW's invalid scalar measurement, not the desired general-inventor result.

## Artifacts

- `sparse_poly_discovery/ax_real_integration_round_ax.zig` — candidate emit and
  independently recomputing evaluator modes
- `scripts/run_round_ax_integration.sh` — coordinator
- `results/ax_real_integration_round_ax.csv` — 108 per-attempt receipts
