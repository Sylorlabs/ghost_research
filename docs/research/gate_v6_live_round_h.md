# H5 — live gate-v6 integration audit (Round H)

**Verdict: positive live-loop evidence, but not a production-adoption result.**
The corrected gate-v6 rule was executed inside a fresh, deterministic candidate
and promotion loop rather than applied to G1's frozen fixture values.  On the
predeclared four-candidate battery it made **4/4 correct decisions**, versus
legacy raw-statistic R2's **2/4**.  It admitted RUN1, RUN-var2, and the G4-type
directed-partition candidate, rejected the exact count remix, and promoted
three candidates versus legacy's one.

## Question and boundary

G1 established a decision-layer replacement on F3's frozen witness table:
reject a candidate only if a candidate-family-excluded, multi-feature
reconstruction reaches `COVER = 0.90` on held-out labels.  H5 tests the open
edge: does that same rule behave correctly when it is invoked while candidates
are considered and admitted candidates change the available library?

It is **not** a wiring change to a production search path.  It is a compact,
standalone live-loop audit using synthetic, balanced grids and an explicitly
limited reference library.  Therefore it supports the claim "the rule has
live-loop evidence on this protocol," not "replace the production gate now."

## Protocol (frozen before results)

- **Candidates and fixed order:** RUN1; RUN-var2; `countGE3 >= 4` exact remix;
  G4-type `rank(cell3) mod 3 == 1` directed-partition candidate.
- **Truth controls:** RUN1, RUN-var2, and G4-type are positional/structural
  novel candidates.  The count target is an exact remix because `count3` is
  already in the pre-existing library.
- **Fresh data:** each candidate receives a separately generated deterministic
  1,800-row *balanced* grid sample (900 positive/900 negative), seed
  `0x48355F4C49564531 + 17*order`; train/validation are 1,080/360 rows.
  Balancing prevents an all-negative classifier from passing COVER.
- **Candidate-exclusion:** candidate family columns are never supplied during
  that candidate's reconstruction.  A predeclared global non-run/non-directed
  base library is `{count>=2,count>=3,count>=4,sum-bin,inversion-bin,
  spread-bin}`.  A candidate admitted earlier in a given loop becomes an
  ordinary prior column for later *different-family* candidates.
- **Live reconstruction:** greedy-select four excluded-library stumps on train;
  held-out model is a fixed two-of-four vote.  `cover_before` is validation
  accuracy.  The selected columns and thresholds are emitted in every raw row.
- **v6 decision:** reject iff validation COVER is `>= 0.90`; otherwise admit
  and promote.  **Legacy comparator:** reject iff the maximum squared Pearson
  correlation of the candidate raw statistic with a base raw feature is
  `>= 0.40`.  Legacy deliberately remains the wrong-axis comparator.
- **Acceptance gates:** finite rows; balanced labels by construction; exactly
  four candidates; one genuine remix and three genuine novelties; fixed seed,
  split, feature menu, vote rule, threshold, and order.  No result-directed
  parameter retuning is allowed.

## Results

| Candidate | Truth | Legacy raw R2 / decision | v6 held-out COVER / decision | Effect |
|---|---|---:|---:|---|
| RUN1 | novel | 0.6382 / reject | 0.7611 / **admit** | fixes false reject |
| RUN-var2 | novel | 0.6516 / reject | 0.7694 / **admit** | fixes false reject |
| `countGE3 >= 4` | remix | 1.0000 / reject | 0.9194 / **reject** | preserved true reject |
| G4 directed partition | novel | 0.0148 / admit | 0.5889 / **admit** | preserved novel admit |

The loops finished at legacy **2/4**, v6 **4/4**.  Legacy promoted only the
G4 candidate.  V6 promoted the three novel candidates and did not promote the
remix.  The trajectory difference is thus `+2` correctly admitted novelties
and `+2` total promotions under the same candidate order and budget.  The raw
CSV is byte-identical on repeat execution (SHA-256
`03e39c7683841c0b785ff791264911b25e3debb7119b6e6f4ead51e9da7b0b39`).

## Reproduce

```bash
cd /home/micah/Desktop/Sylorlabs/ghost_research/sparse_poly_discovery
zig build-exe gate_v6_live_round_h.zig -O ReleaseFast -femit-bin=/tmp/gate_v6_live_h
/tmp/gate_v6_live_h
# H5 live gate: legacy=2/4 v6=4/4; promotions legacy=1, v6=3
# writes ../results/gate_v6_live_round_h.csv
```

Artifacts:

- `sparse_poly_discovery/gate_v6_live_round_h.zig` — standalone harness.
- `results/gate_v6_live_round_h.csv` — two per-candidate loop rows plus
  aggregate raw outcome.
- `docs/research/gate_v6_round_g.md` — upstream decision-layer rule and its
  frozen F3 battery.

## Limits and exact conclusion

This is live evidence for the **decision layer**, not evidence that the
production engine's entire feature menu, scoring model, or promotion economics
are safe.  The reconstruction model is intentionally small and the target
battery is four known controls; it does not estimate population error.  The
G4-type target is a structural analogue, not a rerun of every G4 search
condition.  Also, later candidates may see earlier accepted columns, so this
is a trajectory measurement rather than four independent fixed-library calls.

Within this frozen protocol, gate-v6 repairs the two RUN false rejections and
preserves the count-remix rejection while safely changing the live promotion
trajectory.  A subsequent end-to-end assembly may use v6 as its certification
standard, but production adoption still requires integration against the real
candidate grammar and a broader adversarial control battery.
