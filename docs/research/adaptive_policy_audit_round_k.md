# K5 — adversarial audit of K2/K3/K4

**Verdict: K3 is a valid negative.** Independent ledger replay finds the same
equal-cost outcome: adaptive **10/24**, K1-informed fixed **10/24**,
target-blind directed **10/24**, IID **9/24**, all at 600 charged calls per
target. The strict `adaptive > fixed AND blind AND IID` criterion fails.

Harness: `sparse_poly_discovery/adaptive_policy_audit_round_k.zig`. Ledger:
`results/adaptive_policy_audit_round_k.csv`.

## Attacks and findings

| attack | result | consequence |
|---|---|---|
| K2 fixed-order/prefix replay | pass: all 20 target rows report 254 calls plus reverse-order, enumeration, mask, and residue gates; 4/4 heldout correct | K2's *feature-value* claim survives; still only the supplied corpus |
| label-availability attack | survives as a limitation | K2 scores candidates against labelled examples. It cannot route an unlabelled target and makes no such claim. |
| K4 deterministic/quality replay | pass: 24 opaque tokens, committed seed/hash, nondegenerate, unique, permutation checks | K3's evaluation set is a real deterministic holdout manifest |
| K4 information-boundary attack | warning, not invalidation | The published manifest and in-process suite contain audit fields. K3's `runArm` receives only labelled samples and does not read them, but this is a procedural/source-review boundary, not a sandbox. A future adaptive-positive claim needs a separate evaluator process or sealed manifest. |
| K3 cost/baseline replay | pass: 96 arm-target rows; every row is `254 + 346 = 600`, all integrity fields pass | No free exploration, unequal budget, or missing-arm explanation for the tie |
| K3 comparative recount | pass: 10 / 10 / 10 / 9 | No strict adaptive advantage exists under the preregistered acceptance rule |

## Scope

This audit does not transform the negative into a universal impossibility
claim. It validates the stated max-score allocator experiment and its
comparison at the stated menu and holdout. It also narrows the next valid
positive: it must improve allocation and run under a hardened information
boundary, rather than exploit a revealed K4 manifest.

## Reproduce

```bash
zig build-exe sparse_poly_discovery/adaptive_policy_audit_round_k.zig -O ReleaseFast \
  --cache-dir /tmp/k5-cache --global-cache-dir /tmp/k5-global \
  -femit-bin=/tmp/adaptive_policy_audit_round_k
/tmp/adaptive_policy_audit_round_k results/adaptive_policy_audit_round_k.csv
/tmp/adaptive_policy_audit_round_k selftest > /tmp/adaptive_policy_audit_round_k.selftest.csv
cmp results/adaptive_policy_audit_round_k.csv /tmp/adaptive_policy_audit_round_k.selftest.csv
```
