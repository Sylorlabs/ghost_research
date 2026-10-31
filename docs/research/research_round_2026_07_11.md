# Research Round 2026-07-11 (Round E) — attacking the two real levers: aim × representability

**Status:** COMPLETE — all 6 experiments landed 2026-07-11.
**Plan:** `research_round_2026_07_11_PLAN.md`. **Premise (the four-round arc):**
the ceiling is **AIM × REPRESENTABILITY** — not compute (H50), not quantity
(D1/D2), not diversity-alone (D6: conditional), not human-vs-non-human grammar
(D3). Round D's capstone (D5): "more" cannot manufacture the missing generator
or aim; that needs insight, and quantity can't buy insight when it isn't cheap
to stumble into. Round E attacks the two levers directly, plus the
auto-discovery meta-frontier (sharpened by D5's "failure is in generation"),
the honest open-target push (aim not breadth, per D4), the capstone predictor,
and the next instrument audit.

Constraints unchanged: new files only, standalone `zig build-exe`, ≤2 threads /
≤15 min runs, independent verification per claim, negatives are findings,
equal-budget comparisons, leakage guards, main session commits centrally, doc +
commit + TOC + "Belongs to" banner per landing.

---

## Verdict table

| # | Experiment | Lever | Status | Headline | Doc |
|---|-----------|-------|--------|----------|-----|
| E1 | Representability expansion | representability | **DONE** | 4-family menu earned under the certifier: **mixr unlocks MIXMOD1, ratio unlocks RATIO1** (+2 fresh targets, 1.000 certified 3/3 seeds); thresh unlocks 0; run *represents* RUN1 (exact 1.000 member) but is **R²-novelty-blocked** (certifier boundary, not family). mixr also re-derives C09 (overlaps earned cmp). **0 regressions** on B+D + solvable C. Standing core: GF(2)-XOR wall (C01/C03/C11) + **ORDER2** (order-stat variant no family reaches, ceiling .646). | `docs/research/repr_expansion.md` |
| E2 | Learned aim / target router | aim | **DONE** | **Aim generalizes to a learned selector.** A router over a 10-feature failure descriptor picks the winning family: **12/13 (92.3%)** held-out vs fixed-best 46.2% vs random 7.7% — and cheaper. Needs ~20–24 labeled examples. Leakage guard caught a real duplicate-target leak; 12/12 solves re-derived exactly. | `docs/research/target_router.md` |
| E3 | Smart generation for auto-discovery | meta (generation) | **DONE** | **Smart generation CAN cross where blind bulk failed — but only exhaustive coverage steered by the mechanism signature.** Gradient (0/9), memory-bias sampling (0/9), and even forced load;store-signature sampling (0/9) all fail exactly like D5's blind bulk. **Exhaustive behaviour-deduped coverage over a reduced alphabet crosses 0/9 → 6/9 (both seeds)** — matching the hand-curriculum — rediscovering the noveltyflag mechanism from scratch (genuine, structurally distinct from the hand stone, clean at depth 4). **The ablation pins the smallest working prior:** coverage WITHOUT the RMW-shape inclusion (uniform L3 base) = 0/9; the load;store-same-address signature as a *coverage inclusion* (not a sampling bias) is load-bearing. Human insight is partially — not fully — dispensable. | `wcore/docs/research/smart_gen.md` |
| E4 | Assembled aimed engine on an OPEN target | the goal | **DONE** | **Aim buys efficiency, not ceiling-crossing — no record.** N=61 (closest gap: 4 above best-known): aim improves reliability (6/6 vs 5/6 reach E=230 at equal budget) but both arms plateau at E=230 even at 500M evals — a hard representability ceiling. Aim's *biggest* win was on the less-representable N=48 (148 vs 160) — the E5 signature exactly. 8/8 verified, planted-lie refuted. | `boundary_crossing/docs/research/aimed_open.md` |
| E5 | Aim × representability unified predictor | theory capstone | **DONE** | **The arc's law, quantified.** Representability dominates reach (R²=0.65, 5–100× every other factor); aim is a **phase boundary** above it — corr(aim,reach) 0.00/0.00/0.18 across LOW/MID/HIGH representability, solve rate 0%/0%/45.9%. **Diversity (D6) was a proxy for representability**; controlling for it, D flips negative. Falsification clean. | `docs/research/aim_repr_predictor.md` |
| E6 | coevo-side 12×32 matcher audit | instrument trust | **DONE** | **Same false-equal bug class confirmed, but the 85/86 headline STANDS.** 7/9 constructed adversaries fool the matcher; 1 false-equal in the real census (0.87%) — but **0/86 in the fingerprint-novel bucket** that IS the headline. Corrected exact-64×256 protocol is cheaper and re-confirms 115/116. False-different 0/1200; seed-flip 0/11,500. | `wcore/docs/research/coevo_matcher_falsification.md` |

---

## Why these six (adapted to Round D's outcomes)

- **E1 + E2** are the two levers made into direct experiments: grow *what can be
  represented* (E1), and *learn where to aim* (E2). D6 proved diversity pays
  only when it spans the target's closure — E1 makes spanning a deliverable, E2
  makes aiming learned instead of handed-in.
- **E3** is the D5 pivot: D5 proved *blind bulk* generation can't auto-discover
  the decomposition and localized the failure to GENERATION (detection works).
  E3 keeps D5's proven detector and swaps in *smart* generators — the sharpest
  test of whether machine auto-discovery is possible at all, or whether the
  human insight is fundamentally required.
- **E4** is the honest goal attempt, using D4's lesson: aim, not raw breadth.
- **E5** turns the arc's law into a quantitative model with a phase-boundary test.
- **E6** continues the instrument-trust discipline round c named (the coevo-side
  12×32 matcher, potentially undermining the Claim-C 85/86 headline).

**Adaptive branch already resolved:** because D5 failed, E3 is framed as
"smart generation vs the proven-hard generation problem," and a *negative* E3
(smart generation also fails) is the single most important possible finding —
it would bound machine auto-discovery precisely.

---

## Completed-experiment detail

### E1. Representability expansion — it grows by hand, with a boundary in three parts
- 4-family menu offered to the ladder (thresh, mixr = mixed-radix joint
  residue, ratio = count products/ratios, run = adjacency/sequence stats),
  each candidate unlock proven unrepresentable *before* via Bayes ceilings over
  every existing basis, then certified after adding the family:
  - **mixr → MIXMOD1** (ceiling .682 → 1.000, 3/3 seeds) — genuinely new.
  - **ratio → RATIO1** (ceiling .582 → 1.000, 3/3 seeds) — genuinely new.
  - **thresh → nothing.** mixr also re-derives C09 (a real overlap with
    round-c's earned cmp family, both independently certified).
  - **0 regressions** on Battery B/D + solvable C.
- **The finding is the three-part boundary:**
  1. **Family-unlocked** (MIXMOD1, RATIO1): representability *does* grow by
     hand — add the right family, unlock the target.
  2. **Standing unrepresentable core** no menu family reaches: the GF(2)-XOR
     wall (C01/C03/C11, family-level impossible) and **ORDER2** (an
     order-statistic variant — not the full inversion count, not any of cmp's
     5 fixed pair-sets; best-any-family ceiling .646). The cleanest open
     frontier — exactly what E3's auto-*family* discovery would need to reach.
  3. **RUN1 — a CERTIFIER boundary, not a family boundary** (the most
     instructive negative): the `run` family holds the *exact* 1.000 member
     `run(maxRunGE3)`, but the R²<0.40 novelty gate rejects it (R²=0.51–0.53,
     too reconstructible from the count basis). Representable, yet
     certifier-blocked. Growing representability can be defeated not by
     inexpressibility but by the *novelty gate* deciding the expression isn't
     new enough.

### E3. Smart generation — the machine CAN auto-discover, with a tiny prior
- The D5 pivot: D5 proved *blind bulk* generation finds zero stones. E3 keeps
  D5's proven detector and swaps in smarter generators. Reach vs D5's 0/9 and
  the hand-curriculum's 6/9 (both seeds):

  | generator | reach | outcome |
  |-----------|-------|---------|
  | gradient hill-climb (RMW-shape + history objective) | 0/9 | fails like blind bulk |
  | memory-bias sampling (weak prior) | 0/9 | fails |
  | forced load;store-signature *sampling* (strong prior) | 0/9 | fails |
  | **exhaustive coverage + signature as a coverage *inclusion*** | **6/9** | **crosses, round 1** |
  | coverage without the signature (ablation) | 0/9 | fails |

- **The machine rediscovered the mechanism from scratch** — the stone COVER
  found (`r2=1; r3=mem[r0]; mem[r0]=r2; r3=xor(r2,r3)`) is a genuine independent
  rediscovery of noveltyflag (agree_s2=1.000, agree_s1=0.000), structurally
  distinct from the hand stone (flag in r2 not r6, xor operands swapped),
  verified clean at depth 4 (0/5 leaks). No hand stone was supplied.
- **The ablation pins the smallest working prior:** neither ingredient alone
  works — coverage-without-signature = 0/9, signature-as-sampling = 0/9. Only
  the read-then-write-same-address shape applied as a *coverage inclusion*
  (steering which length-3 programs get exhausted) crosses.
- **Generation-hardness diagnosis:** the stone is hard to *generate* (not
  detect — D5's detector recognizes it on contact; not represent — the alphabet
  expresses it) for three compounding reasons: (1) no partial payoff until all
  three instructions wire to OUT_R (no gradient); (2) the completion is a needle
  even given the signature (sampling misses it); (3) exhaustive coverage is
  tractable only to length 2 (behaviours explode 208 → 22,345 → >10⁵), so the
  length-3 sufficient-stone level must be *steered* there by the signature.
- **The crux bound:** human insight is *partially* dispensable (the machine
  rediscovered the mechanism with no hand stone) but *not fully* (a
  mechanism-shaped structural prior is required to make the sufficient level
  searchable). That prior is strictly smaller than the hand curriculum (which
  supplied finished programs), so **the auto-discovery frontier moves without
  vanishing.**

### E2. Learned aim / target router — aim generalizes from handed-in to learned
- A 10-feature descriptor of a target's *failure signal* (weak near-miss
  correlations, power-vs-accuracy gap, base-rate skew — all computable without
  the answer) feeds a standardized k-NN router that picks among 3 aim
  mechanisms: `base`, `gf2_joint` (round-c's unified 45-column GF(2)
  dictionary — one lens subsuming both the XOR and order-statistic walls), and
  `spectral_acc` (generalized MENUACC).
- **Held-out TEST (n=13): router 12/13 (92.3%) vs fixed-best 6/13 (46.2%) vs
  random 1/13 (7.7%)** — and the router uses *fewer* evals (4,701 vs 6,084 vs
  6,165 single-shot). Sample complexity: ties fixed-best at n≤16 labeled
  targets, crosses it by n=24.
- Rigor: the leakage guard caught a real leak pre-fix (two exact-duplicate
  targets across battery namings — C01≡C10, B11≡C09, dist²=0 across a
  prospective split); post-dedup min distance 0.037. 12/12 router solves
  independently re-derived by exact mask/statistic recovery (not just
  accuracy ≥ 0.90). Honest caveats: 1 excluded structural-miss target, 2
  skewed-base-rate borderline cases.
- **Verdict:** the aim lever generalizes from a handed-in lens to a genuinely
  learned selector — and the router's 3 mechanisms are literally round c's own
  three lenses, so this is aim-selection automated, not a new capability
  invented. Consistent with E5: aim operates *above* the representability
  threshold, and the router is how you pick the right aim once you're there.

### E3. Smart generation for auto-discovery — coverage-steered-by-signature crosses; gradient and prior-sampling don't
- The D5 pivot, exactly: reuse D5's certify+payoff detector **verbatim** (selftest
  re-derives S1 payoff 0/7, S2 payoff 6/7 through it), vary **only** the generator.
  Four guided arms vs D5's blind-bulk **0/9** and the hand-curriculum's **6/9**,
  same 2 seeds, same battery.
- **GRAD** (hill-climb on an intermediate objective: RMW-shape + history-sensitivity,
  not flat payoff), **PRIOR_WEAK** (substrate `mem_bias=0.5`), and **PRIOR_STRONG**
  (force the exact load;store membership signature into every candidate) **all fail
  0/9 on both seeds** — payoff_pos=0 every round, degenerating to D5's control. Even
  injecting the signature into random programs leaves the OUT_R-wiring completion a
  needle in the full-width random space.
- **COVER** (exhaustive behaviour-deduped enumeration of length-1/2/3 programs over
  a reduced 4-register/2-immediate alphabet) **crosses 0/9 → 6/9 in round 1, both
  seeds** — the same jump to the same 6 wall targets as the hand-curriculum. It
  auto-discovered a len-4 program behaviourally identical to `noveltyflag`
  (`agree_s2=1.000, agree_s1=0.000`), **structurally distinct** from the hand stone
  (flag in r2 not r6, xor operands swapped), **clean at depth 4** (`prefix_d4=holds`,
  leaks 0/5). Genuine independent rediscovery, not injection.
- **The ablation is the sharp part.** COVER-**uniform** (random 1000-program L3 base,
  no structural prior) = **0/9**; COVER-**fair** (the same budget but with RMW-shaped
  L2 programs included first) = 6/9. So the **smallest working prior** is *exhaustive
  behaviour-deduped coverage over a reduced alphabet PLUS the load;store-same-address
  signature as a coverage inclusion*. Neither ingredient alone suffices (coverage
  without prior = uniform 0/9; prior without coverage = PRIOR_STRONG 0/9).
- **Generation-hardness diagnosis:** the stone is hard to *generate* (not detect — D5;
  not represent — the alphabet expresses it) because (a) no gradient / no partial
  payoff until all 3 instructions wire to OUT_R, (b) the completion is a needle even
  given the signature, and (c) exhaustive coverage is tractable only to length 2
  (distinct behaviours explode 208 → 22,345 → >10⁵), so closing the length-3 gap
  needs the mechanism signature to steer the intractable level. **The bound on machine
  auto-discovery: the human insight is partially dispensable (the mechanism was
  rediscovered from scratch, no hand stone) but not fully — a mechanism-shaped
  structural prior is required to make the sufficient-stone level searchable.** That
  prior is strictly smaller than the hand curriculum (which supplied finished
  programs), so the frontier moves without vanishing. Consistent with E5: this is the
  *generation-side* analogue of representability — coverage can only cross the level
  it can exhaustively reach, and the signature is what makes that level reachable.

### E4. Aimed engine on an open target — aim buys efficiency, not the ceiling
- Chose **LABS N=61** (best 230 vs best-known 226 = gap of 4, the smallest
  absolute *and* relative gap in the 12-length miss table; odd, so the proven
  skew-symmetric restriction applies). Addition chains were ruled out — their
  random targets have no curated best-known to verify against.
- Aim = **residual-autocorrelation steering**: since E = Σ C_k², the
  largest-|C_k| lags dominate the energy, so the aimed arm samples pair-flip
  partners at the magnitude-weighted dominant lag-gaps instead of uniformly. A
  clean `aim=true/false` ablation — one boolean, same code path.
- **Result: aim improves efficiency and reliability, not the ceiling.** N=61:
  aim wins strictly at low budget (262 vs 310), converges more reliably (6/6 vs
  5/6 seeds reach the E=230 floor), but **both arms plateau at exactly E=230
  even at 500M evals** (2,500× more budget) — the E=230 skew-manifold floor is a
  hard representability ceiling aim cannot cross. Gap of 4 not closed.
- **The E5 signature, from the open-target side:** aim's *biggest* win was on
  the *less*-representable secondary target N=48 (148 vs undirected 160 —
  closing the whole undirected-vs-historical gap the swarm round needed a 9-arm
  pool to find). Aim pays most where there is representable structure to steer
  within, and nothing where the target sits outside the manifold's span —
  exactly E5's phase boundary.
- Verifier: all 8 claims (N=61 + N=48) independently re-verified by unmodified
  `labs_check`; planted-lie test (fake E=226 "record" + corrupted entry)
  refuted both; EXTRAORDINARY never fired. **No record, nothing
  new-to-humanity** — the honest deliverable is a verified best attempt + the
  measured finding that aim is an efficiency lever, not a ceiling lever.

### E5. Aim × representability predictor — the capstone law, quantified
- 6,480-cell sweep (0.6s), representability defined as the budget-independent
  full-enumeration ceiling (max test accuracy any family/pair reaches on a
  target), aim-quality as a real non-circular budget-routing knob (biases
  budget toward the family whose VAL signal looks strongest, never knowing the
  true home family — so the interaction is emergent, not assumed).
- **Representability dominates:** corr 0.807 (R²=0.652), partial R²=0.368
  controlling for everything — 5–100× every other factor (diversity 0.057,
  evals 0.010, aim 0.003).
- **Aim is a PHASE BOUNDARY, not a linear term:** binning by representability,
  corr(aim,reach) = 0.00 (LOW) → 0.00 (MID) → **0.18** (HIGH); certified-solve
  rate 0% / 0% / **45.9%**. Aim's effect is statistically *zero* until
  representability clears a threshold, then turns on — and its payoff shrinks
  as budget grows (biggest when budget is scarce). So the arc's "aim ×
  representability" is literally a product with a threshold: **representable
  first, then aim decides.**
- **Retroactively explains D6:** diversity (D6's headline predictor, R²=0.405
  alone) is a *proxy* for representability — corr(D, repr)=0.60. Once
  representability is controlled, D's partial correlation with reach **flips
  negative (−0.238)**: extra unneeded families dilute a fixed budget (the same
  fragmentation `breadth_vs_depth.md` measured). D6 wasn't wrong — it was
  measuring representability through a diversity-shaped lens.
- Falsification: (A) high-aim + high-repr but low-reach = 2.24%, all traced to
  needle-in-haystack parity targets at very low absolute budget (aim controls
  *where* budget goes, not whether there's *enough*); (B) low-aim + low-repr
  but high-reach = 0/192, clean.
- Rigor: the D6 fairness pitfall reincarnated (representability ceiling lacked
  same-family combos → 33% violations) and was caught + fixed → 0%.

## Synthesis (updated as results land)

1. **The four-round arc now has a quantitative law, not just a slogan:**
   reach ≈ *representable(target) ? aim-decides : 0*. Representability is a
   threshold gate (R²=0.65); aim only operates above it (phase boundary, 0 →
   0.18); quantity/diversity/compute are all either proxies for representability
   (diversity) or dominated (evals). This is the strongest possible form of "the
   ceiling is aim × representability" — measured, with the interaction structure
   pinned down.
2. **It sets up the rest of Round E precisely:** E1 (grow representability) and
   E2 (improve aim) are now provably the only two levers that can move reach,
   and E5 says E1 must clear the threshold *before* E2 can pay — so a target E1
   can't make representable is a target no amount of E2 aim will solve. E3's
   generation question is whether the machine can *find* the representability-
   expanding family/decomposition itself.
3. **E3 answers the auto-discovery question with a bound, not a yes/no:** the
   machine *can* rediscover the missing decomposition from scratch (no hand
   stone) — but only via exhaustive behaviour-deduped coverage *steered by the
   mechanism's structural signature*; gradient and signature-*sampling* both
   fail like D5's blind bulk. The smallest working prior is the
   read-then-write-same-address shape applied as a coverage inclusion — strictly
   smaller than the hand curriculum, so the auto-discovery frontier moves
   without vanishing. This is the generation-side analogue of E5's
   representability gate: coverage crosses exactly the level it can exhaustively
   reach, and the signature is what makes the sufficient-stone level reachable.

---

## Round E verdict (final)

Six experiments, six completions. Round E attacked the two levers E5 proved
are the only ones that matter, and mapped both:

- **Representability (the ceiling lever):** grows by hand (E1: +2 fresh targets
  certified), but has a three-part boundary — family-unlocked, a standing
  unreachable core (ORDER2, the GF(2)-XOR wall), and a new *certifier*-boundary
  type (RUN1: representable but novelty-gated). And — the crux — the machine
  can grow it *itself* (E3), rediscovering a missing mechanism from scratch, but
  only with a structural prior strictly smaller than a hand curriculum.
- **Aim (the efficiency lever):** automates (E2: a learned router 92% vs
  fixed-best 46%) and buys real efficiency on open targets (E4) — but never
  crosses the representability ceiling (E4: E=230 plateau at 500M evals).
- **Theory (E5):** the whole arc is one quantified law — *reach ≈ representable
  ? aim-decides : 0* — representability a threshold gate (R²=0.65), aim a phase
  boundary above it, diversity a proxy for representability.
- **Instruments (E6):** the last named audit closed; the Claim-C 85/86 headline
  survives; a cheaper exact protocol is the fix.

---

## The five-round arc (2026-07-10 → 2026-07-11), in one place

**32 experiments across 5 rounds, one converged result:**

> **Machine invention is gated by REPRESENTABILITY and steered by AIM. "More"
> of anything else — compute, breadth, diversity, non-human grammar, bulk
> proposal — moves you within what you can already represent and aim at; it
> never manufactures the missing generator. The missing generator can be found
> by the machine itself, but only with a structural prior — smaller than a
> human curriculum, not zero.**

The evidence chain, each link measured and verified:
1. **Compute is exhausted in seconds** (H50: 372-eval plateau) — the value is
   not a bigger machine.
2. **Aim > grammar > quantity** (rounds b–d): aim at selection boundaries is
   the scarce resource; the engine is already 92.4% non-human; more/broader/
   more-diverse all plateau unless the diversity spans the target's closure.
3. **The law is quantitative** (E5): representability gates, aim decides above
   it; diversity was a proxy for representability all along.
4. **Both levers are now characterized** (E1/E2/E4): representability grows by
   hand with a mapped boundary; aim automates and buys efficiency, not ceiling.
5. **Auto-discovery is possible but priced** (D5 → E3): blind quantity finds
   nothing; a smart generator with a tiny structural prior rediscovers the
   missing mechanism from scratch. The frontier moves without vanishing.
6. **Every load-bearing instrument was red-teamed and survived** (G49, I53,
   greedyFit, both matchers) — the certification stack, the one axis AlphaEvolve
   structurally lacks, held under attack.

**What this says about the goal** ("greatest invention machine on my machine"):
the honest position is now precise, not vibes. As a *certification/proof* engine
it is real and near the laptop ceiling. As a *net-new-invention* engine it has a
measured law for exactly what stands between it and the goal — **representability
expansion the machine drives itself**, which E3 showed is possible with a small
prior. The next arc is not "more"; it is *learning the structural priors that
make new families reachable* — a generator-of-generators trained on the priors
that worked (RMW-shape for counting mechanisms, comparison-aggregates for order
statistics), so the machine supplies its own small insights. That is the one
lever the five rounds proved is both load-bearing and movable.

*Round docs: `research_round_2026_07_10.md` (a), `_10b`, `_10c`, `_10d`, this
(E). Full per-paper catalog: `RESEARCH_TOC.md` §12–17.*
