# AO2 — live same-user escape reconnaissance

**Verdict: INCONCLUSIVE FOR CONTAINMENT; real same-user exposures found.**

This bounded, deterministic fixture mirrors AN1's important launch shape: a
parent starts a fresh candidate child with stdin ignored, stderr ignored, and
stdout piped back. It measures exposure; it does not claim a containment proof.

The child observed inherited environment and working directory, read
`/proc/self` and its parent status, read an evaluator-adjacent sentinel in the
shared working tree, and created an adjacent sentinel. It can emit arbitrary
stdout and has a local clock. Those are exposed surfaces under the AN1-style
same-user launcher. Dedicated sentinels are removed after every run.

Signals, fork/resource abuse, IPC/network, and nonce/transcript modification
are explicitly **UNTESTED**, not denied. The strict AN1 parser may reject an
arbitrary stdout payload, but that does not remove the child's general ability
to write arbitrary bytes to the pipe. This is an attack baseline for AO1/AO4,
not a security result.

## Reproduce

```bash
zig build-exe sparse_poly_discovery/live_escape_recon_round_ao.zig -O ReleaseSafe -femit-bin=/tmp/ao2-live
/tmp/ao2-live selftest
/tmp/ao2-live results/live_escape_recon_round_ao.csv
cp results/live_escape_recon_round_ao.csv /tmp/ao2-first.csv
/tmp/ao2-live results/live_escape_recon_round_ao.csv
cmp -s /tmp/ao2-first.csv results/live_escape_recon_round_ao.csv
```
