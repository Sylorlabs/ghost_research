# L2 — trace-only blank-region detector

**Verdict: LIMITED POSITIVE.** A frozen detector, given only the completed
search trace from the current grammar, cleanly distinguishes represented cells
from deliberately unmapped cells on the sealed heldout split. This is a
cartography primitive: it can say “the present map has no route here.” It does
**not** identify the missing family, invent an operator, use an unlabelled
real-world target, or demonstrate an allocation advantage.

Harness: `sparse_poly_discovery/blank_region_round_l.zig`.
Ledger: `results/blank_region_round_l.csv`.

## Question and preregistration

Can a policy-safe search trace detect that a target lies outside the current
representation, without reading target identity, formula parameters, family
labels, audit metadata, or candidate position?

The current grammar is fixed before evaluation:

- 25 global threshold/modulo candidates;
- 40 singleton-rank/modulo candidates;
- 1,270 directed-partition/modulo candidates; and
- 20 adjacency/modulo candidates.

For every target, the detector input is exactly four observable maxima:
`trace_global_max`, `trace_singleton_max`, `trace_directed_max`, and
`trace_adjacency_max`. `Trace` has no target id, kind, formula parameter,
split, or audit label. The frozen rule is:

```text
predicted_unmapped = max(current-grammar trace) < 0.95
```

The 0.95 cutoff was chosen before the ledger is generated: represented cells
have an exact member in the existing finite grammar, while an unmapped cell
must be materially short of exactness. No target-specific cutoff fitting or
route label reaches `detect`.

## Construction and boundary

Twenty-four deterministic cells are generated: 16 represented cells from the
four current grammar families, and eight audit-only blank cells (`xor_blank`
and `parity_blank`) that have no exact member in that grammar. The first 12
are development cells and the latter 12 are heldout. The detector does not
branch on the split; the split and formula-kind appear only in the output
ledger's audit fields after prediction.

This is deliberately a synthetic, controlled map edge. It proves that absence
of an exact trace can be detected in this grammar universe. It does not prove
that low accuracy always means a new scientific territory: finite samples,
label noise, a bad verifier, or an insufficient budget could create the same
signature in a less controlled setting.

## Heldout result

On the 12 sealed heldout cells:

| Outcome | Count |
|---|---:|
| True unmapped detected | 4 |
| Represented correctly retained | 8 |
| False positives | 0 |
| False negatives | 0 |
| Precision / recall | 1.000 / 1.000 |

The ledger's final `HELDOUT_SUMMARY` row records these counts. The positive is
limited because the audit-only construction defines the blank classes; the
detector merely sees their search-response consequence.

## Controls

- **Candidate-order control:** canonical, reverse, and affine-bijective
  enumerations of all 1,355 candidates give exactly the same maximum trace and
  prediction.
- **Mask and residue controls:** directed masks and legal residue flavours are
  fully enumerated rather than selected by a useful prefix; their order cannot
  create the result.
- **Cell-name permutation control:** target inputs use identity or reversal.
  Reversal is a nontrivial automorphism of the current line-adjacency grammar;
  singleton and directed banks are closed under it. This checks that a fixed
  physical cell naming convention is not doing the classification.
- **Duplicate control:** every target token has an independent deterministic
  seed and formula-parameter combination; no row is duplicated. The detector
  does not receive the token.
- **Policy boundary:** this harness does not expose candidate scores by
  identity, formula metadata, target label, or audit kind to the detector.

## Reproduce

From the repository root:

```bash
rm -rf /tmp/zig-l2-cache /tmp/zig-l2-global /tmp/blank_region_round_l
zig build-exe sparse_poly_discovery/blank_region_round_l.zig -O ReleaseFast \
  --cache-dir /tmp/zig-l2-cache --global-cache-dir /tmp/zig-l2-global \
  -femit-bin=/tmp/blank_region_round_l
/tmp/blank_region_round_l results/blank_region_round_l.csv
/tmp/blank_region_round_l selftest > /tmp/blank_region_round_l.selftest.csv
cmp results/blank_region_round_l.csv /tmp/blank_region_round_l.selftest.csv
```

## Consequence

L2 earns only the first map-making capability: flag a blank region from a
policy-safe failure trace. A stronger next experiment must use this signal to
propose a *reusable* new family, test it on a separately sealed evaluator, and
beat a fixed current-grammar baseline at equal cost.
