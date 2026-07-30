# Round AQ / AQ1 — approved raw-world adapter

**Verdict: GATE READY, infrastructure only.** AQ1 is a deterministic, evaluator-owned raw-world adapter fixture. It does **not** give an organism access to real-world knowledge, establish autonomous discovery, or prove process containment.

## Question

Can a minimal approved-world adapter expose only bounded opaque observations and accept only bounded raw actions while retaining evaluator ownership of raw source provenance, held-out outcomes, nonces, and the end-only receipt?

## Fixture

The evaluator owns a small delayed-relay raw fixture with four training and two held-out cases. Training and held-out worlds use disjoint IDs and different opaque byte recodings. A candidate protocol can observe raw opaque bytes and select one of two raw action bytes. It has no source-text, label, target, answer, score, progress, or held-out-outcome request.

The evaluator retains the source provenance digest (`fnv1a64:3b6e06a8b1f1d56c`), the hidden outcome law, and the final receipt. The digest is emitted only as an evaluator audit receipt; it is not supplied to the candidate protocol.

## Exercised fixtures

| Fixture | Outcome |
|---|---|
| Normal opaque observation followed by raw action | **allow** |
| Attempted source-world mutation | **deny** |
| Attempted answer, score, or progress request | **deny** |
| Attempted training/held-out overlap | **deny** |
| Provenance mismatch | **deny** |
| Fresh deterministic CSV runs | **2/2 byte-identical** |

The implementation records `1` normal allowed protocol trace and `4` tested hostile denials. It uses no network or external data.

## Reproduction

```bash
mkdir -p /tmp/zig-aq1-cache /tmp/zig-aq1-global
zig build-exe sparse_poly_discovery/approved_world_adapter_round_aq.zig \
  -femit-bin=/tmp/approved-world-aq1 \
  --cache-dir /tmp/zig-aq1-cache --global-cache-dir /tmp/zig-aq1-global
/tmp/approved-world-aq1 selftest
/tmp/approved-world-aq1 run results/approved_world_adapter_round_aq.csv
```

Expected self-test receipt:

```text
round_aq_aq1 selftest PASS deterministic=true normal_allow=1 hostile_denials=4 train_heldout_disjoint=true verdict=GATE_READY residual=infrastructure_only
```

## Limits

- This is a local deterministic fixture, not an adapter for real datasets, source trees, sensors, or external services.
- Its deny cases exercise this program's bounded protocol model. They do not replace the separate AP process/isolation boundary or prove protection from undeclared channels.
- “Held-out” here means disjoint evaluator-owned fixture cases and recodings, not broad real-world generalization.
- Nothing here shows novel invention, semantic understanding, long-horizon learning, or autonomy.

## Artifacts

- `sparse_poly_discovery/approved_world_adapter_round_aq.zig`
- `results/approved_world_adapter_round_aq.csv`
- `docs/research/approved_world_adapter_round_aq.md`
