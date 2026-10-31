# Round AL / AL3 — matcher-free relevance audit

**Verdict: GATE READY, not an intelligence result.** This independent audit defines a fail-closed admission gate for proposed AL1/AL2 causal-relevance mechanisms. It rejects sixteen pre-registered ways a surface matcher, identity, or hidden answer channel can masquerade as causal relevance. A minimal manifest containing only intervention-response provenance is conditionally admissible; that is not evidence that such a candidate is useful or organism-owned.

## Question

Can a purported relevance mechanism be independently rejected whenever it uses raw equality/similarity (directly, through aliases, or encoded), addresses, regime IDs, labels, supplied routing/change-point/uncertainty scalars, target or answer history, earned/private world overlap, fixed fingerprints or segments, or a representation/cause-law-sensitive convention?

## Method

The audit is a standalone Zig executable, not imported by AL1 or AL2. Its fixture manifest contains one minimal qualified claim and sixteen hostile claims. The first rejection reason wins, so the gate is deny-by-default. The only permitted claim payload is append-only provenance of observed generic interventions and observed consequences. Generic byte transport is allowed; similarity or routing algebra is not.

The hostile set covers direct comparison, alias function, encoded key, address routing, ID/label access, change-point and uncertainty ports, target/answer/history leakage, world overlap, fixed fingerprints/segments, private representation recoding failure, causal-law-shift failure, and missing causal provenance.

## Result

| Outcome | Count |
|---|---:|
| Hostile fixtures rejected | **16/16** |
| Minimal response-only manifests conditionally admitted | **1/1** |
| Deterministic CSV replays | **2/2 identical** |

This gate does **not** establish that an existing AL mechanism passes. It is a source-level manifest audit and cannot prove a separately compiled candidate has no concealed behavior. A foundation-positive claim still requires independent rebuild, runtime provenance instrumentation, AL1/AL2 hidden-world controls, recoding and causal-law-shift transfer, ablation, and a strict win over the equal-cost fixed matcher.

## Residual limits

- It cannot prove hostile OS/process containment.
- It cannot inspect a candidate that does not expose an auditable manifest.
- It cannot turn a response record into an organism-owned semantics claim.
- The frozen synthetic substrate and evaluator remain trusted external layers.

## Reproduce

```bash
mkdir -p /tmp/zig-al3-cache /tmp/zig-al3-global
zig build-exe sparse_poly_discovery/matcher_free_audit_round_al.zig \
  -femit-bin=/tmp/matcher-free-al3 \
  --cache-dir /tmp/zig-al3-cache --global-cache-dir /tmp/zig-al3-global
/tmp/matcher-free-al3 selftest
/tmp/matcher-free-al3 run results/matcher_free_audit_round_al.csv
```

Expected:

```text
round_al_al3 selftest PASS deterministic=true hostile_rejects=16 qualified_manifests=1 verdict=GATE_READY residual=source_manifest_only
```

## Artifacts

- `sparse_poly_discovery/matcher_free_audit_round_al.zig`
- `results/matcher_free_audit_round_al.csv`
- `docs/research/matcher_free_audit_round_al.md`
