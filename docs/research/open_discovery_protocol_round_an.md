# Round AN / AN3 — open discovery protocol gate

**Verdict: GATE READY infrastructure only.** This executable protocol evaluates a proposed discovery without comparing it to an answer key, a target label, a candidate ranking, or a human-preferred invention. It is a record-admission gate, not evidence that an organism independently invents.

## Question

Can an open-ended discovery claim be admitted only when it was committed before intervention, predicts a raw observable outcome, specifies a generic intervention protocol, retains append-only evidence, replicates under held-out recoding and conditions, and confronts an attacker alternative plus a simpler alternative—while rejecting answer matching, semantic labels/decoders, training or answer traces, post-hoc rewrites, feedback during discovery, correlation-only claims, and world overlap?

## Protocol

The record carries no success-number or answer-comparison field. Admission is binary and deny-by-default. A candidate must provide all of the following before its intervention executes:

1. A falsifiable claim and predicted **raw** observable outcome.
2. A generic intervention protocol and append-only intervention/observation provenance.
3. A realized intervention contrast consistent with that prediction.
4. Replication in both a held-out recoding and a held-out condition.
5. A tested attacker alternative and a tested simpler alternative.

Any target/answer channel, label or semantic decoder, training-data/answer trace, post-hoc rewriting, evaluator feedback loop, private-world overlap, or correlation-only record rejects. The gate never asks whether a candidate matches a human invention.

## Fixtures and result

| Fixture class | Result |
|---|---:|
| Precommitted causal intervention record admitted | **1/1** |
| Required hostile/process fixtures rejected | **9/9** |
| Deterministic replay CSVs identical | **2/2** |

The admitted fixture is a claim that a generic intervention changes a delayed raw signal, with frozen prediction, provenance, both held-out replications, and both alternatives tested. Rejections cover answer-key matching, memorized training trace, post-hoc rewrite, correlation without intervention, failed held-out replication, semantic-decoder channel, feedback loop, missing attacker alternative, and missing simplicity alternative.

## Reproduction

```bash
mkdir -p /tmp/zig-an3-cache /tmp/zig-an3-global
zig build-exe sparse_poly_discovery/open_discovery_protocol_round_an.zig \
  -femit-bin=/tmp/open-discovery-an3 \
  --cache-dir /tmp/zig-an3-cache --global-cache-dir /tmp/zig-an3-global
/tmp/open-discovery-an3 selftest
/tmp/open-discovery-an3 run results/open_discovery_protocol_round_an.csv
```

Observed output:

```text
round_an_an3 selftest PASS deterministic=true causal_admits=1 required_rejects=9 verdict=GATE_READY residual=evaluation_protocol_not_autonomous_invention
```

## Limits

- This proves only that this standalone record model enforces its listed admission rules and deterministic fixtures; it does not prove a separately running organism cannot use undeclared channels.
- It does not establish that an admitted claim is useful, scientifically novel, broadly transferable, or independently generated rather than supplied by a human.
- “No answer key” means no predeclared desired invention is compared here. The held-out evaluator still checks whether a **precommitted raw prediction** occurred; that is necessary to distinguish a causal claim from a story written afterward.
- Novelty requires later independent evidence: provenance outside the candidate, comparisons to prior art or a declared corpus where applicable, and adversarial attempts to reduce or reproduce the claim.

## Artifacts

- `sparse_poly_discovery/open_discovery_protocol_round_an.zig`
- `results/open_discovery_protocol_round_an.csv`
- `docs/research/open_discovery_protocol_round_an.md`
