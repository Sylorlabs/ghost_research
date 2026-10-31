# H6 — conditional direct-proposal assembly with live v6 certification

**Verdict: constrained, partial positive; not an autonomous general router.**
The assembled H3+H5 path received only labelled grids at inference, opened the
human-supplied directed-partition grammar from a generic failure signature,
found and promoted an exact member on **2/3 held-out directed structural
variants**, and used candidate-excluded v6 reconstruction live to admit both
(`COVER=0.6883, 0.5967`, below the `0.90` bar). It safely made **no proposal**
on a third directed variant and fell back to the fixed menu; it also used that
same safe fallback on a held-out threshold-family control.

This is direct failure-guided grammar proposal, not learned family routing:
H1/H2 remain negative/blocked. It therefore does **not** remove the human
structural-language limitation: the directed comparison/partition/modulo
alphabet, orientation signature, fixed menu, verifier, and budget are
human-supplied.

## Frozen protocol

- Four deterministic held-out data sets, 4,800 iid eight-cell grids each,
  split `2400/1200/1200` train/validation/test. Three directed data sets vary
  pivot, modulus, and a non-singleton partition; the fourth is a threshold
  control. `oracle` creates labels, but `propose` takes only `[]Sample` (grid
  plus binary label): no name, formula, family, pivot, mask, or residue enters
  inference.
- Every arm gets exactly **1,270 candidate-evaluation calls**. Direct proposal
  exhaustively evaluates the frozen 254-mask × residue grammar only after its
  generic signature fires. Fixed and random arms consume the same count.
  Hand oracle is an upper baseline with padded audit calls, never inference.
- Candidate-excluded v6 reconstruction learns only global count and inversion
  residue cells on train, then scores test; candidate-family columns are
  absent. `COVER >= .90` rejects as remix; lower values admit/prompt promotion.
- Controls are hand oracle, fixed threshold menu, blind equal-budget random
  directed search, `cold_no_signature` (fixed menu only), and `direct_no_v6`
  (same proposed candidate, deliberately uncertified).

## Results

| held-out target | hand | fixed / cold | one random arm | direct result | v6 decision |
|---|---:|---:|---:|---|---|
| directed pivot 3, mod 3 | 1.000 | 0.644 | 0.675 | 1.000 exact grammar | admit, COVER 0.688 |
| directed pivot 5, mod 2 | 1.000 | 0.628 | 1.000 | 1.000 exact grammar | admit, COVER 0.597 |
| directed partition, mod 3 | 1.000 | 0.592 | 1.000 | signature absent; fallback 0.592 | no proposal/fallback |
| threshold-family control | 1.000 | 1.000 | 0.567 | signature absent; fallback 1.000 | no proposal/fallback |

The random arm's two exact outcomes are retained. Once the finite grammar is
supplied, blind equal-budget enumeration can be competitive or lucky. The
reliable difference is that direct failure evidence has a deterministic valid
route to two variants and safely refuses two it cannot justify; it is not a
win over random on every draw.

Hand solves 4/4; fixed/cold solve 1/4; this assembly solves 3/4 only because
safe fixed fallback handles the threshold control, while it **directly proposes
and v6-promotes 2/3 directed variants**. It does not solve the non-singleton
directed partition. Therefore it is not an end-to-end general prior-choice
result.

## Validity gates and ablations

- Base rates are strictly inside `(0.10, 0.90)` on all four data sets.
- Both direct promotions are exact on validation and test, and candidate-
  excluded v6 cover is below `.90`.
- `cold_no_signature` cannot open the directed grammar and remains fixed-only.
- `direct_no_v6` finds the same two candidates but records
  `SKIPPED_UNCERTIFIED`; it is not a promotion claim. This shows v6 is an
  enforcement step here, while H5's remix control supplies the error-mode test.

## Reproduce

```bash
cd /home/micah/Desktop/Sylorlabs/ghost_research/sparse_poly_discovery
zig fmt genofgen_round_h.zig
zig build-exe genofgen_round_h.zig -O ReleaseFast -femit-bin=/tmp/genofgen_round_h
/tmp/genofgen_round_h
rg 'summary' ../results/genofgen_round_h.csv
```

The raw CSV contains the complete fixed/random candidate-call ledger for every
arm and summary rows with source, signature, v6 decision, cost, and pass state.

## Limitations

This combines H3's proposer with H5's small live v6 decision layer; it is not
production integration and does not retest H5's remix battery. The grammar,
orientation signature, feature basis, gate threshold, budget, and fixed menu
are human choices. The directed-partition miss shows this signature is not a
general representation of directed grammar needs. H6 is a conditional assembly
demonstration, not proof that arbitrary unseen families can be routed.
