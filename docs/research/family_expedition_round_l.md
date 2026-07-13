# L4 — public-API family-invention expedition

**Verdict: VALID NEGATIVE.** The repaired public interface makes the trial
defined and reproducible, but the proposed extension did not clear the strict
two-target requirement.

This revision replaces the earlier protocol block. The policy reads only the
six-column opaque labelled transcript and L3's public `diagnostics` and `query`
commands. It does not read a target formula, family label, mask, seed, audit
field, or hidden manifest.

## Frozen pipeline

1. Call `diagnostics` and mark a token blank when all current-menu maxima are
   below 0.950 accuracy (the predeclared L2 rule).
2. Freeze the published existing-menu baseline: 412 charged calls per token.
3. From the opaque labelled examples, enumerate the public count-above-cutpoint
   modulo extension language (`threshold`, 80 canonical candidates). No target
   family branch occurs in the proposer.
4. Send every canonical candidate to the public `query` endpoint. Pad its 80
   distinct charged tests with an explicitly recorded redundant sentinel to
   exactly 412 calls, so the comparison is genuinely equal-cost.
5. Require exact solves and strict score wins on two blank tokens. A single
   solve, a tie, or any non-exact result is a valid negative.

The ledger records candidate identity, public fit, evaluator response, every
charged query, the baseline, and padding. Canonical enumeration prevents a
favourable candidate prefix; opaque token strings only group results.

## Result

The diagnostics-only blank rule selected `L3-00` and `L3-01`; `L3-02` was
already represented (12/12 by the frozen menu) and was not eligible for the
new-family claim. On each blank token the policy exhaustively tested the 80
canonical public extension candidates, then made redundant predeclared queries
to exactly match the frozen 412-call existing-menu budget.

| Opaque token | Existing menu | Extension best | Equal charged calls | Outcome |
|---|---:|---:|---:|---|
| L3-00 | 11/12 | 10/12 | 412 | no strict win |
| L3-01 | 10/12 | 12/12 | 412 | strict exact win |

Thus the system made one real, equal-cost sealed discovery through the public
bench, but not two same-region discoveries. The predeclared L4 acceptance
criterion fails, so this is a **valid negative**, not a protocol failure.

The important repair is still real: no formula access was needed to define,
run, and account for the expedition. The remaining failure is scientific—the
proposed reusable extension did not transfer across both blank tokens.

## Reproduce

```bash
rm -rf /tmp/zig-l4-cache /tmp/zig-l4-global /tmp/sealed_l4 /tmp/family_l4
zig build-exe sparse_poly_discovery/sealed_evaluator_round_l.zig -O ReleaseFast \
  --cache-dir /tmp/zig-l4-cache --global-cache-dir /tmp/zig-l4-global \
  -femit-bin=/tmp/sealed_l4
zig build-exe sparse_poly_discovery/family_expedition_round_l.zig -O ReleaseFast \
  --cache-dir /tmp/zig-l4-cache --global-cache-dir /tmp/zig-l4-global \
  -femit-bin=/tmp/family_l4
/tmp/sealed_l4 evaluator /tmp/l4.public.csv
/tmp/family_l4 /tmp/l4.public.csv /tmp/sealed_l4 results/family_expedition_round_l.csv
/tmp/family_l4 /tmp/l4.public.csv /tmp/sealed_l4 /tmp/family_expedition_round_l.selftest.csv
cmp results/family_expedition_round_l.csv /tmp/family_expedition_round_l.selftest.csv
```

The L3 boundary is protocol-level, not OS isolation; this remains a required
limit on any resulting claim.
