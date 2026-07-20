# Round AT / AT2 — deterministic scratch-program forge

**Verdict: infrastructure gate only.** This is the smallest honest path from a
candidate-authored program proposal to a separately specified, deterministic
worker receipt. It is deliberately a tiny in-memory DSL, **not** arbitrary
program execution, a general code agent, process isolation proof, or evidence
that an inventor has solved a real artifact task.

## Contract

The candidate submits two immutable strings before execution: a program and a
test plan (`EXPECT <decimal>`). The worker accepts only these instructions:

```text
SET <integer>
ADD <integer>
ASSERT <integer>
PRINT
```

It returns source/plan/disposable-scratch/output hashes, compile status, test
status, instruction count, and an error tag. The language exposes no file,
network, process, environment, clock, import, evaluator, score, answer, or
credential operation. Traversal, URL/network, answer, score, evaluator and
other dangerous terms are rejected before parsing.

The ledger proves a repair path: `ADD five` fails compilation, then the
candidate repairs it to `ADD 5`; the worker compiles it, checks its assertion,
and verifies the precommitted expected output. It also proves a wrong expected
test fails and unsafe source is denied.

## What this does and does not prove

- It proves deterministic parsing/execution/receipts and a bounded
  failure-to-repair path for a source proposal.
- It does **not** prove that the candidate chose the source intelligently,
  that the DSL is useful for real source analysis, actual OS/process isolation,
  hostile code containment, real artifact access, or a hidden evaluator
  boundary. Those require the planned multi-binary worker/evaluator harness.
- The fixed deny-list is defense in depth, not a complete security policy.
  Safety primarily comes from the absence of expressive host primitives.

## Reproduce

```bash
mkdir -p /tmp/zig-at2-cache /tmp/zig-at2-global
zig build-exe sparse_poly_discovery/scratch_program_forge_round_at.zig \
  -femit-bin=/tmp/scratch-program-forge-at2 \
  --cache-dir /tmp/zig-at2-cache --global-cache-dir /tmp/zig-at2-global
/tmp/scratch-program-forge-at2 selftest
/tmp/scratch-program-forge-at2 run results/scratch_program_forge_round_at.csv
cmp /tmp/at2-a.csv /tmp/at2-b.csv
```

Expected receipt:

```text
round_at_at2 selftest PASS repaired_after_compile_failure=true unsafe_requests_denied=4 deterministic_replay=true executor=tiny_in_memory_dsl_only
```
