# AW1 — Method-memory compiler and answer firewall

## Verdict

**INFRASTRUCTURE READY.** AW1 compiles a small deterministic field manual from
the prior research record without importing old tasks or their answers. It is
not an inventor, a learner, a task corpus, a web-search system, or evidence of
an intelligence result.

## What it remembers

The candidate-visible ledger contains only general, provenance-classed methods:

- reachability precedes aim;
- failure should create a repair/discrimination branch;
- equal budgets and receipt-derived scoring are mandatory;
- answer channels, shared evaluator state, and post-hoc claims must be attacked;
- tools must transfer before becoming reusable experience;
- knownness records are evidence to reproduce, not answer keys;
- fixed/broad/replay controls remain serious competitors; and
- later retractions block an earlier strategy rather than becoming a success
  rule.

These lessons are grounded in the project’s representation/aim synthesis,
prior-selection negative, allocation and equal-budget audits, knownness and
tool-forge protocols, local-artifact trial, and the later reduction audit that
retracted invalid discovery claims. The compiler intentionally stores evidence
families, not experiment/task identifiers, artifact names, hashes, scores, or
solution machinery.

## Firewall contract

[`method_memory_firewall_round_aw.zig`](../../sparse_poly_discovery/method_memory_firewall_round_aw.zig)
emits [`method_memory_firewall_round_aw.csv`](../../results/method_memory_firewall_round_aw.csv).
It excludes:

- task IDs and historical expected outputs;
- artifact paths or hashes for future evaluation data;
- solution source/code and answer-shaped scores;
- unreviewed candidate-provided history; and
- retracted positives as actionable strategy rules.

The only retraction output is a generic warning: invalidate the strategy and
rerun an audit. A deliberately false historical lesson is classified
`untrusted_test_first`, never trusted.

## Attacks and replay

The self-test rejects injected answer, task, path, hash, solution-code, score,
and held-out shaped material. It proves that scrambled historical identifiers
are inert because no identifiers feed the principles; confirms a false lesson
is test-first; confirms retracted material cannot be emitted as an accepted
method; and compares two cached replays byte-for-byte. There is no LLM,
networking, filesystem corpus scan, or hidden evaluator input.

## Reproduce

```bash
zig build-exe sparse_poly_discovery/method_memory_firewall_round_aw.zig -O ReleaseSafe \
  --cache-dir /tmp/zig-aw1-cache --global-cache-dir /tmp/zig-aw1-global \
  -femit-bin=/tmp/method-memory-aw1

/tmp/method-memory-aw1 selftest
/tmp/method-memory-aw1 results/method_memory_firewall_round_aw.csv
/tmp/method-memory-aw1 replay results/method_memory_firewall_round_aw.csv /tmp/method-memory-aw1.replay.csv
cmp results/method_memory_firewall_round_aw.csv /tmp/method-memory-aw1.replay.csv
```

Expected receipt:

```text
round_aw_aw1 selftest PASS lessons=9 injections_denied=7 scrambled_ids_inert=true false_lesson=test_first retractions=blocked replay=byte_identical network=disabled verdict=INFRASTRUCTURE_READY
```

## Boundary

This is **infrastructure only**. It makes the accumulated negatives and
audited positives available as safe experimental discipline; it does not pick
hypotheses, write programs, inspect artifacts, allocate a search budget, or
beat a baseline. Those are separate candidate capabilities that must be tested
on sealed real tasks.
