# R2 — Autonomous Knowledge World (Round R)

## Verdict

**FOUNDATION IMPLEMENTED — LOCAL DYNAMIC DISCOVERY ONLY.** The source governor
takes an invention request plus general read-only safety policy, dynamically
enumerates accessible top-level public Markdown sources, and decides admission,
quarantine, or retirement without a human source list. It records a source
digest, filesystem capture time, request digest, policy/license status,
relevance, reputation, contradiction flag, decision, reason, and immutable
path+digest lineage.

This is not a claim of unrestricted live-web access. The harness truthfully
reports `live_network_adapter=NOT_AVAILABLE`; it demonstrates the autonomous
adapter/governance boundary using the repository's accessible public-document
surface. A later real-world transfer test must add a network/corpus adapter
with the same capture and quarantine contract.

## Safety contract

The governor does not accept a human-curated per-source allow-list. It discovers
top-level `.md` files at runtime and applies generic rules: read-only capture,
content identity rather than filename identity, provenance, request relevance,
and answer/private-surface screening. Paths or content mentioning evaluator,
test-manifest, hidden target, fresh score, credentials, secrets, API keys, or
passwords are quarantined. Result and research-document trees are also denied.
Duplicate content is quarantined even when renamed; short or irrelevant sources
are retired. The ledger stores no evaluator state or target-level result.

## Reproduction

```bash
rm -rf /tmp/zig-r2-cache /tmp/zig-r2-global /tmp/r2_world
zig build-exe sparse_poly_discovery/autonomous_knowledge_world_round_r.zig -O ReleaseFast \
  --cache-dir /tmp/zig-r2-cache --global-cache-dir /tmp/zig-r2-global \
  -femit-bin=/tmp/r2_world
/tmp/r2_world run results/autonomous_knowledge_world_round_r.csv
/tmp/r2_world selftest
```

The selftest replays discovery in reversed arrival order and byte-compares the
canonical ledger, verifies private/result surfaces cannot enter it, and reports
the deliberate offline live-network limitation.

## Limits

The source reputation and contradiction scores are bounded heuristic metadata,
not a general truth engine. `unknown_local_public` is an honest license state;
the governor cannot infer licensing from a file alone. This component provides
the policy-owned discovery and provenance boundary. It does not yet establish
principle learning, atom expansion, or messy-world transfer.
