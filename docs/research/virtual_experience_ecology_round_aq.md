# AQ3 — long virtual-horizon experience ecology

**Verdict: FOUNDATION POSITIVE, bounded synthetic fixture only.**

AQ3 asks a narrow question: can provenance-bound causal experience accumulated
over a long virtual run improve later, held-out decisions after a hidden law
change and opaque context recoding? It is not a claim of general intelligence,
real-world knowledge, or invention. A virtual tick is a deterministic simulated
interaction, not elapsed time or extra intelligence.

## Protocol

Each arm receives exactly 1,000,000 synthetic intervention ticks followed by
100,000 held-out changed-law/recoded evaluation interactions. The earned arm
stores only a context fingerprint, its intervention, observed consequence, and
revision history; it revises a record when a later observation contradicts the
previous causal prediction. The candidate state contains no answer, target,
label, evaluator score, progress feedback, or training trace.

The hidden rule changes once halfway through the experience phase. The held-out
world shifts the rule again and recodes contexts. The candidate must therefore
use a retained causal relation rather than a raw observation cache.

Controls have equal 1,000,000 experience interactions:

- blank/fresh and answer-scrubbed memory;
- deterministic replay;
- equal-volume experience with context provenance shuffled;
- a fixed generalist rule; and
- deterministic random selection.

## Result

| Policy | Virtual experience ticks | Held-out correct / 100,000 | Material | Record revisions |
|---|---:|---:|---:|---:|
| Earned provenance-bound experience | 1,000,000 | 100,000 | 1,000,000 | 4 |
| Blank/fresh | 1,000,000 | 76,243 | 762,430 | 0 |
| Replay | 1,000,000 | 50,003 | 500,030 | 0 |
| Shuffled experience | 1,000,000 | 50,003 | 500,030 | 0 |
| Answer-scrubbed | 1,000,000 | 76,243 | 762,430 | 0 |
| Fixed generalist | 1,000,000 | 71,271 | 712,710 | 0 |
| Random | 1,000,000 | about 50,000 | about 500,000 | 0 |

The earned arm strictly exceeds every equal-budget control, while removing
experience removes the advantage. Its four revisions correspond to the four
anonymous contexts encountering the mid-run causal-law change.

## Reproduction and time

```sh
zig build-exe sparse_poly_discovery/virtual_experience_ecology_round_aq.zig \
  -O ReleaseSafe -femit-bin=/tmp/aq3
/tmp/aq3 selftest
/tmp/aq3 run results/virtual_experience_ecology_round_aq.csv
```

The self-test runs two full 1,000,000-tick-per-arm ledgers and checks them
byte-identical. On this local machine the first full ledger took roughly 44 ms;
that wall-clock number is printed by the self-test rather than stored in the
CSV, because an actual timing field would make two deterministic CSVs differ.
The runtime is far below the 120-second cap.

## Limits

This proves only that a deliberately small, deterministic causal-record method
can benefit from more simulated experience inside this synthetic world family.
Speeding up a simulator does not create understanding. The fixture, raw actions,
observations, reward, and evaluation protocol are still human-built; this result
does not demonstrate open-ended discovery, broad transfer, novelty beyond the
fixture, or a system that can acquire arbitrary real-world knowledge.
