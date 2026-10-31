# R3 — Answer-free structured principle refinery

**Verdict: CONTROLLED LIMITED POSITIVE (adapter-compatible fixture).** R3
turns anonymous causal observations plus public *capture receipts* into typed,
falsifiable principles. On independent calibration, the structured refinery
selects the useful candidate material **12/12**, versus **4/12** for raw
retrieval and a frozen prior at equal charged cost. This is not yet a claim of
real-source learning: R2 had not supplied its autonomous external adapter when
R3 was built, so public source capture is represented by compatible hashed
fixture receipts rather than retrieved document content.

Harness: `sparse_poly_discovery/principle_refinery_round_r.zig`.
Ledger: `results/principle_refinery_round_r.csv`.

## What the system retains

Each retained principle has structured fields, not unstructured text:

| Field | Example role |
|---|---|
| Condition | Observable residual class |
| Mechanism | Structure worth retaining |
| Prediction | Expected improvement if mechanism is used |
| Failure signature | Observable mismatch it addresses |
| Candidate measurement/material | Public comparison and primitive composition |
| Provenance | Content-addressed capture receipt |
| Contradiction status and cost | Supported/rejected claim and charged work |

The ledger is deliberately scanned to reject identity, formula/family,
fresh-result, winner, manifest, source-text, answer, and request-ID fields.
It has no source-to-hidden-answer join. A deliberately conflicting receipt is
written as a distinct rejected principle rather than silently altering the
retained mechanism.

## Result

| Arm | Independent calibration | Cost |
|---|---:|---:|
| Structured causal principle | **12/12** | 1 charged choice/case |
| Raw receipt retrieval | 4/12 | 1 charged choice/case |
| Frozen prior | 4/12 | 1 charged choice/case |

This shows that a structured, provenance-carrying causal abstraction can
outperform keeping a raw receipt. It does **not** prove general principle
learning from real documents: replace the fixture receipts with R2 captures
before using this result in R5.

## Controls

- Reversed arrival preserves the same aggregate verdict.
- A conflicting mechanism is explicitly rejected.
- A duplicate/alias receipt must retain its canonical content hash.
- Every extraction and calibration choice is a separate ledger row.
- Privacy scanner rejects answer-bearing and evaluator-state vocabulary.

## Reproduce

```bash
rm -rf /tmp/zig-r3-cache /tmp/zig-r3-global /tmp/principle_refinery_r3
zig build-exe sparse_poly_discovery/principle_refinery_round_r.zig -O ReleaseFast \
  --cache-dir /tmp/zig-r3-cache --global-cache-dir /tmp/zig-r3-global \
  -femit-bin=/tmp/principle_refinery_r3
/tmp/principle_refinery_r3 run results/principle_refinery_round_r.csv
/tmp/principle_refinery_r3 selftest
```
