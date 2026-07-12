# J5 — adversarial audit of corrected trajectory evidence

**Verdict: J2 survives as a narrow, conditional representation result; J4's
terminal negative survives. Neither supports autonomous prior choice.**

Harness: `sparse_poly_discovery/trajectory_audit_round_j.zig`. Raw audit:
`results/trajectory_audit_round_j.csv`.

## Independent findings

1. **Sampler integrity passes.** This audit independently re-enumerates the
   1,270 directed semantic keys and verifies both the claimed `(809,113)` and
   alternate `(251,17)` affine permutations are bijections.
2. **J2's prefix *membership* is correct, but its 120-member response is not
   order-invariant.** On the held-out directed witness, the best score changes
   across three valid affine/identity orderings (`0.5667`, `0.5689`, and
   `0.6178`). This is not a duplicate-sampler error: the predeclared order is
   a legitimate fixed probe bank. It limits the claim to that fixed bank and
   forbids treating its permutation assertions as a performance-invariance
   proof. (The exact witness is absent from all three 120-member prefixes.)
3. **The J2 deployment condition is real.** Its trajectory needs labelled
   candidate scores before routing. It is valid only when a verifier/evaluator
   supplies such examples; it says nothing about an unlabeled target.
4. **The stated `none` route is not an unrelated/no-grammar control.** It has
   a five-member adjacency grammar. An independent XOR(count, adjacency)
   control has no exact member in the audited banks. Thus J2's four-way 4/4 is
   a separation among four supplied route families, not evidence of rejection
   of arbitrary outside grammars.
5. **J4 remains a valid negative.** Its raw ledger's 10/12 guided vs 12/12
   fixed result is consistent with its code. Every arm is charged 600 calls.
   Fixed is intentionally a strong, human-designed coverage baseline: it
   exhausts global/singleton/adjacency banks and spends 301 calls directed.
   The directed-only IID random control is weak, but it is not needed for the
   negative: guided already loses to fixed under equal cost.

## Scope

J2 may be retained only as: *a fixed-order, labelled-evaluator trajectory
signature that separates this supplied four-family corpus.* It is not a
permutation-robust route representation, a no-grammar detector, or proof that
the prefix was chosen without useful structural knowledge. J4's conclusion is
unchanged: this representation does not improve allocation over target-blind
fixed coverage, so J6 remains blocked.

## Reproduce

```bash
zig build-exe sparse_poly_discovery/trajectory_audit_round_j.zig -O ReleaseFast -femit-bin=trajectory_audit_round_j
./trajectory_audit_round_j results/trajectory_audit_round_j.csv
./trajectory_audit_round_j selftest > /tmp/trajectory_audit_round_j.selftest.csv
cmp results/trajectory_audit_round_j.csv /tmp/trajectory_audit_round_j.selftest.csv
```
