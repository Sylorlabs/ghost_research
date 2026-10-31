# P2 — causal experience-memory schema

**Verdict: CONTROLLED LIMITED POSITIVE.** A strict canonical lab notebook can
retain reusable *calibration experience* without storing individual target
answers.  Its frozen experience rule selects the successful generic primitive
on **12/12** permitted calibration choices, compared with **2/12** for the
history-free blind control.

Harness: `sparse_poly_discovery/causal_memory_round_p.zig`. Ledger:
`results/causal_memory_round_p.csv`.

## The notebook is deliberately not an answer sheet

Each record has exactly these canonical fields: chronological event sequence,
generic primitive shape, permitted observation bin, residual summary, charged
cost, causal hypothesis class, and calibration-level intervention effect. All
fields are fixed-width enums/numbers; there is no free-text field.

The schema rejects or omits target token/identity, target formula or family,
fresh score or label, winning candidate, target-to-tool mapping, test outcome,
manifest data, and arbitrary answer text. The calibration evaluator's private
success relation is not present in any record and is not passed to the chooser.
The emitted CSV is privacy-scanned for answer-bearing column names.

## Controlled benefit

The public history comprises 18 generic interventions. For each permitted
observation bin, one primitive repeatedly eliminates or reduces its residual;
the other two do not. The policy derives a strength score from only the stored
intervention effects, freezes its choice, and is then evaluated on 12 new
*calibration* choices. The evaluator records only the resulting calibration
effect, never an opaque target or fresh-test answer.

| Policy | Permitted calibration choices |
|---|---:|
| Causal experience notebook | **12/12** |
| Blind rotating primitive | 2/12 |

This is not a hidden-task or tool-forging claim. It demonstrates that a
minimal causal notebook can improve an allowed calibration decision while
remaining structurally unable to store individual answer keys.

## Integrity checks

- **Canonical schema:** no free text or optional metadata; all stored values
  fit the declared generic enums.
- **History order:** reversed arrival is normalized by chronological event
  sequence before selection; the outcome is unchanged.
- **Duplicate detection:** duplicate or non-increasing event sequences fail
  validation; bounded nonzero costs are required.
- **Privacy scan:** output fails if it contains target identity, formula,
  family, fresh-score/label, winner, test-outcome, manifest, mapping, or
  answer-text field names.
- **Deterministic replay:** normal and reverse history/calibration runs both
  reproduce 12/12 versus 2/12.

## Reproduce

```bash
rm -rf /tmp/zig-p2-cache /tmp/zig-p2-global /tmp/causal_memory_p2
zig build-exe sparse_poly_discovery/causal_memory_round_p.zig -O ReleaseFast \\
  --cache-dir /tmp/zig-p2-cache --global-cache-dir /tmp/zig-p2-global \\
  -femit-bin=/tmp/causal_memory_p2
/tmp/causal_memory_p2 run results/causal_memory_round_p.csv
/tmp/causal_memory_p2 selftest
```
