# Round T / T2 — Autonomous Challenge Ecology

**Classification:** CONTROLLED FOUNDATION. This is a locally executable
challenge generator with a sealed fresh holdout and adversarial controls. It is
not evidence of general intelligence, open-ended evolution, representation
birth, or a working inventor.

## Question

Can a locally original, non-language challenge ecology derive successor worlds
from measured interaction dynamics rather than a named task family, a
hand-authored curriculum, or a fixed answer key visible to a policy?

## Design

`sparse_poly_discovery/challenge_ecology_round_t.zig` exposes a policy only to
an opaque 16-bit state and four anonymous raw pulses. The evaluator retains the
success predicate. There are no words, source corpus, LLM calls, named problem
families, feature values, or policy-visible target/answer traces.

Candidate worlds begin in **scratch**. A candidate moves to **commit** only
when measured rollout viability is neither zero nor free, state diversity is
adequate, and the transition differs sufficiently from its ancestor. The
policy lineage is snapshot-replayable. A fresh world is generated only after
that lineage closes from a separately seeded root and is recorded without ID,
state, ancestor, or evaluator predicate.

The lifecycle is deliberately grounded in the read-only Ghost Engine Sigil
contract: scratch work is discardable, only earned material commits, and a
committed snapshot replays. This experiment imports no Ghost Engine code and
does not modify that repository. Reference: `ghost_engine/docs/ideas/SIGIL_REFERENCE.md`,
sections `begin scratch`, `discard`, `commit`, and `snapshot`.

## Measured result

Canonical ledger: `results/challenge_ecology_round_t.csv`.

- 48 scratch candidates were measured.
- 22 met the fixed *measurement* admission predicate and committed.
- 26 were retired; zero-viability worlds were rejected rather than silently
  becoming a curriculum.
- The fresh holdout stayed outside the policy lineage.

This establishes only that the local transition substrate can deterministically
produce and filter bounded, nontrivial candidate worlds from prior measured
worlds. It does **not** demonstrate that an agent solves them or that a new
representation transfers to the holdout.

## Adversarial controls

`selftest` executes all of the following, failing closed on any violation:

| Control | Expected outcome |
|---|---|
| Deterministic replay | Two runs produce byte-identical ledgers. |
| Collapsed lineage | Same-transition descendants have zero novelty and none commit. |
| Replayed lineage | Reused descendants are detected/retired; no commits occur. |
| Private-material scan | Policy-visible ledger contains no hidden predicate, state, seed material, answer, or target. |
| Fresh holdout | A separately seeded world is recorded as `withheld`, not linked into policy lineage. |
| Viability/diversity gate | Empty/free and low-diversity candidates do not commit. |

## Reproduce

```bash
mkdir -p /tmp/zig-global-cache /tmp/zig-local-cache
env ZIG_GLOBAL_CACHE_DIR=/tmp/zig-global-cache ZIG_LOCAL_CACHE_DIR=/tmp/zig-local-cache \
  zig run sparse_poly_discovery/challenge_ecology_round_t.zig -- selftest
env ZIG_GLOBAL_CACHE_DIR=/tmp/zig-global-cache ZIG_LOCAL_CACHE_DIR=/tmp/zig-local-cache \
  zig run sparse_poly_discovery/challenge_ecology_round_t.zig -- run results/challenge_ecology_round_t.csv
```

## Boundary and next dependency

The world dynamics and admission thresholds are still a small human-authored
experimental substrate. The result therefore cannot claim “no fixed grammar,”
unbounded novelty, or self-generated intelligence. T1/T3 must show that a
separate raw substrate discovers a reusable mechanism and improves a fresh,
hidden world against fixed-substrate and replay-memory controls. Only then can
this ecology be used as the challenge side of a representation-birth test.
