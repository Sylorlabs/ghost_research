# Round AU / AU1 — isolated evaluator protocol

**Status: COMPLETE — protocol gate passed, with explicit containment limits.**

## Purpose

This is the integration boundary for the later inventor test. It separates
four named roles: **candidate**, **worker**, **evaluator**, and **auditor**.
The candidate precommits an opaque-artifact claim and a narrow request. The
worker returns a measurement receipt. The evaluator alone reads the sealed task
answer and emits a final verdict. The auditor is represented by the hostile
protocol probes in the fresh self-test.

The test fixture is a deterministic local Markdown artifact. It exists solely
to test boundary mechanics; this is **not** an invention, semantic-code, or
real-world-discovery result.

## Boundary contract

- `sealed/` contains the fixture and answer and is evaluator-only by protocol.
- Candidate requests have an opaque id (`local_alpha`), a literal capability
  (`count_lines`), and an immutable claim. They contain no task path, answer,
  score, progress, or evaluator-state API.
- Worker receives only the request, returning a request hash, status, and
  permitted observation to a one-way receipt file.
- Evaluator reads the receipt and sealed answer. It accepts a claim only when
  the receipt hash still binds the exact precommitted request.
- The self-test copies the executable to distinct role-named executable paths
  and invokes candidate, worker, and evaluator as separate OS processes.

## Hostile probes

The self-test rejects path traversal, evaluator-state read, answer query,
score query, progress query, and multi-artifact/task-overlap requests. It then
runs a worker receipt, rewrites the candidate claim, and proves evaluator
rejection because the receipt hash no longer binds it. A clean setup/replay
must yield byte-identical final verdict bytes.

## Limits

This proves a deterministic **protocol isolation** slice with separate role
processes and data files. It does **not** prove hostile OS containment, prevent
a malicious binary from inspecting its own copied code, establish separate OS
users/mount namespaces, execute arbitrary candidate programs, or prove an
inventor learned anything. Those are explicit next-layer requirements.

## Reproduce

```bash
mkdir -p /tmp/zig-au1-cache /tmp/zig-au1-global
zig build-exe sparse_poly_discovery/isolated_evaluator_protocol_round_au.zig \
  -femit-bin=/tmp/isolated-evaluator-au1 \
  --cache-dir /tmp/zig-au1-cache --global-cache-dir /tmp/zig-au1-global
/tmp/isolated-evaluator-au1 selftest
/tmp/isolated-evaluator-au1 selftest
```

Expected only after the commands pass:

```text
round_au_au1 selftest PASS separate_role_processes=true accepted_precommitted_claim=true hostile_denials=6 posthoc_rewrite=denied deterministic_replay=true containment=formal_OS_proof_not_claimed
```

Both fresh coordinator invocations produced that exact line on 2026-07-20.
