# Round AL / AL1 — causal-effect fingerprint birth

**Verdict: VALID NEGATIVE.** The organism forms a compact four-bit record from
the observed effects of its four generic raw interventions. That record binds
to the correct surface-recoded held-out situation and beats fixed fingerprints,
random, replay, shuffled provenance, answer memory, and ablation. It cannot be
a foundation positive: an equal-cost fixed generic effect-vector matcher ties
it exactly. The substrate still supplies the observation vector and equality
comparison that make matching possible.

## Pre-registered setup

Each of 72 hidden cohorts has two anonymous causal response types. During
experience the organism performs four uniform raw pokes per type and stores
only `{four observed effects, earned action bit, evidence count, provenance
digest}`. A held-out query uses a private value/surface recoding and shares no
literal observed values or addresses with the experience trace. It receives no
world ID, target, label, regime key, semantic decoder, task menu, similarity
score, answer trace, or evaluation feedback. The evaluator scores only after
the cohort's contacts are exhausted.

The controls have the same 12 charged contacts per cohort: an equal-cost
generic effect-vector matcher, a fixed fingerprint, random variation, previous
cohort replay, shuffled provenance, scrubbed answer memory, and literal
relevance ablation. Label, encoding, world-overlap, and changed-causal-law
attacks are pre-registered.

## Results

| Policy | Contacts | Hidden material | Perfect cohorts |
|---|---:|---:|---:|
| earned fingerprint | 864 | **19,008** | **72/72** |
| fixed generic matcher | 864 | **19,008** | **72/72** |
| fixed fingerprint | 864 | 7,392 | 28/72 |
| random / answer / ablated | 864 | 8,448 | 32/72 |
| replay / shuffled | 864 | 10,824 / 10,032 | 41/72 / 38/72 |

The candidate is causally necessary: removing its earned fingerprint returns
to the generic baseline. It is answer-scrubbed and provenance traced, and the
surface-recoding and no-overlap attacks pass. The changed-causal-law attack
properly fails rather than silently treating a previous response as universal.

## Why the verdict remains negative

The decisive control is the exact tie with the fixed generic matcher. Although
the selected record is built from intervention consequences instead of literal
surface values, the host still specifies the four-poke vector and the equality
relation used to compare it. Thus AL1 demonstrates a useful bounded causal
fingerprint but not organism-created relevance algebra.

## Reproduce

```bash
mkdir -p /tmp/zig-al1-cache /tmp/zig-al1-global
zig build-exe sparse_poly_discovery/causal_fingerprint_round_al.zig -femit-bin=/tmp/causal-fingerprint-al1 --cache-dir /tmp/zig-al1-cache --global-cache-dir /tmp/zig-al1-global
/tmp/causal-fingerprint-al1 selftest
/tmp/causal-fingerprint-al1 run results/causal_fingerprint_round_al.csv
```

Expected: `round_al_al1 selftest PASS verdict=VALID_NEGATIVE deterministic=true fixed_matcher_tie=true attacks=true`.
