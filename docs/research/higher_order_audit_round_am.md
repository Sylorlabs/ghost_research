# Round AM / AM3 — higher-order causal-relevance audit

**Verdict: GATE READY infrastructure only; not an intelligence, foundation, or ownership positive.** This independent, deterministic, matcher-free manifest auditor is a deny-by-default admission gate for proposed AM higher-order relevance mechanisms. It rejects all 21 seeded hostile manifests and conditionally admits only two minimal response-only intervention-transition provenance manifests.

## Question

Can an independent gate reject a purported higher-order causal-relevance mechanism whenever its declared surface includes a static matcher (direct, aliased, encoded, or fixed vector), address/ID, label, target/answer/trace, score/uncertainty, supplied temporal motif/schedule/router, supplied graph/topology, representation or recoding dependency, or private/earned-world overlap?

## Source-level admission rules

`sparse_poly_discovery/higher_order_audit_round_am.zig` makes the following rules explicit and applies them in a stable first-match order:

1. Deny by default: a missing response-only intervention-transition provenance record rejects.
2. Conditionally admit only append-only provenance of observed generic interventions and observed transitions.
3. Reject direct, alias, and encoded matcher/key forms; address and ID comparisons; labels; target, answer, or trace fields; score and uncertainty fields; and fixed static matcher/vector/fingerprint fields.
4. Reject any supplied temporal motif, schedule, router, graph, or topology, as well as representation/recoding leaks and overlap with a private or earned world.

Generic transport is not itself evidence of relevance. A conditional admission merely says that this source-level manifest has none of the declared prohibited fields.

## Fixtures and result

| Outcome | Result |
|---|---:|
| Seeded hostile negative manifests rejected | **21/21** |
| Provenance-only positive manifests conditionally admitted | **2/2** |
| Deterministic CSV replay comparison | **2/2 identical** |

The negative set includes direct/alias/encoded matching, address and regime-ID routing, labels, target cache and answer-history trace leaks, score and uncertainty ports, fixed embeddings/fingerprints, supplied motifs/schedules/routers/graphs/topologies, representation decode and recode-sensitive surfaces, world overlap, and missing provenance.

## Exact reproduction and observed output

```bash
mkdir -p /tmp/zig-am3-cache /tmp/zig-am3-global
zig build-exe sparse_poly_discovery/higher_order_audit_round_am.zig \
  -femit-bin=/tmp/higher-order-am3 \
  --cache-dir /tmp/zig-am3-cache --global-cache-dir /tmp/zig-am3-global
/tmp/higher-order-am3 selftest
/tmp/higher-order-am3 run results/higher_order_audit_round_am.csv
```

Observed self-test result:

```text
round_am_am3 selftest PASS deterministic=true hostile_rejects=21 qualified_manifests=2 verdict=GATE_READY residual=source_manifest_only
```

The generated row-level results are recorded in `results/higher_order_audit_round_am.csv`.

## Limits

- This inspects only the manifest model in this standalone source; it cannot prove an unexposed binary, runtime, dependency, environment, or host has no concealed behavior.
- It does not establish that a conditionally admitted candidate is useful, generalizes under recoding or causal-law shifts, or beats an equal-cost fixed matcher.
- It does not provide hostile OS/process containment or evaluator isolation.
- It cannot turn transition provenance into semantic intelligence, organism status, or ownership.

Any AM intelligence or ownership claim needs independent runtime instrumentation, a separately rebuilt auditable candidate, hidden-world/recoding/causal-law-shift controls, ablation, and comparative evidence. This gate supplies only a reproducible manifest boundary.

## Artifacts

- `sparse_poly_discovery/higher_order_audit_round_am.zig`
- `results/higher_order_audit_round_am.csv`
- `docs/research/higher_order_audit_round_am.md`
