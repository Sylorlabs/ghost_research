# S3 — Genuine-capture, answer-free principle loop

**Verdict: BLOCKED — architecture integration prepared; no validated S1 live
capture was available at run time.** This is deliberately not a re-labelled
Round R fixture positive. The harness accepts only the stable S1 handoff
schema for one public, external, read-only capture, then records an
answer-free structured principle and equal-cost raw-retrieval control. It
refuses to score a positive until an independently protected calibration
evaluator supplies a result.

Harness: `sparse_poly_discovery/genuine_principle_loop_round_s.zig`.
Ledger: `results/genuine_principle_loop_round_s.csv`.

## S1 capture contract

One pipe-separated capture receipt is required:

```text
receipt_id|https_origin|captured_at_utc|sha256(content)|public_read_only|lineage|public_external|public_content
```

The receipt records source origin, capture time, content digest (recomputed
against the supplied public content), policy, and discovery lineage. It carries public content only. It cannot include answer,
target, family, winner, score, evaluator, manifest, hidden-test, formula, or
fixture vocabulary. The adapter rejects local paths, localhost, non-network
origins, bad digests, non-public policy/scope, missing provenance, and silent
multi-receipt joins.

## What is retained

From an accepted receipt, the learner retains only:

- observable condition;
- candidate mechanism derived from public structural language;
- falsifiable prediction and failure signature;
- candidate material;
- origin plus content digest provenance;
- contradiction status and charged cost.

There is no target/answer lookup, source-to-evaluator join, or raw response
memorisation. The raw-capture retrieval arm receives the same one charged
receipt but produces no structured mechanism; frozen prior is reserved for the
same private calibration. The evaluator must later compare all three at equal
cost using unseen cases.

## Result and boundary

The current ledger is **BLOCKED**, because S1 has not supplied a validated
public-external live capture. This is an architecture dependency, not a
negative finding: accepting a fixture or local Markdown would falsely claim
real-source principle learning. If a genuine receipt arrives, run the harness
with its path; it produces only `INTEGRATION_READY`, not a success claim. A
fresh, evaluator-isolated equal-cost calibration remains necessary for a
positive.

## Reproduce

```bash
rm -rf /tmp/zig-s3-cache /tmp/zig-s3-global /tmp/genuine_principle_loop_s3
zig build-exe sparse_poly_discovery/genuine_principle_loop_round_s.zig -O ReleaseFast \
  --cache-dir /tmp/zig-s3-cache --global-cache-dir /tmp/zig-s3-global \
  -femit-bin=/tmp/genuine_principle_loop_s3
/tmp/genuine_principle_loop_s3 run results/genuine_principle_loop_round_s.csv
/tmp/genuine_principle_loop_s3 selftest
```

With a future capture:

```bash
/tmp/genuine_principle_loop_s3 run /tmp/s3.csv /path/to/s1_live_capture.receipt
```
