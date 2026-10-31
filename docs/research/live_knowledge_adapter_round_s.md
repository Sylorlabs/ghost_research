# S1 — Autonomous Live Knowledge Adapter (Round S)

## Verdict

**BLOCKED — public network/DNS is unavailable in this runtime.** This is an
infrastructure result, not a negative scientific result and not a successful
real-world knowledge-adapter claim. The adapter was implemented and exercised
against two independent generic public metadata indexes. Both live acquisition
attempts returned curl exit `6`, `NETWORK_DNS_UNAVAILABLE`. It therefore
admitted **0/2** sources and deliberately did not substitute repository files,
a cached fixture, or human-selected material.

The downstream S3–S6 acceptance gates remain blocked. A later run must obtain
at least one genuine public capture before it can claim real-source principle
learning, material expansion, or messy-world transfer.

## What the adapter does

The only task input is a natural-language invention request. Generic adapter
capabilities turn that request into percent-encoded queries for public metadata
indexes (Crossref and OpenAlex); they are not a hand-picked list of sources for
this task. For each attempted candidate it records:

- request digest, public origin URL, provider, retrieval timestamp and content
  digest;
- a read-only policy, unknown-remote-license status until capture inspection,
  generic relevance/reputation/contradiction fields, and an admit/quarantine/
  retire/block decision with reason;
- provider/request/origin/content/exit-code lineage, sorted canonically so
  discovery arrival order cannot alter the ledger.

The request gate rejects evaluator, hidden-target, score, test-manifest,
credential, secret, password, private, and answer-key requests before any
acquisition. A captured forbidden surface is quarantined. The ledger itself
contains no source text, hidden answers, evaluator state, or fixture fallback.

## Measured live acquisition result

The canonical ledger is
[`results/live_knowledge_adapter_round_s.csv`](../../results/live_knowledge_adapter_round_s.csv).

| Provider | Origin class | Live result | Decision | Reason |
|---|---|---:|---|---|
| Crossref public metadata index | request-derived public HTTPS query | curl exit 6 | BLOCKED | `NETWORK_DNS_UNAVAILABLE` |
| OpenAlex public metadata index | request-derived public HTTPS query | curl exit 6 | BLOCKED | `NETWORK_DNS_UNAVAILABLE` |

The two independent failures distinguish a blocked environment from a
provider-specific no-result. The adapter will admit a real response only when
it is nonempty, at least 80 bytes, and does not contain a forbidden surface;
otherwise it records retirement or quarantine rather than claiming success.

## Reproduction

```bash
zig build-exe sparse_poly_discovery/live_knowledge_adapter_round_s.zig -O ReleaseSafe \
  --cache-dir /tmp/zig-s1-cache --global-cache-dir /tmp/zig-s1-global \
  -femit-bin=/tmp/s1_live
/tmp/s1_live results/live_knowledge_adapter_round_s.csv
/tmp/s1_live selftest
```

Expected in this environment: `ADMITTED_0_OF_2` plus two
`NETWORK_DNS_UNAVAILABLE` rows. The selftest validates request-derived generic
planning, the prohibited-request gate, no-fixture ledger declaration, and
absence of private/evaluator/answer terms. It does not pretend that a DNS
failure validates real-world acquisition.

## Limits and release condition

This is a ready acquisition **mechanism**, but it is not yet a live knowledge
world because the runtime cannot resolve public hosts. The provider set is a
small generic metadata-index capability, not an open-ended crawler; when live
access is restored it still needs robots/rate-limit enforcement, content-level
license parsing, source reputation calibration, broader discovery, and replay
from retained public snapshots. Most importantly, S1 cannot release S3–S6
until a fresh live capture, hash/provenance inspection, and no-fixture audit
actually pass.
