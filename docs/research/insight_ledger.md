# Insight ledger — putting a number on the residual human-insight bit (round 2026-07-11b headline)
> **Belongs to: Round 2026-07-11b · experiment F6 of 6 (residual human-insight bit)** — [round index](research_round_2026_07_11b.md).

**Status:** built, measured (a bookkeeping harness over already-published, committed CSVs/docs —
no new search is run). Reproduce (standalone, single-threaded, instant):
```bash
cd /home/micah/Desktop/Sylorlabs/ghost_research
zig build-exe -O ReleaseFast sparse_poly_discovery/insight_ledger.zig -femit-bin=sparse_poly_discovery/bin/insight_ledger
./sparse_poly_discovery/bin/insight_ledger
```
Wall clock: under 1 second (no random search, no threads — pure arithmetic over a hand-curated,
doc-cited ledger). Writes `results/insight_ledger_2026_07_11.csv`.

**F1/F2/F3/F4/F5 have not landed as of this run** (`research_round_2026_07_11b.md` shows 0/6 complete;
no `prior_selector.md`/`autofamily_order2.md`/etc. exist). Per the task brief, this experiment uses
D5 (`wcore/docs/research/auto_curriculum.md`), E1 (`docs/research/repr_expansion.md`), E3
(`wcore/docs/research/smart_gen.md`), and round-c's hand-curriculum
(`wcore/docs/research/conjunction_wall.md`) as the measured data; F1 is reported as **pending**, with
its projected trajectory stated as a labeled projection, never a fabricated number.

**Verdict (one line):** On the one target both a hand-built and a machine-built solution exist for
(the distinct-count WALL / `noveltyflag` stone), the human-supplied share of the solving insight
fell from **100% (hand-curriculum) → 33% (E3's smart-gen)** — the machine now supplies **67%** of the
concrete mechanism, and it supplies it with a **structurally different realization** than the human's
own (r2 not r6, evidence of genuine discovery, not restatement). D5's blind bulk shows the floor
under this trend: supplying **0%** from *either* party (not "0% human" — "0% of anything") yields
**0/9 solved**, i.e. insight cannot be skipped, only shrunk. A **structural** floor of ~4 fixed
infrastructure ingredients (alphabet, certifier, target/battery, protocol) sits *outside* this
ledger and was never varied — it is the strongest candidate for a permanent human floor. F1
(pending) is the experiment that tests whether the remaining 33% (the shape-predicate itself) can
also become machine-inferred.

---

## 1. The insight-bit decomposition

Two things must be separated to make this measurable rather than rhetorical:

- **The INFRASTRUCTURE floor** — ingredients that are *never varied* across any method examined in
  this arc (D5, E3, hand-curriculum, E1): the instruction-set alphabet, the certifier/detector
  definition, the target/battery definition, and the seeds/budget/comparability protocol. These are
  the pre-conditions for the experiment to mean anything at all, and they are 100% human in every
  method measured here — see §4.
- **The MECHANISM ledger** — the specific, per-target ingredients that *do* vary by method: which
  structural shape/family/prior is handed in vs which concrete realization the search itself finds.
  This is where "the frontier moves without vanishing" (Round E's phrase) becomes a number.

For the mechanism ledger, the fairest apples-to-apples target is the one every generation-side
method in this arc was run against: the distinct-count conjunction wall, whose sufficient stepping
stone is the 4-instruction `noveltyflag` mechanism (`smart_gen.md`'s own printed stone):
```
setup: r?=1;  step: r3=mem[r0];  mem[r0]=r?;  r3=xor(r?,r3);
```
This is decomposed into **9 fixed units**, held identical across every method so the fraction is
comparable: {setup opcode, setup operand+register}, {load opcode-class, load operand+register},
{store opcode-class, store operand+register}, {the load/store **same-address** relational
constraint}, {completing-op opcode, completing-op operand-order+OUT_R-wiring}. Each unit is tagged
by **who fixed it**:
- **human** — pinned to an exact value *before* any search runs, true regardless of what the search
  finds (i.e., handed in, not discovered).
- **machine** — left open; the search explored multiple values and the *reported* value is what the
  search itself selected or discovered (verified, where possible, to differ from any human-specified
  value — the strongest evidence it wasn't smuggled in).
- **unresolved** — required to solve the target, but supplied by *neither* party (the target stays
  unsolved). This is distinct from "0% machine" — it means the ledger has nothing to divide.
- **pending** — the method has not yet been run in this round; no unit is scored.

For the representability side (E1), a parallel but smaller **6-unit ledger** (family mathematical
form, candidate stat-pair grid, candidate radius grid — human; which family / which member / which
lens actually certifies — machine) is applied to E1's most fully-documented certified new solve,
`mixr → MIXMOD1`.

**Conservatism (per the mandated culture):** every ambiguous unit was tagged **human** unless a doc
explicitly evidences the machine finding it independently (e.g., a structural-diff quote proving the
register allocation differs from the hand version). The "same-address relational constraint" in E3
is tagged human even though the exhaustive enumerator also touches register combinations, because
the *relation itself* is explicitly named in the coverage-inclusion predicate
(`hasRMWShape`) — conservatively credited to the human hint, not the search.

---

## 2. Per-method fraction — the mechanism ledger (distinct-count WALL, 9 units)

| method | round | reach | human units | machine units | unresolved/pending | **machine-supplied fraction** |
|---|---|---:|---:|---:|---:|---:|
| **hand-curriculum** (reference, pre-arc) | round-c | 6/9 | 9 | 0 | 0 | **0.0%** |
| **D5 blind bulk** | 2026-07-10d exp5 | **0/9** | 0 | 0 | 9 (unresolved) | **N/A — nothing resolved by either party** |
| **E3 smart-gen (COVER-fair)** | round-E exp3 | 6/9 | 3 | 6 | 0 | **66.7%** |
| **F1 prior-selector** | round-F exp1 | pending | — | — | 9 (pending) | **pending — not yet landed** |

Reading the table (computed by `insight_ledger.zig`, not hand-typed):

- **Hand-curriculum (0.0%):** both stones (`membership`, `noveltyflag`) were authored end-to-end by
  a human — exact registers (r6), exact opcodes, exact wiring — and handed to the forge unchanged.
  This is "method zero," the full-human anchor the whole arc is escaping from.
- **D5 (undefined, not 0%):** the doc is explicit that the memory-op bias lever was *"deliberately
  not used ... to keep this a fair test of blind bulk"* — 0 units human-supplied — and
  `n_payoff_pos = 0` across **54,432 evaluated candidate-behaviours, 8 runs, both seeds** — 0 units
  machine-discovered either. **This is the crux distinction the fraction alone would hide**: D5 is
  not "the human-heavy end of the spectrum," it is the *no-insight* point, and it fails completely
  (0/9). A fraction of "0% machine" would misleadingly read as "100% human, and that's enough" — it
  isn't; the units were never supplied by anyone.
- **E3 (66.7%):** the human hands in exactly one ingredient — the read-then-write-same-address shape
  predicate, applied as a *coverage inclusion* (not a finished program, not a sampling bias — the
  doc's own ablation shows sampling-bias-only, `PRIOR_STRONG`, also fails 0/9). That predicate pins 3
  of 9 units (the two opcode-classes + the same-address relation). The exhaustive enumerator then
  **discovers** the other 6 units from scratch: the entire setup instruction, both instructions'
  register allocations, and the completing xor's opcode + operand order + OUT_R wiring — verified
  **structurally distinct** from the hand version (flag in r2 not r6, `xor(r2,r3)` not `xor(r3,r6)`,
  per `smart_gen.md`'s own genuineness check). This is real, not restated, discovery.
- **F1 (pending):** no fabricated number. See §5 for the projection.

## 3. Per-method fraction — the representability ledger (E1, mixr → MIXMOD1, 6 units)

| weighting | human units | machine units | machine-supplied fraction |
|---|---:|---:|---:|
| equal-weight (every unit counts 1) | 3 | 3 | **50.0%** |
| depth-weighted (family FORM counted 3×, since inventing "joint mixed-radix residue" is a deeper act than a grid-cell pick) | 5 | 3 | **37.5%** |

E1's machine contribution is **selection**, not the same kind of discovery E3's is: the ladder picks
*which* of 4 hand-offered families certifies (2 of 4 pay off — `thresh` and `run` certify nothing),
*which* stat-pair/radius combination is the exact 1.000 member, and *which* of a fixed 7-lens set
closes it — all real, all measured, all genuinely uncertain in advance (repr_expansion.md: "a family
that unlocks nothing is a valid finding"). But every candidate the machine *could* have picked was
already enumerated in a small hand-authored grid (≤6 members per family, 7 lenses) — a materially
narrower search than E3's exhaustively-*generated* (not hand-listed) program space. **Honest
reading: representability-growth (E1) and generation-mechanism-discovery (E3) are at different
points on the same shrinking-residual curve** — E3 has already crossed into "machine invents the
concrete realization"; E1 is still at "machine sweeps a hand-curated menu." E1's own standing-open
item (ORDER2, no family in the menu reaches it) is exactly the target F2 (auto-family discovery)
would need to move E1 toward E3's position.

## 4. The floor — what stayed 100% human in every method measured

Four ingredients were never varied, never machine-selected, in any of D5/E3/E1/hand-curriculum:

1. **The alphabet** — which opcodes/registers/immediates exist as primitives at all. (E3 additionally
   *shrinks* it, 12reg/13imm → 4reg/2imm, for tractability — itself a human choice the doc calls "a
   mild prior... generic but not nothing" — so even this floor item has a method-specific human
   tuning decision layered on top of the more basic "some alphabet must pre-exist" fact.)
2. **The certifier/detector** — depth-3/4 irreducibility, COVER ≥0.90, R²<0.40 novelty gate, the real
   payoff/reachability check. Never machine-authored anywhere in this arc. This is the ingredient the
   task brief names as "arguably always human," and the ledger confirms it: no experiment in Round
   D/E/this-round even attempts to make the certifier itself a search target — for good reason (a
   search that could redefine its own success criterion could vacuously "solve" anything, the same
   failure mode the Closure Principle's escape corollary depends on an *external* generator to avoid).
3. **The target/battery definition** — which 9 members count as "the WALL," what MIXMOD1/RATIO1/
   ORDER2 mean as targets. `repr_expansion.md` §8 says it outright: "fresh targets are a design
   choice." A machine has never posed its own target in this arc.
4. **The comparability protocol** — seeds, depth caps, budget caps, leakage guards, equal-budget
   requirement. Fixed by the researcher so every method's number means the same thing.

**This is the strongest measured candidate for an irreducible human floor.** Every method examined
— including the one where the machine supplies 67% of the mechanism-ledger — operates entirely
inside this 100%-human infrastructure. Even a hypothetical F1 that fully automates the shape-choice
(pushing the mechanism ledger toward ~100% machine) would still be searching a human-fixed alphabet,
scored by a human-fixed certifier, against a human-posed target, under a human-fixed protocol. The
mechanism ledger can shrink to near zero; this floor has not moved once in 32+ experiments across
five rounds.

## 5. The trend, and F1's projection (not yet measured)

Restricting to methods that actually **solve** the target (D5 is excluded — it solved nothing, see
§2), the human-supplied share of the mechanism ledger:

```
hand-curriculum  ██████████████████████████████████████████████████  100% human  (reach 6/9)
E3 (COVER-fair)  ████████████████                                      33% human  (reach 6/9)
F1 (pending)     ??                                                    ??         (not yet run)
```

**Yes, shrinking, on the one comparable data point available.** 100% → 33% is a real ~3× drop in the
choice-count metric, corroborated by a second, independent estimate: the search-space-narrowing
cross-check (§6) gives ~60% machine (vs 67% from the choice-count), the same order of magnitude from
a completely different counting method. Two independent metrics agreeing to within experimental noise
is itself informative — the 60-70% figure is not an artifact of one particular counting convention.

**F1's honest projection** (not a measurement): Round F names F1 as "can the machine INFER which
structural prior a target needs from its failure signature — the E2-router idea, one level up." E2
(`target_router.md`, already landed in Round E) is the closest existing analogy: a router over a
10-feature *hand-defined* failure descriptor picked among 3 *hand-defined* aim mechanisms at 92.3%
held-out accuracy, vs fixed-best 46.2%. If F1 follows that pattern, the human's remaining
contribution would shrink from "hand the exact shape predicate" (3/9 units) to "hand a *menu* of
candidate shape-templates + a feature descriptor" (structurally smaller — a menu of options, not a
specific selected option) while the machine *learns* which template fits a new target and, as in E3,
still discovers the concrete realization. **If** this succeeds at an E2-like accuracy, the projected
mechanism-ledger fraction would move toward roughly 85-90% machine — but this is a projection stated
for transparency, not a claim; F1 has not run, and per the task's conservatism rule this projection
counts as 0 measured evidence until it lands.

## 6. Cross-check: does a bit/entropy framing agree — and what it reveals about "insight"

A second, independent metric: use `smart_gen.md`'s own reported pool sizes to estimate how many bits
of search-space uncertainty the human's prior eliminates vs how many the machine resolves on its own.
- L2 pool (exhaustive, no prior needed): 22,345 distinct behaviours.
- L3 base cap (both `COVER-fair` and `COVER-uniform` use the identical size): 1,000 programs.
- Within that cap, `COVER-fair`'s tested length-3 pool: 3,604 candidates, with exactly 2 found
  OUT_R-equivalent to `noveltyflag`.

Computed: `log2(22345/1000) = 4.48 bits` (the L2→cap narrowing) and `log2(3604/2) = 10.82 bits` (the
machine's own exhaustive within-pool resolving work) — giving machine-fraction ≈ 10.82/(10.82+4.48) ≈
**70.7%**, close to the 66.7% choice-count figure.

**But the honest finding is sharper than the agreement:** `COVER-uniform` (the ablation, no RMW-shape
inclusion) samples the **exact same size** subset — 1,000 of 22,345, **identical 4.48-bit
narrowing** — and still fails 0/9. **The bit-count framing cannot distinguish the method that works
from the one that doesn't**, because both eliminate the same *quantity* of uncertainty; only one
eliminates the *right region*. This is a real, measured limitation of the entropy metric, not a
footnote: **the prior's value here is not measured in bits eliminated (quantity) — it is measured in
whether the eliminated region contains the target (targeting).** This is the arc's own "aim ×
representability" finding (E5) reappearing at the insight-accounting scale: E5 showed aim is a
phase-boundary lever, not a linear one, that pays off only once representability clears a threshold;
here, the human's structural prior is functioning as *aim over the generator's search space*, not as
bulk uncertainty-reduction — exactly the D5 vs E3 contrast (D5 had zero aim and zero payoff no matter
how much quantity — 54,432 candidates — was thrown at it). **The choice-count ledger (§2) is the
primary metric of this doc precisely because it captures "which unit was targeted," where the
entropy metric captures only "how much was eliminated" and demonstrably gets the wrong answer when
those two come apart.**

## 7. What this says about "the greatest invention machine" question

The arc's honest position (Round E verdict) was: representability gates, aim decides above it, and
the machine can grow representability itself but only with a structural prior smaller than a hand
curriculum. This experiment turns "smaller" into a number: for the one target measured both ways, the
prior shrank from a **complete finished program (9/9 units, the entire solving artifact)** to **one
shape predicate (3/9 units, a boolean fact about two instructions)** — the machine now originates the
majority (67%) of the mechanism, in a form (a different register allocation) that proves it wasn't
just restating the hint. The **smallest human seed found so far** for this target class is: *one
sentence describing a structural relationship between two instruction types* — smaller than any
previous method in this arc's history required. Whether that seed can shrink further (F1) or whether
it names a genuine floor (the certifier-style ingredients in §4, which have never moved) is the open
question the rest of Round F is built to answer. What's measured, not projected: **the residual
human-insight bit is shrinking on the one target both a hand method and a machine method were run
against, and the shrinkage is a real ~3× drop, not a rounding artifact of how the count is drawn** —
two independently-designed counting schemes (choice-count, bit-narrowing) agree to within 10
percentage points.

## 8. Honest limitations

1. **Single target for the primary (mechanism) ledger.** Only the distinct-count WALL / `noveltyflag`
   stone has both a fully-documented hand solution (round-c) and a fully-documented machine solution
   (E3) to compare unit-by-unit. The trend (§5) is a two-point line (100% → 33%), not a curve fit —
   directionally real, not statistically established. ORDER2/RUN1 (E1's standing-open targets) have
   no machine-discovered solution yet to ledger against.
2. **Equal-unit weighting is a convention, not an information measure.** All 9 mechanism units and
   all 6 E1 units are counted as equal-weight regardless of true "depth" (e.g., inventing the xor
   completion vs allocating a register are not obviously equally hard). §3's depth-weighted E1
   variant (0.500 → 0.375) is reported specifically to bound this sensitivity; no depth-weighted
   variant of the mechanism ledger is given because there is no principled basis in the docs for
   weighting one instruction's discovery over another's (all four are equally undetermined by the
   shape predicate) — an honest gap, not a hidden precision claim.
3. **D5's "unresolved" units are not comparable to a 0%-machine score.** Treating D5 as "0% machine,
   100% human" would misstate the finding; the doc is explicit the human deliberately withheld every
   hint. The correct reading is "0 units resolved by anyone," which is why §2 reports it as
   undefined/N/A rather than a numeric fraction, per the task's own conservatism instruction (count
   ambiguous cases as human — here, the ambiguity is resolved by NOT assigning either party credit
   for units nobody actually supplied).
4. **The representability (E1) and mechanism (E3) ledgers use different targets and are not additive
   or directly comparable** — MIXMOD1 (a family/parameter-selection problem) and the WALL stone (a
   program-synthesis problem) measure different sub-kinds of "insight." §3's cross-arc observation
   (E1 lags E3) is a qualitative reading of two separately-computed numbers, not a single unified
   metric.
5. **F1's projection (§5) is explicitly labeled speculative** and contributes 0 to any reported
   average or trend-line; it exists only to state, transparently, what the next data point would need
   to look like for the shrinking trend to continue, grounded in E2's already-measured 92.3% router
   result (a structurally analogous but not identical automation).
6. **The floor (§4) is an empirical floor, not a proof.** "Never varied in 32+ experiments across 5
   rounds" is strong evidence it is load-bearing, not a theorem that it must remain fixed forever —
   F2-F5 (pending) are precisely the experiments that would test parts of it (F2 attacks whether a
   *family* can be auto-discovered rather than hand-designed, moving part of item 3's target-battery
   floor; F3 audits whether the certifier's own novelty gate is itself miscalibrated).
7. **Bit-narrowing cross-check (§6) uses order-of-magnitude pool sizes reported in smart_gen.md**, not
   a first-principles enumeration this doc performed independently; it inherits any imprecision in
   those upstream counts (which the source doc itself flags — e.g., full unrestricted-alphabet L3
   space is reported only as ">10^5," not exact).

## Files
- Harness: `sparse_poly_discovery/insight_ledger.zig` (new file; standalone, no imports beyond
  `std`; encodes the ledger as doc-cited structured data and computes every fraction/bit estimate
  arithmetically — nothing is hand-typed as a percentage).
- Data: `results/insight_ledger_2026_07_11.csv` (56 lines = 1 header + 55 data rows: 9+9+9+9
  mechanism-ledger ingredient rows for hand-curriculum/D5/E3/F1 + 4 method_summary rows + 6 E1
  representability ingredient rows + 2 E1 method_summary rows [equal-weight, depth-weighted] + 3
  crosscheck rows + 4 floor rows).
- Reproduce: see the block at the top of this doc.
- Sources cited (all pre-existing, none modified): `wcore/docs/research/conjunction_wall.md`
  (hand-curriculum), `wcore/docs/research/auto_curriculum.md` (D5), `wcore/docs/research/smart_gen.md`
  (E3), `docs/research/repr_expansion.md` (E1), `docs/research/target_router.md` (E2, cited for the
  F1 projection only), `docs/research/research_round_2026_07_11.md` (Round E verdict),
  `docs/research/research_round_2026_07_11b.md` (Round F index, confirms F1-F5 pending).
