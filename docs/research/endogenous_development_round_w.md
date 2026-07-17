# W2 — Endogenous development under immutable resource physics

**Verdict: VALID NEGATIVE.** A mutable-drive organism developed from anonymous
action consequences without a task, target trajectory, curriculum, novelty
bonus, prediction reward, semantic usefulness reward, answer feedback, text, or
LLM. On 24 independently seeded worlds created after freeze it survived longer
than inert, random, and copied-trajectory controls, but **lost to the equal-cost
fixed-drive probe**. The experiment therefore does not establish endogenous
intelligence, sustained autonomous development, or representation birth.

## Question and boundary

The evaluator exposes only organism-local energy, organization, damage, and
anonymous intervention consequences. It owns metabolism, finite reservoirs,
damage, reproduction thresholds, compute/time budgets, world generation, and
the result ledger. Organisms cannot rewrite those quantities. Their drive
weights and exploration duration can mutate between generations, and their
lifetime consequence estimates begin empty at each birth.

The installed raw physics is explicit: eight anonymous interventions draw from
finite reservoirs, affect energy/organization/damage, and are independently
permuted in every world. This remains a designed ecology. In particular,
viability axes and sequential probing are supplied machinery, not organism-born
concepts.

## Protocol

1. Begin with an empty action-consequence table and a small mutable drive
   `(energy=2, organization=2, damage=3, explore=3)`.
2. Across 12 source generations, mutate drive weights and exploration duration.
   A child may replace its parent only through evaluator-owned reproduction
   consequences; no quality score is returned to the organism.
3. Freeze the surviving drive and one source action trace.
4. Generate 24 new worlds from a separate seed family. Each changes effect
   values, finite reservoirs, and the anonymous action permutation.
5. Give every policy the same 128-tick budget per world (3,072 total ticks).
6. Compare mutable endogenous development with inert, random, fixed-drive,
   replay, favorable-birth oracle, evaluator-rewrite, and oscillatory controls.

## Results

| Policy | Viable ticks / 3,072 | Resource return | Useful actions | Recovered worlds |
|---|---:|---:|---:|---:|
| Mutable endogenous | **1,275** | -1,082 | 369 | 2/24 |
| Inert | 744 | -2,304 | 0 | 0/24 |
| Random | 1,022 | -1,094 | 143 | 0/24 |
| Fixed drive | **1,300** | **-774** | **526** | **7/24** |
| Replay | 1,023 | -1,371 | 104 | 0/24 |
| Favorable-birth oracle | 1,235 | 442 | 1,242 | 14/24 |
| Oscillate | 956 | -1,446 | 272 | 7/24 |

The evolved drive finished as
`energy=6;organization=2;damage=3;explore=5`. It gained 531 viable ticks over
inert, 253 over random, and 252 over replay. But fixed drive gained 25 more
viable ticks, 308 more resource units, 157 more useful actions, and recovered in
five more worlds. No evaluated policy achieved sustained reproduction across
the fresh worlds.

The favorable-birth row is deliberately invalid: it consults evaluator-owned
current effects and shows what an answer-bearing oracle would look like. It is
not evidence for the organism.

## Integrity attacks

- Invalid rewrite actions were denied 768/768 times; they produced inert-like
  viability and could not modify evaluator accounting.
- Alternating two actions received no special novelty or prediction credit and
  did not beat endogenous or fixed-drive development.
- A frozen source trajectory did not transfer.
- Duplicate evidence, post-freeze edits, and uncharged bloat are explicit
  rejection sentinels in the ledger contract.
- Fresh worlds use a distinct post-freeze seed family and independently rebuilt
  action permutations.

These are bounded harness checks, not hostile operating-system isolation. The
duplicate/bloat/freeze rows certify this experiment's ledger policy; W2 alone
does not establish the full Round W evaluator-security claim.

## Interpretation

The positive portion is narrow: consequence sampling can recover some
viability after anonymous rewiring without a human-issued job. The decisive
negative is that mutable organism-owned preferences did not beat a simple
human-fixed developmental preference. Worse, the experiment installs both the
viability coordinates and the sequential probe schedule. It demonstrates a
useful no-language ecology instrument, not self-originating intelligence.

The next dependency must not inherit W2 as a success. To advance, an organism
would need to originate or replace its probing organization and improve across
physics variants whose viability tradeoffs differ, while still beating fixed
drive at equal cost.

## Reproduction

```bash
zig build-exe sparse_poly_discovery/endogenous_development_round_w.zig \
  -O ReleaseSafe -femit-bin=/tmp/endogenous_w2 \
  --cache-dir /tmp/w2-cache --global-cache-dir /tmp/w2-global
/tmp/endogenous_w2 selftest
/tmp/endogenous_w2 run results/endogenous_development_round_w.csv
```

Canonical artifacts:

- `sparse_poly_discovery/endogenous_development_round_w.zig`
- `results/endogenous_development_round_w.csv`
- `docs/research/endogenous_development_round_w.md`
