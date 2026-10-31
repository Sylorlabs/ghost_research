# I5 — adversarial leakage and fairness audit (Round I)

**Verdict: mixed; I3's negative survives, I2's narrow coverage claim survives, and I1 fails a material enumeration-integrity check.**

This is an independent audit harness, not a modification of the I1–I3
protocols. It reimplements the directed candidate enumeration and uses six
fresh, fixed-seed conditions: two I2 replays, an unseen four-cell partition,
and threshold, adjacency, and random-label negatives.

## Per-claim verdicts

| Claim | Audit verdict | Evidence |
|---|---|---|
| I1 has an equal, well-defined 30-candidate partition micro-search | **Refuted (integrity defect).** | I1 declares `254*2*3 = 1,524` partition candidates, but the actual grammar has `254*(2+3) = 1,270`. Its indexing duplicates the 254 mod-3/residue-2 candidates. Thus the deterministic 30-probe schedule is not a uniform/equal representation of the stated grammar. |
| I1 establishes a leakage-clean general response atlas | **Not supported.** | Its distance guard only excludes identical descriptor rows; it does not test answer-shaped candidate access. The audit finds the probe bank is malformed, and I1 uses labeled response scores on each evaluated target. This is legitimate task feedback only if labels are available at routing time, but is not a held-out-example generalization test. I1 remains at its own narrow 2/4 atlas result and should not be used as a clean fixed descriptor contract. |
| I2's symmetric full-bank test admits multi-cell structures and rejects unrelated controls | **Confirmed, narrowly.** | Independent replay admits singleton, two-cell, and a fresh unseen four-cell target, while rejecting threshold, adjacent-structure, and random controls at the frozen 0.90 threshold. |
| I2 is lightweight admission or evidence of search efficiency | **Refuted.** | Each I2 condition scans all 1,270 members on train to compute admission, then all 1,270 again on validation to select. That is a 2,540 candidate-call near-solve before the independent test, not a small high-level feature. This agrees with I2's own caveat but makes the restriction operational. |
| I3's equal-budget valid negative | **Confirmed.** | Source replay verifies every arm is charged 120 probes + 300 selection calls = 420. It makes no positive allocation claim and already reports guided = fixed (9/15), so the I1 enumeration defect cannot convert it into a positive. Its conclusion should be retained: this allocator is a valid negative. |

## Raw adversarial controls

The raw CSV prints train/validation/test scores for the independent I2 replay.
The unseen four-cell directed target is intentionally outside I2's original
one/two/three-cell set. The adjacency control is intentionally distinct from
both I2's threshold and iid-random controls.

An important boundary: the audit does **not** claim that using labeled
micro-search response is automatically leakage. It is admissible only under a
deployment contract where the target's labeled examples are genuinely
available before grammar selection. What fails is the stronger claim that
I1's response vector is a clean, uniformly sampled representation of the
partition grammar: its enumeration is objectively wrong and its distance
guard cannot diagnose answer-shaped probes.

## Consequences

1. Keep I3 marked **valid negative**. Its equal-call conclusion is unchanged.
2. Keep I2 marked **constrained full-bank coverage**, never lightweight
   admission/routing.
3. Downgrade I1 from a frozen downstream descriptor source. Any successor
   must correct the 1,270-member enumeration, explicitly separate probe-label
   availability from final evaluation labels, and test probe schedules under
   residue/mask permutation controls.
4. I6 remains blocked: no audited response allocator beats fixed allocation.

## Reproduce

```bash
cd /home/micah/Desktop/Sylorlabs/ghost_research/sparse_poly_discovery
zig build-exe search_response_audit_round_i.zig -O ReleaseFast -femit-bin=search_response_audit_round_i
./search_response_audit_round_i
cat ../results/search_response_audit_round_i.csv
```
