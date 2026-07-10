# Research Round 2026-07-10 — eight parallel experiments toward "way better than AlphaEvolve"

**Status:** LIVE — updated as each experiment lands. 6/8 complete.
**Design:** Eight independent experiments launched in parallel (one subagent each),
derived from the gap analysis against AlphaEvolve: the repo is ahead on the
*certification* axis (irreducibility certificates + remix taxonomy = a defensible
"genuine invention" claim AlphaEvolve structurally cannot make) and behind on the
*significance* axis (targets that matter). Constraints on every experiment:
new files only (no edits to shared sources), standalone `zig build-exe`,
≤2 threads, runs ≤15 min, independent verification for every claim, negative
results documented as findings.

## Placement context (the invention tier ladder, `tier8_mega_plan.md`)

AlphaEvolve = a Tier 2 verifier-gated loop with a rented Tier 6 generator (LLM
ensemble) at data-center scale; no tax gate (Tier 5), no problem invention
(Tier 7), no framework/instrument invention (Tier 8). This round attacks:
target significance (exp 1–2), proposer richness without an LLM (exp 3–4),
tax-gated promotion (exp 5), Tier 8 load-bearing-ness (exp 6), the efficiency
claim (exp 7), and our own foundations (exp 8).

---

## Verdict table

| # | Experiment | Status | Headline | Doc |
|---|-----------|--------|----------|-----|
| 1 | LABS merit-factor campaign | **DONE** | Proven optima N=2–24 (23/23 match literature); matched best-known at all N=25–43 and every odd N≤59; honest misses at 12 lengths (even N≥44 + {61,63,64}). Verifier: 63/63 verified, 3/3 planted lies refuted. Nothing new-to-humanity. | `boundary_crossing/docs/research/labs_campaign.md` |
| 2 | Addition-chain campaign v2 | pending | — | `boundary_crossing/docs/research/addchain_v2.md` |
| 3 | A10 Clifford binding ablation | **DONE** | Ceiling broken: 0.508 → 0.976 (6 seeds, zero overlap). Deflation control: plain Hadamard-real bind = 0.978 — the lever is leaving GF(2) for a magnitude-carrying algebra, not the geometric product. Escape corollary confirmed. | `sparse_poly_discovery/docs/research/a10_clifford_binding.md` |
| 4 | A1–A6 iterated atom promotion | **DONE** | No fixed point (depth-3 certifier bar too weak); corrected held-out reach 3/18 → 4/18 — 6/8 raw flips were SELF matches. ~5% certifier leak caught at depth 4. Ten escape rungs bought ONE genuine behaviour. | `wcore/docs/research/a1a6_iterated_promotion.md` |
| 5 | Tax gate as promotion gate (A/B/C) | **DONE** | Nuanced negative: compounding is REAL (survivor library instantly solves later targets; no-promotion arm fails fresh composition P8 3/3 seeds) but hard-gating loses — starves library 33→9, drops 2 solves, 5.4× eval cost. **B > A > C; keep measurement-only**, gate at library export if at all. | `docs/research/tier8_tax_gate_promotion.md` |
| 6 | Tier 8 framework-revision ablation | **DONE** | **Existence proof found — revision IS load-bearing.** C08 parity-count solved 3/3 seeds only with revision (OFF: certified escape tax-blocked, cov~0.50; ON: promoted, cov=1.000). ON solved 4 targets OFF never did, with fewer evals. Caveat: post-revision tax is vacuous for certified escapes. | `docs/research/tier8_ablation.md` |
| 7 | H50–H52 scaling laws | pending | — | `docs/research/scaling_laws_h50.md` |
| 8 | I53 falsification + G49 cross-audit | **DONE** | **Crack found:** the "emergent pair" block of `CLOSURE_PRINCIPLE.md` is false as printed (x&(x−1) via SUB alone at depth 6; the walls were depth/register bounds, not closure). Core theorem SURVIVED (exact infinite-depth fixpoint proof at u2). Affine-theorem off-by-one fixed (order bound n+1=65). G49: 5016/5016 agreement. | `docs/research/i53_falsification_2026_07_10.md` |

---

## Completed-experiment detail

### 1. LABS (dial 3 at real scale)
- Exhaustive Gray-code scan (2^(N−1), s₀ fixed) proves the optimum at every
  N≤24; all 23 reproduce recalled literature values → audits both search and
  the embedded best-known table. F(13)=14.0833 (Barker, E=6).
- Tabu + skew-symmetric tabu (odd N) matches recalled proven optima at all 19
  lengths N=25–43 (F(27)=9.8514, F(42)=8.7327) and every odd N≤59
  (F(57)=8.6410, F(59)=8.4902). ~1.7B ΔE probes, 4m15s, single-threaded.
- Yield curve (1,192 improvement events): plain tabu stalls at F=7.13 on N=57;
  the skew-symmetric restriction closes to optimum 8.64 — a measured example of
  a search-space restriction acting as the escape generator.
- **Misses (honest):** all even N≥44 plus {61,63,64} (worst N=64: E=312 vs
  known 208). Skew-symmetry only exists for odd N → even-N needs memetic /
  richer move sets. Proofs beyond N≤24 need Mertens-style branch-and-bound.
- Independent verifier `scripts/zig/labs_check.zig`: shared-nothing, own O(N²)
  energy, own brute optimality re-proof N≤22; 63/63 real claims verified,
  refutation test 3/3 planted lies caught (exit 1).
- **Verdict:** the FunSearch/AlphaEvolve *shape* (unknown target + sound
  verifier + beats naive baseline) now runs end-to-end at CPU-seconds scale.
  Nothing new-to-humanity; the gap to records is quantified, not vibes.

### 3. A10 Clifford binding (proposer richness without an LLM)
- Arm (a) XOR/bundle baseline reproduces the known ceiling: 0.508 ± 0.013
  (majority base rate 0.529). Arm (b) Cl(13,0) geometric-product bind + same
  linear readout: **0.976 ± 0.006**. Arm (c) linear probe over raw Clifford
  encoding: 0.978 ± 0.016.
- Controls clean: shuffle-label 0.505 (no leak); raw ≈ standardized (not a
  conditioning artifact).
- **Deflation (the important part):** plain Hadamard real-valued bind scores
  0.978 — indistinguishable from Clifford. The out-of-closure generator is
  "magnitude-carrying algebra instead of GF(2)", and the minimal version
  already saturates this (mass-symmetric, effectively one-sided) predicate.
  Clifford's grade-2 relational capacity was not exercised here.
- Replicates and upgrades the prior single-seed A10 (adds the two controls it
  lacked). **Closure escape corollary: confirmed at 6 seeds.**

### 4. A1–A6 iterated promotion (does the escape ladder keep paying?)
- 10 rounds × 2 seeds, novelty forge (pop 90 / gens 45) + depth-3 exhaustive
  certifier; library 5 → 15 atoms, promotion never starves → **no fixed
  point**; earlier "saturation" was a search-budget artifact.
- **Key decomposition:** raw held-out reach 3/18 → 7/18, but 6 of 8 flips are
  SELF matches (promoted atom ≡ a decoy target — the forge re-drawing its own
  distribution). Corrected: **3/18 → 4/18**; one genuine composed flip per seed
  (xor-scan via a promoted atom applied twice). The structured family
  (distinct-count, hash-table, union + 9 hidden compositions) never flips.
- Retro-audit at depth 4–5: 1/20 promoted atoms retroactively reducible
  (**~5% certifier leak**), 3/20 redundant vs final library.
- **Verdict:** closure escapes don't run out but mostly stop paying; the
  bottleneck is coupling novelty pressure to the frontier of interest (or a
  deeper certifier), not more rounds. Direct motivation for exp 5's tax gate
  as the coupling mechanism.

### 5. Tax gate as promotion gate (A/B/C — does gated novelty compound?)
- 3 seeds × 3 arms × 19 targets, equal protocol; arms realized purely via
  existing `pub var` toggles (`eqtax.strict_enabled`,
  `eqtax.reality_lane_enabled`), zero edits to existing files.
- Aggregate: **A (gated)** 55/57 solves, 9 kept promotions, 83 blocked, 6398
  evals. **B (current: promote on certifier, tax measured)** 57/57, 33 kept,
  1191 evals. **C (no promotion)** 54/57, 2261 evals.
- **Compounding is real:** arm A's 3-feature-per-seed survivor library
  (`sum%7`, parity-Walsh `χ{0xFF}`, +1) instantly solves the survivor-designed
  later targets P3/P4 on every seed; arm C fails fresh composition P8 on all
  3 seeds (0.843–0.847) while both library-carrying arms solve it.
- **But hard-gating loses:** the gate never exceeds B — B's remix-verdict
  promotions are what make repeats free and carry the borderline B4/B10
  solves A loses. Gating starves the library (33→9), drops 2/33 phase-1
  solves, and inflates eval cost 5.4× (blocked rungs re-propose + re-certify;
  each blocked check pays the greedy tax fit).
- **Recommendation adopted: keep measurement-only** (the shipped v4
  strict-tax + reality-lane config is already the right hybrid). If a gate is
  wanted, put it at library *export* (wcore lift) or as search
  deprioritization — never as a block inside the solve loop.
- Engineering note (shared with exp 6): the tax greedy fit needs ~32MB stack;
  run it on a 512MB-stack worker thread or a plain binary segfaults.

### 6. Tier 8 framework-revision ablation (is the just-PASSed loop load-bearing?)
- Two arms × 3 seeds (production seed + both battery-C held-out seeds),
  identical code path and ladder caps, both starting at strict tax basis v3.
  ARM-OFF frozen forever; ARM-ON carries the T8-AG-21 remix alert (checked ≥5,
  novel rate <0.20) firing a witnessed T8-AG-22/25 revision to v4.
- **Existence proof (the thing the Tier 8 PASS lacked):** C08 "parity count",
  3/3 seeds — ARM-OFF finds a *certified* walsh escape that the v3 tax blocks
  as greedy-basis remix (2 blocked certified escapes per seed, saturates at
  cov ≈ 0.50); ARM-ON's post-revision gate promotes the same escape,
  cov = 1.000. Secondary: B10 on 1/3 seeds (indirect library-trajectory
  effect; OFF missed by 0.002 — reported, not leaned on).
- Aggregate: battery B 32/33 (OFF) vs 33/33 (ON); battery-C ladder-only slice
  0/33 vs 3/33; novel promotions 3 vs 20; ARM-ON used **fewer** evals
  (2072 vs 4412) — not a compute artifact. Revision fired at target 1 in every
  ON run.
- **Diagnosis for a decisive battery:** B is too easy (rescue lanes bypass the
  tax); 10/11 battery-C targets too hard for both arms (ladder lacks an xor
  primitive). The decisive band — ladder-reachable but v3-blockable —
  currently contains ~one target. Fix: add parity-of-count / sum%k /
  walsh-of-subset composites in that band, or admit xor_popcount as a ladder
  feature.
- **Honest caveat:** v4's escape-authentic lane condition is identical to the
  certifier's escape condition, so post-revision the tax is vacuous for
  certified escapes (0 post-revision blocks, 100% novel). Revision is proven
  load-bearing *for solves*; NOT proven to retain novelty discrimination.
  That is the next gate to design.
- Engineering note: the tax greedy fit needs ~32MB stack → harness runs it on
  a 512MB-stack worker thread (default 8MB main stack segfaults).

### 8. I53 falsification + G49 cross-audit (red-team our own foundations)
- **The crack (attack b — depth push): the "emergent pair" refinement block in
  `CLOSURE_PRINCIPLE.md` is REFUTED as printed.** On the repo's own substrate
  (u8, K=2), BFS found `x&(x-1)` with **SUB alone at depth 6** (the repo had
  searched only ≤3), `x|(x*x)` without OR or MUL (19 instrs of
  {SHR,SHL,XOR,NOT,AND}), and `x&(x-1)` via {OR,SHL,XOR}. All three verified
  exhaustively in Zig and independently re-verified in Python. New qualifier:
  the synergy substrate's walls are **(depth, register-count) resource
  bounds, not algebraic closure** — base+{AND} is functionally complete over
  GF(2) given registers.
- **The core theorem SURVIVED, and is now stronger:** at u2 the affine base
  reaches an exact closure **fixpoint** (64/256 functions) with the
  genuinely-nonlinear targets unreachable at *any* depth — an infinite-depth
  proof, not a budget claim. Affine base = 0/5 targets at every width/depth
  tested (u4 depth 9, u8 depth 8).
- Boundary abuse (attack a): SURVIVED-WITH-QUALIFIER — witness targets are
  width-relative (all 5 affine at u1; the flagship pair-emergence witness
  degenerates to the identity map at u2). Statements need explicit width.
- Affine-theorem edges (attack c): W2b alone certifies nothing —
  **4095/4096 basis-passers are non-affine impostors**; the W1 precondition
  is fully load-bearing. Real off-by-one found: the order bound for
  affine-with-offset is **n+1 = 65**, not 64 (Cayley–Hamilton misapplied);
  affects the F00D mul_free champion (only c≠0 case); BRank verdict
  unaffected.
- **G49 instrument cross-audit: PASS 5016/5016 (100%)** — production
  native-prover path (AIG strash → miter → toSat → DPLL) vs a
  zero-shared-code truth-table evaluator, including 1551 adversarial
  single-minterm-flip cases. Unaudited surface listed: `Aig.sweep`,
  `createBvMiter`, 64-bit chains.
- **Follow-up flagged:** the wcore Claim-C reducer has the same
  depth-artifact risk as attack (b) — its "irreducible" verdicts may also be
  resource-bound artifacts. Deserves its own round (and connects to A1–A6's
  5% certifier leak).

---

## Cross-experiment synthesis (updated as results land)

1. **Two confirmations of the Closure Principle's escape corollary** from
   opposite directions: one algebra change collapses a provable readout
   ceiling (A10), while ten certified escapes barely move held-out reach when
   the escape generator is not aimed at the frontier (A1–A6). Escapes are
   cheap; *aimed* escapes are the scarce resource.
2. **The certification stack held up under its own audits**: the LABS verifier
   refuted planted lies; the A1–A6 retro-audit caught a certifier leak at
   deeper budget. This is the axis AlphaEvolve cannot match — keep it.
3. **Significance axis:** LABS establishes the honest baseline and the exact
   distance to published records (even-N move sets; Mertens bounding). The
   addchain v2 result (pending) will add the second external-verification
   domain.
4. **Tier 8 is now evidenced, not just PASSed:** framework revision produced
   solves unreachable by the frozen loop at equal (actually lower) budget,
   3/3 seeds — the repo's first ablation-backed Tier 8 claim. The next
   weakness is precisely characterized: the revised gate must be shown to
   still *discriminate* (post-revision tax is currently vacuous for certified
   escapes). Combined with A1–A6 (escapes must be aimed) and exp 5 (tax gate
   as the aiming mechanism), the Tier 8 loop's missing piece is a gate that
   both admits aimed escapes and keeps blocking remix.
5. **The tax's correct role is resolved by exps 5+6 jointly:** as a hard
   promotion gate it blocks certified escapes (exp 6's ARM-OFF failure mode)
   and starves/slows the loop (exp 5's arm A); as pure measurement it is free
   and loses nothing (exp 5's arm B, 57/57). So: tax = instrument + revision
   trigger + export filter, never an inner-loop block. This settles the
   Phase-1 design question from `tier8_mega_plan.md` with data.
6. **"Outside the closure" claims must now carry (width, depth, registers)
   qualifiers.** Exp 8 broke the emergent-pair block by pushing depth on the
   repo's own substrate — the walls were resource bounds, not algebra. This
   retroactively reframes A1–A6's certifier leak (same failure class: a
   depth-budget verdict presented as an algebraic one) and puts the wcore
   Claim-C reducer next in line for the same attack. The core principle
   itself came out *stronger* (u2 infinite-depth fixpoint proof) — which is
   exactly what a falsification round is for.
7. **CLOSURE_PRINCIPLE.md needs a correction pass:** delete/rewrite the
   emergent-pair block with the resource-bound qualifier, add explicit width
   to every witness, fix the order bound to n+1. (Corrected wording proposed
   in the I53 doc.)

*(Sections for experiments 2 and 7 to be added on completion.)*
