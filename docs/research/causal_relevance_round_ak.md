# Round AK / AK1 — causal relevance binding

**Verdict: VALID NEGATIVE.** Earned causal records can be bound to the relevant
anonymous current regime through an equality-pattern fingerprint, and that
beats shuffled, replayed, random, answer-memory, and record-ablated history.
It cannot count as a foundation positive: an equal-cost fixed generic
content-matcher ties it exactly. The purported relevance mechanism is therefore
reducible to supplied matching algebra.

## Question and pre-registration

Can an organism use only earned causal consequences to bind a record to the
right current regime, without a regime key, router, task label, target,
world-family identity, semantic decoder, experiment menu, uncertainty reward,
or evaluator feedback?

Before execution, 64 hidden cohorts are generated. Each contains two anonymous
raw regimes, each with a separately sampled action consequence. A four-contact
raw trace exposes only an equality pattern; it has no named feature or label.
The held-out query uses a private value bijection and different nonce/contacts.
The organism retains only `{ equality shape, earned action-law bit, evidence,
provenance }`. It has no response table or answer trace. Evaluation occurs only
after the finite contacts have been spent.

## Mechanism and controls

The candidate stores a relation from an observed equality shape to an earned
action-law bit. It probes the current raw trace, selects the record with an
equal shape, and applies that bit. The same code includes pre-registered,
equal-cost controls:

- previous-cohort replay and shuffled provenance;
- generic unrecorded variation;
- answer-memory with its causal shape removed;
- literal record ablation;
- a fixed, equal-cost content matcher;
- label, encoding, and non-overlapping-world attacks.

No policy sees a score during execution. All policies consume 12 raw contacts
per cohort. The shape survives a private value bijection because it is an
equality relation, rather than a literal value or world identifier.

## Results

| Policy | Contacts | Private material | Perfect hidden cohorts |
|---|---:|---:|---:|
| earned binding | 768 | **18,432** | **64/64** |
| fixed content matcher | 768 | **18,432** | **64/64** |
| replay | 768 | 10,656 | 37/64 |
| shuffled history | 768 | 8,064 | 28/64 |
| random / answer-memory / ablated | 768 | 9,216 | 0/64 |

The candidate cleanly beats all weak history and answer controls, passes the
private label/encoding/world-overlap attacks, and its 64 provenance commits are
necessary. But the fixed matcher obtains the identical result using the same
record layout and generic equality operation. This is precisely the competing
explanation AK1 was meant to expose.

## What this teaches

The experiment rules out a misleading claim: “matching an anonymous raw
fingerprint” is not itself evidence that an organism learned **relevance**.
It may simply exploit a supplied content-addressable matching primitive. A
future positive needs a record representation and contextual relation that are
constructed or selected from experience and beat a fixed matcher with the same
capacity—not merely a better use of an already-defined key/value relation.

This remains a bounded synthetic frozen-substrate experiment. It says nothing
about open-ended invention, full autonomy, or hostile containment.

## Reproduce

```bash
mkdir -p /tmp/zig-ak1-cache /tmp/zig-ak1-global
zig build-exe sparse_poly_discovery/causal_relevance_round_ak.zig \
  -femit-bin=/tmp/causal-relevance-ak1 \
  --cache-dir /tmp/zig-ak1-cache --global-cache-dir /tmp/zig-ak1-global
/tmp/causal-relevance-ak1 selftest
/tmp/causal-relevance-ak1 run results/causal_relevance_round_ak.csv
```

Expected:

```text
round_ak_ak1 selftest PASS verdict=VALID_NEGATIVE deterministic=true fixed_match_tie=true attacks=true
```

## Artifacts

- `sparse_poly_discovery/causal_relevance_round_ak.zig`
- `results/causal_relevance_round_ak.csv`
