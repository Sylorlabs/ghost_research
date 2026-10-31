# AS1 — Local read-only artifact adapter

**Verdict: GATE READY (infrastructure only).**

This experiment provides a narrow, deterministic adapter for inspecting real
workspace artifacts without granting arbitrary host access. The evaluator
selects two public, non-hidden workspace source fixtures before candidate
execution (`README.md` and the prior round's public master record), snapshots
their bounded structural statistics, and records SHA-256 provenance. The
candidate receives only byte count, line count, and aggregate delimiter counts;
it receives no path, source content, score, progress, target, or held-out
artifact.

The evaluator separately snapshots a held-out public source fixture
(`approved_world_adapter_round_aq.zig`). It accepts a bounded candidate
proposal that predicts whether aggregate delimiters balance, then records an
end-only receipt. This is a **prediction-before-local-test record**, not a
discovery claim: balanced delimiters is a deliberately small structural
property and the fixture family is evaluator selected.

## Evidence

`results/local_artifact_adapter_round_as.csv` records:

- two train snapshot manifests and SHA-256 digests;
- a bounded structural proposal (`predict_balanced=true`);
- an end-only held-out property receipt, with held-out content/path/digest not
  emitted into the candidate record;
- ten denial fixtures: mutation, traversal, out-of-scope path, `.git`,
  secret-like path, answer/score/progress request, snapshot mismatch, and
  train/held-out overlap.

Fresh `zig build-exe ... -O ReleaseSafe`, `selftest`, and two independently
written ledgers passed byte-identically. The selftest reports 10 hostile
denials, two train fixtures, and one held-out fixture.

## Boundary

This does **not** provide arbitrary host access, browser/network access, real
world understanding, a general artifact language, or OS containment. It is a
local, evaluator-owned protocol fixture. Its value is provenance, bounded raw
structure exposure, held-out separation, and explicit denials that can be
reused by the later disposable worker and long-run scheduler.
