# Round AQ / AQ2 — earned instrument forge

**Verdict: FOUNDATION POSITIVE, bounded synthetic evidence.** In a private,
per-cohort recoded world, the candidate first finds that every single raw probe
fails to distinguish the anonymous roles. It then earns a relation instrument by
composing pairs of raw actions, storing only the raw response signature,
evidence count, pair position, and provenance digest. On a later changed
evaluation presentation, it selects the earned pair whose raw signature matches
the challenge observation. It earns **4,080** evaluator-only material over 96
cohorts, strictly exceeding every equal-contact control.

This is evidence that an observed failed distinction can trigger a useful,
experience-derived composition within a small supplied action alphabet. It is
not evidence of open-ended tool invention, arbitrary material discovery,
semantic understanding, or general intelligence.

## Pre-registered setup

Each sealed cohort supplies four anonymous raw primitive actions. The candidate
does not receive a target, task label, answer trace, semantic decoder, progress
score, uncertainty, evaluator feedback, or instrument menu. It only observes
raw responses to actions it pays to execute.

The first four single-action contacts always return the same raw response. That
is a genuine failure to distinguish the hidden roles, and it is the sole
authorization for the generic forge loop. The loop constructs every ordered
two-primitive composition from the available raw actions, observes a raw
signature for each, and records only:

```text
(raw first position, raw second position, raw signature, evidence=1, provenance digest)
```

The evaluator privately permutes raw action positions per cohort. It exposes a
raw challenge signature after the forge phase, then evaluates four chosen final
trials under a distinct evaluator-only payoff law. The candidate never sees
that payoff during selection. A raw signature collision can make a first-match
selection miss; the positive therefore does not rely on a perfect matching
oracle.

Every policy is charged **21 raw contacts per cohort**: four failed raw probes,
twelve forged pair probes, one challenge observation, and four final trials.
All arms pay **2,016** contacts across 96 cohorts.

## Equal-cost results

| Policy | Contacts | Hidden changed-world material | Forged / selected records |
|---|---:|---:|---:|
| earned forge after failed distinctions | 2,016 | **4,080** | **96 / 96** |
| fixed raw primitive only | 2,016 | 0 | 0 / 0 |
| fixed human-like composition `(0,1)` | 2,016 | 1,360 | 0 / 0 |
| deterministic random composition | 2,016 | 880 | 0 / 0 |
| replay previous cohort | 2,016 | 320 | 0 / 0 |
| shuffled prior experience | 2,016 | 400 | 0 / 0 |
| answer-memory scrubbed | 2,016 | 640 | 0 / 0 |
| forge ablation | 2,016 | 640 | 0 / 0 |
| fixed broad four-composition coverage | 2,016 | 840 | 0 / 0 |

The strongest comparator is the fixed human-like pair at 1,360; the earned
forge leads by 2,720. The candidate's material comes from 51 successful
cohorts × four final trials × 20 material. It still creates and provenance
authorizes a composition record in all 96 cohorts; signatures collide in the
remaining cohorts, which is an explicit limitation of this deliberately small
raw representation.

## What the controls rule out

- **Raw-only / forge ablation:** neither the uniform single-probe record nor a
  generic fallback is enough.
- **Fixed composition and broad coverage:** a supplied-looking static pair or
  fixed coverage schedule is much weaker after private action recoding.
- **Random, replay, and shuffled experience:** an arbitrary pair or other
  cohort's otherwise equal-sized history does not transfer.
- **Answer scrub:** the scrubbed policy has no retained composition trace and
  falls to 640.
- **No online reward:** material is evaluator-only and revealed after the four
  final trials, so it cannot guide the forge within a cohort.

## Boundary and limitations

- The primitive alphabet is supplied by the environment. Enumerating ordered
  pairs over four primitives is a small fixed *grammar*, even though no list of
  favored pair instruments is supplied. This is not self-invented operations,
  unbounded instrument growth, or a claim that the machine can discover all
  useful materials.
- The hidden role law, raw response channel, and evaluator are synthetic and
  human-authored. The result is a fixture-level causal-learning test, not a
  real-world discovery.
- The source fixture is deterministic and local. It does not itself prove
  process isolation or hostile containment; Round AP's separate boundary work
  is a distinct claim.

## Reproduce

```bash
mkdir -p /tmp/zig-aq2-cache /tmp/zig-aq2-global
zig build-exe sparse_poly_discovery/earned_instrument_forge_round_aq.zig \
  -femit-bin=/tmp/earned-instrument-aq2 \
  --cache-dir /tmp/zig-aq2-cache --global-cache-dir /tmp/zig-aq2-global
/tmp/earned-instrument-aq2 selftest
/tmp/earned-instrument-aq2 run results/earned_instrument_forge_round_aq.csv
```

Expected receipt:

```text
round_aq_aq2 selftest PASS verdict=FOUNDATION_POSITIVE deterministic=true contacts_per_cohort=21 all_controls_strictly_beaten=true primitive_failures_authorize_forge=true
```

The full deterministic ledger is
[`results/earned_instrument_forge_round_aq.csv`](../../results/earned_instrument_forge_round_aq.csv).
