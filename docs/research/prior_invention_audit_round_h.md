# H4 — adversarial audit of G4/H3 prior invention

**Verdict: MIXED / constrained result survives, broad grammar-invention claim does not.**

G4/H3's directed-partition enumerator is real and robust *inside the
human-supplied singleton-orientation admission regime*: it recovered exact
members across two seeds, changed pivots, and changed modulus/residue settings.
Under a genuinely equal 1,270-evaluation blind-directed control, however,
blind search also finds an exact member in 56.25–68.75% of trials. The reliable
advantage is therefore exhaustive selection after grammar admission, not a
large sample-efficiency advantage over blind search in this small grammar.

More importantly, the pre-existing admission signal is not generic across the
directed grammar. An unseen two-cell-partition target is exactly representable
by the same grammar and is recovered by exhaustive selection at 1.000
validation/test accuracy, but its singleton-orientation probe is only 0.592.
It fails the >=0.75 admission gate. Thus the claimed `directed_partition`
grammar had been admitted using a **singleton-shaped prior**. That is legitimate
for the narrow target class tested; it is answer-shaped if described as general
directed-partition invention.

## Scope and frozen pre-run contract

Scoped artifacts only:

- `sparse_poly_discovery/prior_invention_audit_round_h.zig`
- `results/prior_invention_audit_round_h.csv`
- this report

The audit fixes an eight-cell iid grid (values 0–5), 2,000 examples per
condition, and disjoint 1,000/500/500 train/validation/test slices. The
proposer API consumes `[]Sample` (grid + binary label) only. It has no target
name, formula, family label, pivot, anchor/mask, modulus, or residue input.
Generator specifications exist outside that API solely to create labels.

Every directed arm gets exactly 1,270 validation evaluations: all 254
nontrivial masks crossed with mod-2/mod-3 and all legal residues. Blind random
draws uniformly from those 1,270 legal candidates, with replacement, at the
same 1,270 evaluation budget and 128 independent trials per condition. The
fixed global-threshold menu is also evaluated in a 1,270-call cycle, but has
only 25 distinct members; it is a menu/reach control, not an equally broad
grammar-search control.

Pre-run acceptance gates were: binary base rate in (0.10, 0.90), fixed menu
<0.75 validation, singleton orientation probe >=0.75, selected direct member
>=0.99 validation and test, direct test greater than fixed validation, and
blind exact-hit rate <0.95. The last condition prevents calling a nearly-certain
blind hit an aiming result. Conditions and seeds were encoded before execution.

## Results

| condition | selected member | fixed validation | singleton probe | direct val/test | blind exact hit, 128 x 1,270 | result |
|---|---|---:|---:|---:|---:|---|
| singleton pivot 3, mod 3/residue 1, seed 1 | `0x08 / 3 / 1` | 0.662 | 1.000 | 1.000 / 1.000 | 0.6563 | pass |
| same target, independent seed 2 | `0x08 / 3 / 1` | 0.662 | 1.000 | 1.000 / 1.000 | 0.5625 | pass |
| singleton pivot 5, mod 3/residue 2 | `0x20 / 3 / 2` | 0.670 | 1.000 | 1.000 / 1.000 | 0.6875 | pass |
| singleton pivot 1, mod 2/residue 0 | `0x02 / 2 / 0` | 0.606 | 1.000 | 1.000 / 1.000 | 0.6797 | pass |
| **held-out two-cell partition `{1,5}`, mod 2/residue 0** | `0x22 / 2 / 0` | 0.548 | **0.592** | 1.000 / 1.000 | 0.5625 | **admission FAIL** |

All base rates were non-degenerate: 0.2450–0.6005. The raw CSV has 128
equal-budget random-trial rows plus one summary row for each condition. One-off
blind exact hits are retained, including the maximum of 1.000 in every
condition; they are not discarded as inconvenient controls.

## Ablations and adversarial findings

1. **Equal budget changes the interpretation.** H3's direct enumerator is
   deterministic because it exhausts the 1,270-member supplied grammar. A
   blind equal-budget sampler succeeds 56–69% of the time, not near zero. The
   appropriate claim is reliability from exhaustive coverage after admission,
   not strong search-efficiency superiority.
2. **Pivot/modulus/residue variation passes.** The chosen member tracks the
   generator changes with exact test accuracy, so no fixed pivot, residue, or
   seed is baked into `selectDirected`.
3. **Held-out structural variant exposes the limitation.** A two-cell mask is
   representable in the enumerated grammar and found by the full enumerator,
   but is rejected before it can be proposed because the admission probe only
   asks singleton questions. This is direct evidence that the failure signature
   is narrower than its grammar's representational reach.
4. **No semantic leakage in inference, but a structural prior remains.** The
   source inspection confirms `selectDirected([]Sample)` receives only labels
   and grids. Yet the human supplied compare/partition/modulo primitives *and*
   chose singleton orientation as the gateway. That gateway encodes a relevant
   shape. This is not primitive invention and not generic grammar discovery.

## Reproduction

```bash
cd /home/micah/Desktop/Sylorlabs/ghost_research/sparse_poly_discovery
zig build-exe prior_invention_audit_round_h.zig -O ReleaseFast -femit-bin=prior_invention_audit_round_h
./prior_invention_audit_round_h
awk -F, '$2=="summary" {print}' ../results/prior_invention_audit_round_h.csv
```

On this machine the run completed in about 4.5 seconds, CPU-only.

## What this permits—and what it blocks

Permitted: use the directed enumerator as a **constrained proposer option** for
targets whose independently validated failure representation licenses the
singleton-orientation regime.

Blocked: claiming that G4/H3 has autonomously discovered the general
directed-partition family, that it has lifted off human structural-prior
selection, or that it holds a decisive equal-budget search advantage. A future
proposer must derive a representation that can admit both singleton and
multi-cell directed structures without being handed the relevant probe shape.
