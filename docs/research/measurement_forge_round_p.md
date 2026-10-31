# P4 — measurement forger from generic atoms

**Verdict: CONTROLLED POSITIVE.** Starting from a supplied *raw atom grammar*
(bounded Boolean folds and a comparison/composition operation), P4 synthesizes
a nonredundant diagnostic from canonical answer-free calibration experience.
On evaluator-owned score-private validation sessions it separates the two
competing causal hypotheses **12/12**, versus **6/12** for a frozen generic
parity-fold baseline. Both arms spend one persistent charged execution per
validation session; only campaign aggregates are released.

Harness: `sparse_poly_discovery/measurement_forge_round_p.zig`. Ledger:
`results/measurement_forge_round_p.csv`.

## What was forged

The policy is not offered named probes. It enumerates four programs composed
from the supplied generic atoms: parity fold on either bounded input vector,
XNOR followed by parity fold, and population-count followed by comparison. It
uses only anonymous calibration observations and P2-compatible abstract causal
classes to score those program shapes. The selected structural program is
`fold_count_then_compare`; it is structurally distinct from the frozen
`fold_parity_left` baseline.

The atom grammar is still supplied. This is therefore not unconstrained
measurement invention: P4 proves selection/composition from raw computational
material under a strict privacy boundary, not discovery of new physics or a
new instruction substrate.

## Results

| Arm | Calibration separation | Sealed validation separation | Validation cost |
|---|---:|---:|---:|
| Forged count-then-compare program | 12/12 | **12/12** | 1/session |
| Frozen generic parity-fold baseline | 6/12 | **6/12** | 1/session |

The validation closure emits only these totals. It does not serialize a
session identity, raw bit vectors, hidden causal class, individual validation
answer, formula/family, winner, or manifest field.

## Controls

- **Equal cost:** each arm receives exactly one evaluator-owned validation
  execution for each anonymous session; calibration is inherited frozen P2
  experience, not validation feedback.
- **Order:** reversed calibration arrival is canonicalized; normal and reverse
  runs byte-compare.
- **Nonredundancy:** the selected program's structural fingerprint differs
  from the baseline; a renamed-baseline acceptance fails selftest.
- **Duplicate:** atom-program fingerprints are checked for collision.
- **Privacy and memory leakage:** emitted ledger is scanned for identity,
  hidden answer, raw-vector, formula/family, fresh-outcome, winner and
  manifest vocabulary. It contains aggregate closure results only.
- **Complete ledger:** every calibration evaluation and every execution for
  both validation arms is a distinct charged row.

## Reproduce

```bash
rm -rf /tmp/zig-p4-cache /tmp/zig-p4-global /tmp/measurement_forge_p4
zig build-exe sparse_poly_discovery/measurement_forge_round_p.zig -O ReleaseFast \
  --cache-dir /tmp/zig-p4-cache --global-cache-dir /tmp/zig-p4-global \
  -femit-bin=/tmp/measurement_forge_p4
/tmp/measurement_forge_p4 run results/measurement_forge_round_p.csv
/tmp/measurement_forge_p4 selftest
```
