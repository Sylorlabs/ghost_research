# R1 — Hardened evaluator service boundary

**Round:** R (real-world inventor architecture)  
**Status:** DONE — local service-boundary foundation, with OS limit stated  
**Harness:** `sparse_poly_discovery/hardened_evaluator_service_round_r.zig`  
**Ledger:** `results/hardened_evaluator_service_round_r.csv`

## Question

Can the evaluator own private manifests, individual test outcomes, and a
persistent session budget while a policy client receives only permitted
calibration/probe replies and a non-joinable aggregate closure result?

## Design

The harness has an evaluator-service mode which creates a private service
directory containing a private manifest and persistent budget state.  Private
files are created `0600` where the host honours POSIX modes.  The policy-facing
API is capability based: it has no handlers for `manifest`, per-target `score`,
service `state`, filesystem `path`, `restart`, or identity/result `join`.

The policy artifact contains anonymous allowed replies, commitment events, and
only two closure aggregates.  Private test events are emitted as `withheld`;
there are no target identifiers, individual scores, secret outcomes, or join
keys in the CSV.

## Result

| Check | Result |
|---|---:|
| Sealed sessions | 6 |
| Persistent calls charged | 18 (3/session) |
| Closure export | aggregate `6/6` only |
| Manifest read request | denied |
| Per-target score request | denied |
| Service-state request | denied |
| Forged path request | denied |
| Restart/reset request | denied |
| Join request | denied |
| Reverse traversal replay | byte-identical |

The harness and ledger build/run successfully and `selftest` validates
canonical replay plus a scan for private manifest/state values in the exported
CSV.

## What this proves

This is a genuine local protocol boundary: the normal policy interface cannot
ask for private data or reset budget state, and the public result has no
per-session answer mapping.

## Important limit

This is **not** a hostile same-user security boundary.  A malicious policy
process running under the evaluator's same Unix identity could bypass the
capability API and attempt direct filesystem reads despite `0600` files.  The
production-strength deployment requirement is therefore separate OS accounts
or containers plus mandatory-access-control policy, a socket/RPC boundary, and
an evaluator-owned persistent database/secret store.  R1 supplies the
deterministic local service contract and denial/audit tests that later work can
deploy behind that stronger isolation.

## Reproduce

```bash
rm -rf /tmp/zig-r1-cache /tmp/zig-r1-global /tmp/r1
zig build-exe sparse_poly_discovery/hardened_evaluator_service_round_r.zig -O ReleaseSafe \
  --cache-dir /tmp/zig-r1-cache --global-cache-dir /tmp/zig-r1-global \
  -femit-bin=/tmp/r1
/tmp/r1 results/hardened_evaluator_service_round_r.csv
/tmp/r1 selftest
```
