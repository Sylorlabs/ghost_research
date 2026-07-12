# Gate v6 — corrected novelty decision (Round G / G1)

**Verdict: PASS as a frozen decision-layer replacement on the F3 battery; not
yet production-wired.** Gate v6 replaces the legacy raw-statistic `R² >= 0.40`
rejection with a directly relevant question: can the existing,
candidate-excluded family menu reconstruct the **held-out target label** using
multiple features to the already-established `COVER = 0.90` bar? On the frozen
nine-target F3 battery it corrects both false rejections (RUN1 and RUN-var2),
keeps all three established remixes rejected, and has no false admits:
**v5 7/9 correct → v6 9/9; novel false rejects 2/6 → 0/6; remix false admits
0/3 → 0/3.**

This is the instrument prerequisite for Round G's downstream certification.
It is deliberately a decision-layer artifact, not an in-loop rewrite of an
existing search path.

## Frozen protocol (before interpretation)

The protocol was frozen from F3's already completed reconstruction audit
([`run1_gate_audit.md`](run1_gate_audit.md)); no target, threshold, feature
pool, split, seed, or K value was added after seeing the G1 decision table.

- **Statistic:** held-out classification accuracy (`cover_before`) of F3's
  greedy multi-feature, candidate-family-excluded reconstruction. It is the
  engine-facing analogue of the tier8 v5-ladder principle: assess what the
  engine can already express, rather than a continuous raw feature's incidental
  linear correlation.
- **Threshold:** `COVER = 0.90`, unchanged from the existing certifier. Gate
  v6 rejects only at `cover_before >= 0.90`; otherwise it admits as novel.
- **Replication rule:** a replicated target must clear COVER on **every**
  frozen replication to be rejected. For RUN1 the gate witness is the minimum
  of F3's three held-out observations (0.9011, 0.8817, 0.8789), hence 0.8789.
  One-seed F3 controls retain their explicitly secondary, one-seed status.
- **No retuning:** old v5 remains `R² >= 0.40`; v6 has no fitted coefficient
  and no post-hoc threshold sweep. `K` is F3's pre-existing 4–12 feature
  budget per control.
- **Validity gates:** exactly 9 target-level cases; 6 known-novel and 3
  known-remix controls; finite COVER values in `[0,1]`; positive K; all gates
  checked by the executable before it writes a result.

The source records the frozen witnesses verbatim from
`results/run1_gate_audit_2026_07_11.csv` (`gate_repro`, `roc`, and `roc_r2`
rows), so this audit does not conceal a fresh, differently configured search
under the same gate name.

## Results

| Target | Known status | F3 multi-feature COVER witness | v5 (raw R²) | v6 | Delta |
|---|---|---:|---|---|---|
| RUN1 (3-seed minimum) | novel | 0.8789 | reject | **admit** | flip |
| RUN-var2 | novel | 0.8686 | reject | **admit** | flip |
| RUN-var3 | remix | 1.0000 | reject | reject | unchanged |
| RUN-var4 | novel | 0.6954 | admit | admit | unchanged |
| C09 | novel | 0.4869 | admit | admit | unchanged |
| RATIO1 | novel | 0.5069 | admit | admit | unchanged |
| MIXMOD1 | novel | 0.6560 | admit | admit | unchanged |
| REMIX-A | remix | 1.0000 | reject | reject | unchanged |
| REMIX-B | remix | 0.9983 | reject | reject | unchanged |

This repairs the F3 failure exactly where the old statistic was known to be
on the wrong axis. RUN1's old raw `R²=0.7347` and RUN-var2's `R²=0.7222`
look highly linearly correlated yet fail the actual reconstruction criterion;
the true remixes reach 0.998–1.000 on the target label. The new gate leaves
the three positive controls intact.

## Reproduce

```bash
cd /home/micah/Desktop/Sylorlabs/ghost_research/sparse_poly_discovery
zig build-exe gate_v6_round_g.zig -O ReleaseFast
./gate_v6_round_g
# writes ../results/gate_v6_round_g.csv
```

Observed output:

```text
gate-v6: 9/9 correct; v5: 7/9; false-reject novel: 2/6 -> 0/6; CSV ../results/gate_v6_round_g.csv
```

Artifacts:

- `sparse_poly_discovery/gate_v6_round_g.zig` — standalone executable gate
  definition plus frozen-protocol validity checks.
- `results/gate_v6_round_g.csv` — per-target old/new decisions and summaries.
- `docs/research/run1_gate_audit.md` — upstream F3 raw reconstruction work.
- `docs/research/tier8_gate_v5.md` — related engine-expressible gate lineage.

## Limits and adoption boundary

1. **This is a re-audit, not an independent reconstruction rerun.** It
   evaluates the corrected gate over F3's measured witnesses. That is enough
   to freeze the rule and quantify decision deltas, but a live G5 run must
   execute the same excluded-family greedy reconstruction on each new
   candidate rather than reuse this fixture table.
2. **The battery is small.** Six novelty controls and three remix controls are
   a regression battery, not a population estimate. Three controls and the
   RUN-var2 outcome are only one seed. The v6 9/9 is a compatibility result,
   not a claim of zero generalization error.
3. **Greedy COVER remains an approximation.** As F3 noted, it is not an
   exhaustive proof that no joint reconstruction exists. It is still strictly
   more aligned with the certifier's actual classification objective than raw
   one-column R².
4. **Replication matters at the boundary.** RUN1 has one 0.9011 witness and
   two sub-COVER witnesses. The all-seed rejection rule avoids declaring a
   feature redundant from a single 0.11-point crossing; future gates must
   retain the same predeclared aggregation rule.
5. **Do not bind blindly in a solve loop.** Tier8 gate-v5 showed that a valid
   verdict-layer gate can still change trajectory economics when made
   in-loop. G1 freezes a corrected certification rule; G5 must measure its
   equal-budget end-to-end impact before any production adoption claim.

## Exact conclusion

F3's 33% target-level false-rejection problem is repaired on its frozen
six-novel/three-remix control battery without a measured regression in the
three established remix calls. Gate v6 is therefore the Round G certification
standard for new, live experiments; its generalization and in-loop economics
remain open tests, not settled facts.
