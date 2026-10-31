# AR3 — multi-second open-workshop virtual lifetime

**Verdict: VALID NEGATIVE.** This is a deliberately generated dynamic-world
model, not a real-world general-intelligence test. It expands substantially past
the AQ toy fixture (4,096 procedural anonymous worlds, 12 interacting components,
delays, noise, law changes, recoding, and held-out seeds), but its substrate and
scoring remain human-built.

## Question

Can a candidate accumulate provenance-bound causal records and forge bounded
two-step instruments after failed simple distinctions, then use them more
efficiently on held-out recoded law-shifted worlds than equal-cost controls?

The candidate receives raw component observations and intervention outcomes only.
It receives no rule text, target relation, family identifier, world identifier,
answer trace, evaluator score/progress, or answer-memory field. It procedurally
creates the next experimental world seed from prior failed distinctions. The
evaluator alone owns the held-out relation and final material score.

## Work and controls

Each policy carries out `192,000 × 96 = 18,432,000` real simulated interventions,
visiting procedurally mutated worlds and propagating delayed noisy component
events. The earned arm serializes/checks an eight-point transfer curve. All arms
have identical interaction budgets and held-out evaluation:

- blank and answer-scrubbed memory;
- fixed broad coverage;
- deterministic random, replay, and provenance-shuffled records;
- forge ablation; and
- experience ablation.

A positive is allowed only if earned experience plus forged instruments strictly
beats every control, while both ablations remove the advantage. The executable
produces two byte-identical full ledgers in its self-test. Actual wall time is
printed by the test receipt; it is not placed in the CSV because timing would make
the two deterministic ledgers differ.

## Measured result

The clean self-test completed two byte-identical full nine-policy ledgers. Its
first full ledger used **10,174 ms** of actual CPU wall time on this machine,
without sleep, idle spinning, or no-op padding. Per policy that ledger performed
18,432,000 simulated interventions, 663,552,000 delayed component-event
propagations, and 4,096 held-out evaluations.

The result is a **valid negative**, not a failed run:

| Policy | Held-out material | Held-out correct / 4,096 |
|---|---:|---:|
| Earned provenance + forged composition | 20,140 | 2,014 |
| Fixed broad rule | **21,070** | **2,107** |
| Random | 20,840 | 2,084 |
| Replay | 20,830 | 2,083 |
| Shuffled provenance | 20,250 | 2,025 |
| Blank / answer-scrubbed / forge ablation / experience ablation | 20,030 | 2,003 |

The earned arm genuinely forged 4,608,000 bounded compositions and revised
2,304,440 causal records. Those mechanisms produced a small gain over blank,
but the fixed broad rule and random/replay controls did better. Therefore this
does **not** establish that the candidate can choose or generate a better open
world or instrument at this scale. The generated-world workload is real and
multi-second; the claimed learning advantage is not.

## Reproduction

```sh
zig build-exe sparse_poly_discovery/open_workshop_lifetime_round_ar.zig \
  -O ReleaseSafe -femit-bin=/tmp/ar3
/tmp/ar3 selftest
/tmp/ar3 run results/open_workshop_lifetime_round_ar.csv
```

The intended run is genuine world propagation/intervention/held-out evaluation
and checkpoint work for at least ten actual wall seconds, without sleeps or
padding. The final receipt records the measured duration. If this machine cannot
meet that condition before the safe 90-second cap, the report will state that
plainly rather than treating virtual ticks as elapsed learning time.

## Fresh coordinator reproduction (2026-07-19)

The earlier report that the clean self-test did not return was an interrupted
coordinator observation, not a reproducible program failure. A fresh standalone
build was run outside the worker process with explicit shell exit receipts:

```sh
zig build-exe sparse_poly_discovery/open_workshop_lifetime_round_ar.zig \
  -O ReleaseSafe -femit-bin=/tmp/ar3-safe-verify && echo BUILD_SAFE=$?
/tmp/ar3-safe-verify selftest; echo SELFTEST_SAFE=$?
/tmp/ar3-safe-verify run /tmp/ar3-run-fresh.csv; echo RUN=$?
/tmp/ar3-safe-verify run /tmp/ar3-run-second.csv; echo RUN_SECOND=$?
cmp -s /tmp/ar3-run-fresh.csv /tmp/ar3-run-second.csv
echo TWO_FRESH_RUNS_BYTE_IDENTICAL=$?
```

Observed receipts: `BUILD_SAFE=0`, `SELFTEST_SAFE=0`, `RUN=0`,
`RUN_SECOND=0`, and `TWO_FRESH_RUNS_BYTE_IDENTICAL=0`. The self-test printed
`PASS` after two full ledgers in 20.66 seconds; each standalone full ledger took
about 10.1 seconds and matched the recorded CSV byte-for-byte. The valid-negative
verdict is therefore retained: it is supported by two fresh deterministic
ledgers, not by an incomplete worker run.

## Limits

This cannot establish open-ended invention, real-world understanding, independent
world construction, or general intelligence. The candidate can make bounded
compositions and procedural experiment seeds only. The world generator, raw
alphabet, evaluator, and criterion remain supplied infrastructure. A later sealed
process replay is required before treating any behavioral outcome as isolated.
