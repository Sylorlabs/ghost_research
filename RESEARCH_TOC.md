# RESEARCH_TOC — Master Tried → Result → Aftermath Catalog

One entry per research paper in this repository: what was tried, what was measured,
and what the program did with the result. Complements [`INDEX.md`](INDEX.md)
(directory/narrative index) and [`RESEARCH_INDEX.md`](RESEARCH_INDEX.md) (thread
chronology). Every Result sentence quotes the doc's own numbers.

## Legend — aftermath tags

| Tag | Meaning |
|-----|---------|
| **ABANDONED** | Direction dropped; no successor work |
| **MODIFIED** | Approach revised and retried (successor doc linked) |
| **ADOPTED** | Result became standard practice / a reused component |
| **SUPERSEDED** | Later doc replaces this one's role (linked) |
| ⚠️ **REFUTED** | A later doc overturned part or all of this doc's claim (linked) |
| **OPEN** | Still the frontier; no follow-up yet |
| **UNCLEAR** | No downstream reference found; honest "don't know" |

## Reading order — the ~10 load-bearing docs for a new reader

1. [`CLOSURE_PRINCIPLE.md`](CLOSURE_PRINCIPLE.md) — the unifying result (read with its refutation, #2)
2. [`docs/research/i53_falsification_2026_07_10.md`](docs/research/i53_falsification_2026_07_10.md) — the falsification round that broke the pair-refinement claims
3. [`sparse_poly_discovery/docs/research/closure_escape_control.md`](sparse_poly_discovery/docs/research/closure_escape_control.md) — cleanest closure witness + its own self-correction
4. [`wcore/docs/research/alien_novelty_limit.md`](wcore/docs/research/alien_novelty_limit.md) — "a fixed atom set cannot invent," the purist terminal verdict
5. [`05_meta_synthesis/docs/07/affine_closure_tierA_2026_05_28.md`](05_meta_synthesis/docs/07/affine_closure_tierA_2026_05_28.md) — the formal GF(2) affine-closure proof
6. [`sparse_poly_discovery/docs/research/feature_discovery.md`](sparse_poly_discovery/docs/research/feature_discovery.md) — the discovery ladder (selection → construction), each rung self-falsified
7. [`docs/research/tier8_mega_plan.md`](docs/research/tier8_mega_plan.md) — the north star: Tier 8 = invention of the conditions for invention
8. [`docs/research/tier8_swarm_master.md`](docs/research/tier8_swarm_master.md) — the Tier 8 verdict table (read with [`results/NEGATIVE_RESULTS_LEDGER.md`](results/NEGATIVE_RESULTS_LEDGER.md) N3)
9. [`results/NEGATIVE_RESULTS_LEDGER.md`](results/NEGATIVE_RESULTS_LEDGER.md) — the canonical refuted/self-certified claim ledger
10. [`sparse_poly_discovery/docs/research/open_invention_rq9.md`](sparse_poly_discovery/docs/research/open_invention_rq9.md) → [`open_invention_e26.md`](sparse_poly_discovery/docs/research/open_invention_e26.md) — the equivalence tax: most "escapes" are remix (85%)
11. [`RESEARCH_QUESTIONS.md`](RESEARCH_QUESTIONS.md) — the open-question inventory with honesty flags

---

## 1. Top-level program documents & syntheses

### [CLOSURE_PRINCIPLE.md](CLOSURE_PRINCIPLE.md)
- **Tried:** Cross-thread synthesis stating the Closure Principle (closed primitive set ⇒ no escape without an out-of-closure generator) with five measured witnesses: mixers, wcore invention, control, meta-engine search depth, k-sparse parity.
- **Result:** All five witnesses hold as measured — mixer SAC 0.5 → 0.13 (ADD) → 0.02 (MUL); band readout 0.51 (chance) vs mb_mass 11.02; linear parity 0.50 → MLP 1.0; wcore 85/86 reducible at depth 4.
- **Aftermath:** ⚠️ PARTIALLY REFUTED by [docs/research/i53_falsification_2026_07_10.md](docs/research/i53_falsification_2026_07_10.md) — both "emergent pair" claims broken at depth 6–8 / 3–5 registers, and the principle needs domain-width + resource-bound qualifiers; the core ceiling theorem SURVIVED every attack; a 2026-07-10 correction pass from I53 rewrote the emergent-pair block as budget-relative, so the current text incorporates the fix.

### [RESEARCH_QUESTIONS.md](RESEARCH_QUESTIONS.md)
- **Tried:** Inventory of 60 research questions (sections A–J) each flagged by honesty class (🟢 genuinely unknown / 🟡 quantifies known / 🔴 confirms known).
- **Result:** Steering document, not an experiment — tracks answers inline (A10 ✅ "leave GF(2)" is the lever; #53 ✅ XOR ceiling is information destruction; #46 ✅ threshold audit clean).
- **Aftermath:** ADOPTED as the program's steering document; its I53/G48/G49/H50 rows were executed in the 2026-07-05 swarm and 2026-07-10 falsification rounds.

### [RESEARCH_SUMMARY.md](RESEARCH_SUMMARY.md)
- **Tried:** Early "BitForge" synthesis covering a 128-bit multi-word ARX PRNG, a topological execution tracer, the native AIG prover, and an automated CEGIS invention claim.
- **Result:** Claims as stated: 24-instruction ARX passing 256MB PractRand; structural search "1,000,000× faster"; AIG collapse 513→1 node; and "in 3 generations the engine independently rediscovered x & (x-1)" via CEGIS.
- **Aftermath:** ⚠️ PARTIALLY REFUTED — the CEGIS x&(x-1) claim is N1 in [results/NEGATIVE_RESULTS_LEDGER.md](results/NEGATIVE_RESULTS_LEDGER.md) (real rediscovery is exhaustive search in `boundary_crossing/superopt.zig`, not CEGIS, not 3 gens); the PRNG/tracer/AIG claims have no downstream refutation or confirmation found.

### [STRATEGIC_PLAN.md](STRATEGIC_PLAN.md)
- **Tried:** Forward roadmap proposing four challenges: SIMD vector-register synthesis, breaking the GF(2) affine trap, SAC-in-Z3 S-box synthesis, and compiler-defiance superoptimization.
- **Result:** No measured outcome — purely Goal/Approach/Edge statements, no run data.
- **Aftermath:** UNCLEAR — never cited as origin by later docs, though challenge #2 overlaps the later `closure_escape_mixer` work and #4 overlaps swarm EXP-19 (beat gcc); unconfirmed overlap, not a proven link.

### [RESEARCH_ROUND_2026_06_03.md](RESEARCH_ROUND_2026_06_03.md)
- **Tried:** Four-direction round off the Closure Principle: (A) Clifford vs real-Hadamard vs XOR binding, (B) open-atom-set promotion transcendence, (C) gradient-learned parameter ω vs grid search, (D) falsification hunt against the XOR ceiling.
- **Result:** A: XOR 0.503 → Hadamard-R 0.974 / Clifford 0.967 (algebra matters, Clifford specifically doesn't); B: promotion "RELOCATES claim C, doesn't escape it"; C: grid 1.000 vs gradient 0/40 >0.95 (vanishing gradient at ω=π); D: "PRINCIPLE SURVIVES — STRENGTHENED" (MLP at 0.505 chance vs 0.998 on raw cells).
- **Aftermath:** ADOPTED — all four verdicts absorbed into RESEARCH_QUESTIONS.md status flags and re-verified by the 2026-07-05 swarm (EXP-16 CE-1).

### [docs/research/ghost_mega_plan_v3_the_fix.md](docs/research/ghost_mega_plan_v3_the_fix.md)
- **Tried:** Proposed a four-track fix plan (subword N-gram OOV encoding, permutation syntax encoding, dynamic context binding, Pareto multi-objective search) for four named flaws in the conceptless-VSA lineage.
- **Result:** No measured outcome — pre-implementation plan with only "Expected Outcome" statements.
- **Aftermath:** UNCLEAR — no downstream reference found; no evidence any track was run.

### [results/NEGATIVE_RESULTS_LEDGER.md](results/NEGATIVE_RESULTS_LEDGER.md)
- **Tried:** Audit converting unsafe claims into documented negative results: N1 (CEGIS x&(x-1) attribution), N2 (`verify_cli.zig` mixer-CSV column bug), N3 (Tier-8 hardcoded "witnessed survivor" whitelist), N4 ("discovered" escape generators actually human-supplied).
- **Result:** N1 REFUTED/UNSUBSTANTIATED; N2 PARTIAL — the parser drops `imm_hex`, so any mixer "VERIFIED" verdict from that CSV path is on a program the engine never produced; N3 SELF-CERTIFIED-ONLY — `tier8_loop.zig` prints "witnessed survivor" and `phase6 = true` unconditionally; N4 REFUTED-AS-DISCOVERED — engines search within human-authored families.
- **Aftermath:** ADOPTED as the canonical negatives ledger; carried forward by [results/addchain_campaign_2026_07_07.md](results/addchain_campaign_2026_07_07.md) and cited by the addchain campaign as proof of its own independence.

---

## 2. Threads 01–04 — baseline engines, heuristic search, conceptless synthesis, verified synthesis

### [01_baseline_engines/docs/flare_vs_flame_vs_vsa_analysis.md](01_baseline_engines/docs/flare_vs_flame_vs_vsa_analysis.md)
- **Tried:** Benchmarked ghost_flare (twin-flare paired-residual) vs ghost_flame and the static VSA baseline on a 12-case suite plus a 1000-sample survival probe.
- **Result:** Flare dominates trial-win reliability (typo-intent: 67 vs 4 wins) with 8 baseline survivors at 100% structural validity; Flame keeps higher peak quality (3,019,159 vs 2,156,689).
- **Aftermath:** MODIFIED — its "combine Flame's peak with Flare's stability" next step became Frost ([frost_5x_innovation_analysis.md](01_baseline_engines/docs/frost_5x_innovation_analysis.md)).

### [01_baseline_engines/docs/frost_5x_innovation_analysis.md](01_baseline_engines/docs/frost_5x_innovation_analysis.md)
- **Tried:** Evaluated ghost_frost ("invented by predecessor ghost_flare") against the mandate to beat the best prior engine ≥5× on the Transformer-Killer prompt.
- **Result:** PASS — closure_delta 12,573,997,689 vs Flame's 4,579,574 (>2,700×).
- **Aftermath:** MODIFIED — its apex candidate became ghost_fractal ([fractal_penta_analysis.md](01_baseline_engines/docs/fractal_penta_analysis.md)); per CLAUDE.md the benchmark chain is real, the "invented by its predecessor" narrative framing is not engine output.

### [01_baseline_engines/docs/frost_transformer_killer_invention.md](01_baseline_engines/docs/frost_transformer_killer_invention.md)
- **Tried:** Narrative "translation" of Frost's apex candidate (mark/scar hex values) into a "wave-state inference engine" architecture description.
- **Result:** Repeats the same closure_delta -12,573,997,689; claims to go "beyond vectors."
- **Aftermath:** ⚠️ The interpretive prose is the agent-authored "alien math" framing CLAUDE.md explicitly disavows; only the delta number is real — SUPERSEDED by the fractal benchmark doc.

### [01_baseline_engines/docs/fractal_penta_analysis.md](01_baseline_engines/docs/fractal_penta_analysis.md)
- **Tried:** Benchmarked ghost_fractal (holographic-cascade engine) against VSA/Flame/Flare/Frost in a 5-way benchmark plus Transformer-Killer.
- **Result:** 1000/1000 baseline survival; Transformer-Killer delta 52,330,096,926 — 11,426× over Flame, 4.2× over Frost.
- **Aftermath:** SUPERSEDED by ghost_flux ([flux_hexa_analysis.md](01_baseline_engines/docs/flux_hexa_analysis.md)).

### [01_baseline_engines/docs/flux_hexa_analysis.md](01_baseline_engines/docs/flux_hexa_analysis.md)
- **Tried:** Benchmarked ghost_flux ("synthesized by ghost_fractal") against all 5 prior engines on the Hexa benchmark and Transformer-Killer.
- **Result:** 256/256 trial wins in every weird domain; delta 2,879,761,615,922 — claimed 628,827× over legacy VSA/Flame, 55× over Fractal.
- **Aftermath:** ADOPTED as the end of the verified benchmark chain (CLAUDE.md: "VSA → Flame → Flare → Frost → Fractal → Flux → Void is real and verified"); superseded architecturally by void.zig.

### [01_baseline_engines/docs/flux_transformer_killer_invention.md](01_baseline_engines/docs/flux_transformer_killer_invention.md)
- **Tried:** Narrative translation of Flux's apex candidate into a "Ghost Singularity" phase-field-collapse architecture.
- **Result:** Same delta -2,879,761,615,922 as the hexa benchmark; claims token-free "structural physics" understanding.
- **Aftermath:** ⚠️ Agent-authored theatrical framing per CLAUDE.md's "Alien Math" warning — the number is real, the interpretation is not; no successor continues the narrative style.

### [01_baseline_engines/docs/trained_semantic_bench.md](01_baseline_engines/docs/trained_semantic_bench.md)
- **Tried:** Replaced random per-word VSA hypervectors with co-occurrence-trained Random Indexing vectors and re-ran the related-vs-orthographic Hamming benchmark.
- **Result:** Cohen's d moved from raw-byte +1.92 (spelling bias) and random-HV +0.31 to trained-HV **-0.41** (p=0.0028) on natural English; the curated-pairs -13.22 flagged as corpus-biased.
- **Aftermath:** OPEN — the "wire trained HVs into ingestSemantic" path was never taken; distinct from (and not refuted by) the 2026-05-17 PRNG-swap control, which refuted popcount-grounding of Flame's laws, not this distributional result.

### [02_heuristic_search/docs/novelty_invention_engine.md](02_heuristic_search/docs/novelty_invention_engine.md)
- **Tried:** Novelty-pressure probe maximizing minimum Hamming distance from all 20 VSA concept hypervectors while running Flame law repair.
- **Result:** prototype_lock profile: 24/24 trials past the VSA envelope (max 290), best min distance 293, best closure ~20,448,584.
- **Aftermath:** SUPERSEDED by [engine_genesis.md](02_heuristic_search/docs/engine_genesis.md) (closure 14,829,513).

### [02_heuristic_search/docs/engine_genesis.md](02_heuristic_search/docs/engine_genesis.md)
- **Tried:** Geometry-to-Zig compiler deriving a genome from outside-envelope chamber geometry, evolving it, and emitting a standalone Zig invention engine.
- **Result:** Generated engine: 16/16 trials past the envelope, best closure 14,829,513 (beats prototype_lock's ~20.4M).
- **Aftermath:** SUPERSEDED by [phase_lattice_inventor.md](02_heuristic_search/docs/phase_lattice_inventor.md); the whole geometry-search thread later ABANDONED per INDEX.md ("geometric descriptors insufficient for verifiable code generation").

### [02_heuristic_search/docs/phase_lattice_inventor.md](02_heuristic_search/docs/phase_lattice_inventor.md)
- **Tried:** Phase-locked geometry invention engine spawning 5 phase views repaired against Flame laws.
- **Result:** 16/16 past envelope, best closure 14,795,384 — but "the selector always chose the root phase," so the extra views were never shown useful.
- **Aftermath:** SUPERSEDED by [alien_breakthrough_inventor.md](02_heuristic_search/docs/alien_breakthrough_inventor.md).

### [02_heuristic_search/docs/alien_breakthrough_inventor.md](02_heuristic_search/docs/alien_breakthrough_inventor.md)
- **Tried:** engine_genesis search for a stronger outside-VSA-envelope engine, independently re-run at 32 trials.
- **Result:** 32/32 past the envelope, best closure 14,486,650 — self-assessed "a stronger local invention engine, not the extraordinary breakthrough yet."
- **Aftermath:** ABANDONED with the thread — its geometry constants seeded the conceptless chain ([synthesized_conceptless_breakthrough.md](03_standard_synthesis/docs/synthesized_conceptless_breakthrough.md)).

### [02_heuristic_search/docs/invention_mega_plan_results.md](02_heuristic_search/docs/invention_mega_plan_results.md)
- **Tried:** Six tracks: PractRand mixer validation, program-synthesis self-bootstrap, conceptless Gen3, VSA log-scaling, a semantic-HV bridge, and placeholder-CLI cleanup.
- **Result:** PractRand tied splitMix64; bootstrap Gen1 beat parent (47.97 vs 47.30) but Gen2 stalled; Gen3 FAILED (0/8 past parent); log-scaling self-reverted; semantic ingest cohens_d=0.3109, "semantic_wins=no."
- **Aftermath:** MIXED — Gen3 and log-scaling ABANDONED in-doc; the semantic track MODIFIED into [trained_semantic_bench.md](01_baseline_engines/docs/trained_semantic_bench.md) (sign flipped to -0.41); CLI cleanup ADOPTED.

### [02_heuristic_search/docs/alien_invention_experiments_2026_05_22.md](02_heuristic_search/docs/alien_invention_experiments_2026_05_22.md)
- **Tried:** Three flag-only Engine-3 experiments: anti-human-penalty, compressor-mode, live-macro-graduation, vs the 47.2299 baseline.
- **Result:** Anti-human degraded to 38.79 (no structural avoidance achieved); compressor-mode flat at 417.9718 (locked to mixer space); live-macro-graduation crossed to **47.3244** (+0.0945, 3 seeds, NON_COPY_STRUCTURAL).
- **Aftermath:** ABANDONED (first two) / ADOPTED (LMG — reproduced in [engine3_seed_repro_exp4_2026_05_23.md](05_meta_synthesis/docs/06/engine3_seed_repro_exp4_2026_05_23.md)).

### [02_heuristic_search/docs/search_strategy_meta.md](02_heuristic_search/docs/search_strategy_meta.md)
- **Tried:** Made the search-strategy tuple itself a DomainSpec program and meta-searched it over a held-out 24-case battery (after discarding an invalid train=test version).
- **Result:** Smoke-budget champion improved val 4/8→6/8 and test 5/8→6/8, but the test bootstrap CI [-0.25, 0.625] crosses zero — `claim_status=unresolved`; a 4-gen recursive loop rejected every promotion.
- **Aftermath:** OPEN — explicitly unresolved, cross-referenced as such by [04_verified_synthesis/docs/domain_spec.md](04_verified_synthesis/docs/domain_spec.md).

### [03_standard_synthesis/docs/conceptless_inventor.md](03_standard_synthesis/docs/conceptless_inventor.md)
- **Tried:** VSA-free/Flame-free invention probe (std-only) synthesizing an anti-reference field beyond a splitMix64 self-reference orbit.
- **Result:** 24/24 trials passed target; best min reference distance 290, clearance +2.
- **Aftermath:** SUPERSEDED by [synthesized_conceptless_breakthrough.md](03_standard_synthesis/docs/synthesized_conceptless_breakthrough.md) (clearance +8).

### [03_standard_synthesis/docs/synthesized_conceptless_breakthrough.md](03_standard_synthesis/docs/synthesized_conceptless_breakthrough.md)
- **Tried:** New VSA-free engine seeded from alien_breakthrough_inventor's geometry constants, with its own private reference orbit.
- **Result:** 24/24 past target, best min distance 291, clearance +8 (vs +2 for conceptless_inventor).
- **Aftermath:** SUPERSEDED by its own child [recursive_conceptless_inventor.md](03_standard_synthesis/docs/recursive_conceptless_inventor.md) (clearance +11).

### [03_standard_synthesis/docs/recursive_conceptless_inventor.md](03_standard_synthesis/docs/recursive_conceptless_inventor.md)
- **Tried:** Child engine replacing the parent's search with a moving maximin distance-frontier push against the inherited 24 reference fields.
- **Result:** 24/24 beat the parent's target; best min distance 294, clearance +11; sweeps to 2048 steps still topped at 294.
- **Aftermath:** SUPERSEDED by [recursive_conceptless_inventor_v2.md](03_standard_synthesis/docs/recursive_conceptless_inventor_v2.md), which explains the 294 ceiling as single-bit saturation.

### [03_standard_synthesis/docs/recursive_conceptless_inventor_v2.md](03_standard_synthesis/docs/recursive_conceptless_inventor_v2.md)
- **Tried:** Gen2: exhaustive pair-flip search + Metropolis kicks atop Gen1's greedy search.
- **Result:** 12/12 then 16/16 past parent, best_min_ref 296 (clearance +13) — its honest ceiling (reached in ~3/16 trials).
- **Aftermath:** ⚠️ Its proposed Gen3 (triple-flip) FAILED (0/8 past parent, capped at 295 vs a 297 target) per [invention_mega_plan_results.md](02_heuristic_search/docs/invention_mega_plan_results.md); 296 stands as the chain's unbeaten end and the thread closed into the DomainSpec line.

### [04_verified_synthesis/docs/program_synthesis_inventor.md](04_verified_synthesis/docs/program_synthesis_inventor.md)
- **Tried:** SA search over short u64-mixing programs (10-op ISA) vs splitMix64 on a composite fitness, plus a self-bootstrap attempt using its own mixer as search RNG.
- **Result:** Two runs beat splitMix64 (47.19, 47.30 vs 46.20, distinct 5-instruction programs); PractRand 1 GiB tied; bootstrap Gen1 47.97 but Gen2 stalled at 47.86–47.93 (no CEGIS or x&(x-1) claim anywhere in this doc — checked).
- **Aftermath:** ADOPTED — graded INVENTION (strict) by [reachability_tester.md](04_verified_synthesis/docs/reachability_tester.md); the bootstrap track a documented partial failure.

### [04_verified_synthesis/docs/reachability_tester.md](04_verified_synthesis/docs/reachability_tester.md)
- **Tried:** Verdict-ladder tester (edit distance + bit-agreement + compositional reachability to depth 5) grading the discovered mixer against a 4-mixer canonical library.
- **Result:** Champion classified **INVENTION (strict)** (edit distance 5, bit-agreement 0.501 ≈ library peer distance); N=20 batch 20/20 strict verdicts.
- **Aftermath:** ADOPTED — "first artifact to pass an operational, falsifiable invention test"; extended to a second domain in [sorting_invention.md](04_verified_synthesis/docs/sorting_invention.md).

### [04_verified_synthesis/docs/sorting_invention.md](04_verified_synthesis/docs/sorting_invention.md)
- **Tried:** Reachability methodology on N=8 sorting networks vs a Floyd-8/Batcher-8 library, 20 seeds.
- **Result:** 20/20 INVENTION (strict) (correct 20–25-comparator sorters, unreachable at depth ≤3); a broken Bitonic-8 library entry (0.20 correctness) caught and replaced.
- **Aftermath:** ADOPTED — the two-domain evidence became the basis for the DomainSpec refactor ([domain_spec.md](04_verified_synthesis/docs/domain_spec.md)).

### [04_verified_synthesis/docs/domain_spec.md](04_verified_synthesis/docs/domain_spec.md)
- **Tried:** Comptime-generic DomainSpec engine with a fixed interface contract, validated across u64_mixer, sort_net, and boolean domains.
- **Result:** All three domains produced INVENTION (strict) on the same binary; boolean discovered a PARITY-4 XOR chain structurally distinct from the 3 canonical forms.
- **Aftermath:** ADOPTED as the architecture underlying all later synthesis work; the self-application question deferred to the still-OPEN [search_strategy_meta.md](02_heuristic_search/docs/search_strategy_meta.md).

### [04_verified_synthesis/docs/verify_cli.md](04_verified_synthesis/docs/verify_cli.md)
- **Tried:** Real-Z3-backed verifier for discovered champions (sort_net via 0/1 principle, mixer via bijectivity), replacing a hardcoded "SMT_VERIFIED" string.
- **Result:** Sort champions VERIFIED; the mixer gen_0 champion returned **COUNTER-EXAMPLE** at 8/16-bit widths, with gens 1–3 silently masked by a CALL_LIB-identity default — "bijectivity is not a chain invariant."
- **Aftermath:** ADOPTED (real verification wired in), REFUTING the hardcoded verified-truth string; ⚠️ N2 in [results/NEGATIVE_RESULTS_LEDGER.md](results/NEGATIVE_RESULTS_LEDGER.md) later found its mixer-CSV parser corrupts `imm` (consumes `used_len`), so mixer-path verdicts from inventor CSVs are untrustworthy until fixed.

### [function_hardness/docs/hardness_landscape.md](function_hardness/docs/hardness_landscape.md)
- **Tried:** Exhaustively tested all 65,536 4-input Boolean predicates against four linear-readout substrates plus n=5/n=6 sampling, testing four hypotheses.
- **Result:** deg1 closure exactly matches Muroga's linear-threshold count (1,882/65,536); H1 confirmed, H3 necessity REFUTED (99.7% of deg2's closure are "bonus" predicates); Q38 emergent escape confirmed at 228 predicates; deg3's n=5 "99.23%" coverage falsified at n=6 (72.84%).
- **Aftermath:** ADOPTED — the hardness landscape feeds the Tier-8 battery-C generator and the hardness router; five listed open questions remain OPEN.

---

## 3. 05_meta_synthesis — the meta-engine ladder (Tier 0 → Engine 4) and the affine-closure proof

### [05_meta_synthesis/docs/05/meta_engine.md](05_meta_synthesis/docs/05/meta_engine.md)
- **Tried:** Built Tier-0 "engine-inventing-engine": a MetaProgram (opcodes over engine primitives) itself searched by an outer SA to discover a u64-mixer search algorithm, iterated v1–v5 plus a sort_net cross-domain test.
- **Result:** v1 held-out 25.01 (overfit); v2 seed-rotation 33.12 and 3/4 seeds at held-out 44+; v5 at inner_steps=1000 hit 46.81; the sort_net "+5.54 win" self-corrected to "median 161.40, slightly below hill-climb 166.05."
- **Aftermath:** MODIFIED — v2's seed rotation became the disciplined baseline built on by [tier1_meta_engine.md](05_meta_synthesis/docs/05/tier1_meta_engine.md).

### [05_meta_synthesis/docs/05/invention_chain.md](05_meta_synthesis/docs/05/invention_chain.md)
- **Tried:** Chain runner where each generation extends the operator library with prior champions (v1 gate-only, v2 + CALL_LIB, v3 ported to sort_net N=8).
- **Result:** v1's "3 generations of ADVANCE" self-falsified against the measured seed-noise floor (σ=0.3567 — "a noise ratchet, not an invention chain"); v2 CALL_LIB genuinely selected but plateaus ~47.9; v3 sort_net FAILED 6/6 (macro composition sums depth).
- **Aftermath:** ⚠️ Self-REFUTED (v1 claim) then MODIFIED — the additive-cost diagnosis produced the `.logical` depth fix in [successor_chain_sort.md](05_meta_synthesis/docs/05/successor_chain_sort.md).

### [05_meta_synthesis/docs/05/tier1_meta_engine.md](05_meta_synthesis/docs/05/tier1_meta_engine.md)
- **Tried:** Tier-1 (MMP searching for a Tier-0 search algorithm) with a disciplined baseline, then CALL_META composition and wide 4-bit addressing.
- **Result:** Initial pilot HALT (-6.52 vs baseline 32.55); with CALL_META, 3/4 seeds STRICT_DOMINATION, seed 0x1111 holdout **44.30** (64-seed mean 37.68 vs 28.13, wins 37/64); 200-iter budget REFUTED (all seeds worse).
- **Aftermath:** ADOPTED as the Tier-1 reference; its 44.30 ceiling broken later by [monotone_parallel.md](05_meta_synthesis/docs/05/monotone_parallel.md) (47.16) and [recursive_engine_phase_abc_2026_05_21.md](05_meta_synthesis/docs/05/recursive_engine_phase_abc_2026_05_21.md) (47.49).

### [05_meta_synthesis/docs/05/tier2_meta_meta_engine.md](05_meta_synthesis/docs/05/tier2_meta_meta_engine.md)
- **Tried:** Tier-2 (MMMP searching for a Tier-1 search algorithm), pilots at tier2_iters=8 and 24.
- **Result:** Pilot 1 pinned at sentinel -1,000,000; Pilot 2 STRICT_DOMINATION at gen 2 with holdout **-10,812.81** — real learning, 5 orders of magnitude below Tier-1's 44.30.
- **Aftermath:** MODIFIED — shaped fitness/curriculum/constrained-init built in [invention_engine_v2.md](05_meta_synthesis/docs/05/invention_engine_v2.md), raising Tier-2 to +23.30 (still not competitive).

### [05_meta_synthesis/docs/05/successor_loop_research.md](05_meta_synthesis/docs/05/successor_loop_research.md)
- **Tried:** Three parallel tests after the 44.30 plateau: 200-iter budget, wide CALL_META, Tier-2 pilots.
- **Result:** Budget **REFUTED** (all 4 seeds worse, 0x1111 10.93→-35.35); wide CONFIRMED (3/3 seeds, ceiling 44.81); Tier-2 -10,813 ("architectural noise floor").
- **Aftermath:** ADOPTED (wide CALL_META) / ABANDONED (bigger budget) / Tier-2 continued in [invention_engine_v2.md](05_meta_synthesis/docs/05/invention_engine_v2.md).

### [05_meta_synthesis/docs/05/successor_chain_sort.md](05_meta_synthesis/docs/05/successor_chain_sort.md)
- **Tried:** `.logical` depth mode fixing the additive-cost failure, sort_net N=8 chain, 5 seeds × 6 gens, Z3-verifying every champion.
- **Result:** "First reproduced engine-invents-its-successor result" — 5/5 seeds STRICT_DOMINATION (depth 11→6), all champions Z3-verified, hitting the Bose-Nelson depth-6 SOTA floor.
- **Aftermath:** ADOPTED — cited as "where the successor question WAS answered yes."

### [05_meta_synthesis/docs/05/invention_engine_v2.md](05_meta_synthesis/docs/05/invention_engine_v2.md)
- **Tried:** Five approaches against the 44.30 ceiling: expanded Tier-0 opcodes (10→14), expanded-opcode chains, Tier-2 curriculum, shaped fitness, combined Tier-2.
- **Result:** None of 4 expanded chains broke 44.30 (best 37.26); combined Tier-2 hit **+23.30** (first positive Tier-2 holdout) but still ~21 below Tier-1 — "more tiers do NOT compound."
- **Aftermath:** SUPERSEDED — the ceiling fell to monotone-retry+parallel in [monotone_parallel.md](05_meta_synthesis/docs/05/monotone_parallel.md).

### [05_meta_synthesis/docs/05/monotone_parallel.md](05_meta_synthesis/docs/05/monotone_parallel.md)
- **Tried:** `--monotone-retries=N` (ADVANCE only on strict cumulative-best improvement) plus N parallel attempts; parallel-broad vs sequential-deep strategies.
- **Result:** Ceiling broken twice — 0x1111 parallel 45.13; 0xF00D sequential **47.16** at gen 4 via CALL_META compounding ("new high water mark").
- **Aftermath:** ADOPTED (recommended default per CLAUDE.md) and the Phase-A baseline for [recursive_engine_phase_abc_2026_05_21.md](05_meta_synthesis/docs/05/recursive_engine_phase_abc_2026_05_21.md).

### [05_meta_synthesis/docs/05/recursive_engine_phase_abc_2026_05_21.md](05_meta_synthesis/docs/05/recursive_engine_phase_abc_2026_05_21.md)
- **Tried:** Phase A stacked all Engine-2 tricks vs 47.1615; Phase B built Engine-3 (MMMP-driven Tier-1 search) + constrained-init + QD; Phase C built Engine-4 (MMMMP).
- **Result:** Phase A PLATEAU/near-copy at 47.1615; Engine-3 constrained+QD gave the **first fair-budget Engine-3 > Engine-2 crossing at 47.2299** (64-seed confirm), scaling to **47.4867**; Engine-4 best 38.4430 "implemented but not competitive."
- **Aftermath:** ADOPTED (Engine-3 crossing) / OPEN (Engine-4); the repair-ordering side-experiment REFUTED at this budget (19.07).

### [05_meta_synthesis/docs/05/mul_free_challenge.md](05_meta_synthesis/docs/05/mul_free_challenge.md)
- **Tried:** MUL-free mixer challenge protocol (mul_free/no_carry/unrestricted, PractRand ladder, Z3 bijection gate), 3 seeds × 3 modes.
- **Result:** Confirming negative — 0/3 mul_free and 0/3 no_carry passed PractRand 1M; unrestricted passed 64M on 2/3 roots but both Z3-rejected as non-bijective.
- **Aftermath:** SUPERSEDED by [mul_free_challenge_full_run_2026_05_23.md](05_meta_synthesis/docs/06/mul_free_challenge_full_run_2026_05_23.md) and explained by the affine-closure proof.

### [05_meta_synthesis/docs/05/bittape_inventor_2026_05_22.md](05_meta_synthesis/docs/05/bittape_inventor_2026_05_22.md)
- **Tried:** Minimal Boolean substrate (XOR/AND/NOT only), pure GA for 10,000 generations, hunting a verifiably non-remix "alien" mixer.
- **Result:** Converged (382-instruction non-remix program) but metric-gamed: min per-bit flip fraction 0.166, catastrophic PractRand failure at 32 MiB.
- **Aftermath:** MODIFIED — its proposed per-bit fitness fix implemented in [bittape_fitness_fix_2026_05_23.md](05_meta_synthesis/docs/06/bittape_fitness_fix_2026_05_23.md).

### [05_meta_synthesis/docs/06/mega_research_round_checkpoint_2026_05_23.md](05_meta_synthesis/docs/06/mega_research_round_checkpoint_2026_05_23.md)
- **Tried:** Checkpoint/index of nine parallel experiments (Exp1–Exp9) on MUL-necessity, fitness axes, cross-domain generality, and new domains.
- **Result:** Verdict roll-up: per-bit fix necessary-not-sufficient; MUL-necessity holds at meta-engine tier; LMG inert on linear opsets; 45.83 dominant attractor; length escape ≠ quality; 3-tier sort weaker than 2-tier; first Z3-bijective mixer; dual-output 2/6 pass; opset discovery null.
- **Aftermath:** ADOPTED as the round's READ-FIRST index.

### [05_meta_synthesis/docs/06/bittape_fitness_fix_2026_05_23.md](05_meta_synthesis/docs/06/bittape_fitness_fix_2026_05_23.md)
- **Tried:** Per-output-bit avalanche objective replacing the gameable aggregate, 3 seeds × 10,000 gens, independently verified.
- **Result:** Imbalance eliminated (0.166→0.500 min flip frac on 2/3 seeds) but all champions still fail PractRand at 16 MiB with BRank — "the signature of GF(2) linear structure."
- **Aftermath:** MODIFIED — necessary-not-sufficient; resolved formally by [affine_closure_tierA_2026_05_28.md](05_meta_synthesis/docs/07/affine_closure_tierA_2026_05_28.md).

### [05_meta_synthesis/docs/06/meta_engine_mulfree_exp2_2026_05_23.md](05_meta_synthesis/docs/06/meta_engine_mulfree_exp2_2026_05_23.md)
- **Tried:** The 3-tier meta-engine applied to the MUL-free domain, cross-verified via two byte-identical implementations.
- **Result:** Reached PractRand 16 MiB (16× over flat SA) but all champions FAIL BRank and are Z3-non-bijective; two seeds converged to an identical -215.2252 attractor.
- **Aftermath:** MODIFIED — followed by [exp3 LMG](05_meta_synthesis/docs/06/meta_engine_mulfree_lmg_exp3_2026_05_23.md) and [exp5 length-24](05_meta_synthesis/docs/06/mulfree_l24_exp5_2026_05_23.md).

### [05_meta_synthesis/docs/06/meta_engine_mulfree_lmg_exp3_2026_05_23.md](05_meta_synthesis/docs/06/meta_engine_mulfree_lmg_exp3_2026_05_23.md)
- **Tried:** Added live-macro-graduation (the unrestricted-domain ceiling-breaker) to the MUL-free meta-engine.
- **Result:** **Zero effect** — byte-identical holdouts to Exp2 (delta=0 on all 3 seeds); composition of GF(2)-linear functions stays GF(2)-linear.
- **Aftermath:** ABANDONED (this lever in this domain); the explanation later proven in the affine-closure theorem.

### [05_meta_synthesis/docs/06/engine3_seed_repro_exp4_2026_05_23.md](05_meta_synthesis/docs/06/engine3_seed_repro_exp4_2026_05_23.md)
- **Tried:** Engine-3 LMG recipe re-run on 3 fresh seeds to test whether 47.3244 is reproducible.
- **Result:** Seed DEAD reproduced 47.3244 exactly; 1111/ABCD both converged to an identical lower attractor **45.8290** (byte-identical champions), PractRand-16MiB PASS.
- **Aftermath:** ADOPTED — "45.83 is the dominant global attractor."

### [05_meta_synthesis/docs/06/mulfree_l24_exp5_2026_05_23.md](05_meta_synthesis/docs/06/mulfree_l24_exp5_2026_05_23.md)
- **Tried:** Doubled the MUL-free length cap (12→24) to test whether the -215 floor is a cap artifact.
- **Result:** 2/3 seeds escaped (-163.47, -162.11 — cap artifact confirmed) but both still fail PractRand — "a fitness-metric escape, not a quality escape."
- **Aftermath:** ADOPTED as one of the "7 independent conditions" for MUL-necessity.

### [05_meta_synthesis/docs/06/sort_net_3tier_meta_exp6_2026_05_23.md](05_meta_synthesis/docs/06/sort_net_3tier_meta_exp6_2026_05_23.md)
- **Tried:** 3-tier MMMP meta-engine for sort_net N=8 vs the 2-tier successor chain.
- **Result:** Only 1/3 seeds found a valid MMMP (holdout 134.62 ≈ 75% sort-correctness, no perfect sorter); 2/3 stuck at sentinel — weaker than the 2-tier chain.
- **Aftermath:** ABANDONED in current form — LMG/constrained-init never wired to sort adapters; no rerun found.

### [05_meta_synthesis/docs/06/sac_fitness_exp7_2026_05_23.md](05_meta_synthesis/docs/06/sac_fitness_exp7_2026_05_23.md)
- **Tried:** SAC fitness substituted for composite fitness in the mixer meta-engine, 3 seeds.
- **Result:** First Z3-verified **bijective** mixer (seed DEAD) — but it fails PractRand BRank, while two non-bijective champions pass: bijectivity and PractRand-safety are distinct axes.
- **Aftermath:** OPEN — SAC + explicit-nonlinearity combination proposed, never run.

### [05_meta_synthesis/docs/06/dual_output_exp8_2026_05_23.md](05_meta_synthesis/docs/06/dual_output_exp8_2026_05_23.md)
- **Tried:** Dual-output domain (jointly discover two mixers with an independence penalty), 3 seeds plus an export/verify tool.
- **Result:** All seeds escaped the sentinel but with 38–110 unit anchor/holdout gaps and consistent slot asymmetry; only DEAD_A fully verified (bijective AND PractRand-PASS).
- **Aftermath:** OPEN — closing questions never answered.

### [05_meta_synthesis/docs/06/opset_discovery_exp9_2026_05_23.md](05_meta_synthesis/docs/06/opset_discovery_exp9_2026_05_23.md)
- **Tried:** Meta-engine search over opset bitmasks hoping to re-derive MUL-necessity autonomously.
- **Result:** **Null result** — all 3 seeds stuck at the initial holdout (-10752.70) for all 24 iterations (penalty-based enforcement + flat landscape).
- **Aftermath:** ABANDONED as implemented — the listed redesign was never run.

### [05_meta_synthesis/docs/06/mul_free_challenge_full_run_2026_05_23.md](05_meta_synthesis/docs/06/mul_free_challenge_full_run_2026_05_23.md)
- **Tried:** Full 20M-evaluation flat-SA run of the MUL-free challenge (3 seeds × 3 modes) with PractRand ladder and Z3 checks.
- **Result:** 0/3 mul_free and 0/3 no_carry passed PractRand 1 MiB; 2/3 unrestricted passed 64 MiB but Z3-rejected as non-bijective (~31ms counterexamples).
- **Aftermath:** MODIFIED — motivated the meta-engine rerun (Exp2); upgraded to a theorem by [affine_closure_tierA_2026_05_28.md](05_meta_synthesis/docs/07/affine_closure_tierA_2026_05_28.md).

### [05_meta_synthesis/docs/07/affine_closure_tierA_2026_05_28.md](05_meta_synthesis/docs/07/affine_closure_tierA_2026_05_28.md)
- **Tried:** Formal proof tool (GF(2) matrix tracker + 65-point deterministic check + redundant Z3 oracle) converting the MUL-free BRank failure into a theorem, run on all 6 constrained champions.
- **Result:** **AFFINE_CONFIRMED 6/6** — every constrained champion proven an exact affine bijection M·x+c over GF(2) for all 2^64 inputs; "the failure is about algebraic class, not injectivity."
- **Aftermath:** ADOPTED as the repo's cleanest theorem; ⚠️ two edge qualifiers found by [i53_falsification_2026_07_10.md](docs/research/i53_falsification_2026_07_10.md) (W2b alone certifies nothing — 4095/4096 basis-passers are impostors; recurrence order is n+1=65 for c≠0) and applied in the 2026-07-10 correction pass (order bound 64→65); Tier B answered by [closure_escape_mixer.md](05_meta_synthesis/docs/07/closure_escape_mixer.md).

### [05_meta_synthesis/docs/07/closure_escape_mixer.md](05_meta_synthesis/docs/07/closure_escape_mixer.md)
- **Tried:** Direct closure test in the mixer domain — same hill-climber, MUL-free vs MUL-enabled opsets, SAC-error metric, 12,000 iters × 6 seeds.
- **Result:** Pure GF(2)-affine pinned at SAC-error exactly 0.5 (theorem); MUL-free-with-ADD plateaus at 0.1269; MUL-enabled 0.0213 — "nonlinearity is the out-of-closure generator."
- **Aftermath:** ADOPTED as the mixer witness in CLOSURE_PRINCIPLE.md; ⚠️ N4 in [results/NEGATIVE_RESULTS_LEDGER.md](results/NEGATIVE_RESULTS_LEDGER.md) notes the escape op families are human-authored lists — search within, not discovery of, the families.

### [05_meta_synthesis/docs/research/swarm_exp19_beat_gcc.md](05_meta_synthesis/docs/research/swarm_exp19_beat_gcc.md)
- **Tried:** Exhaustive IDDFS superoptimizer (u8, 7-op ISA) vs gcc -O3 on bit-hack specs, verified over all 256 inputs.
- **Result:** **PASS** — 3 certified-minimal 2-op programs beat gcc -O3 (4–5 ops); no certified win at u32/u64 (hardware POPCNT unbeatable without emitting popcnt).
- **Aftermath:** OPEN — Z3 CEGIS at u32 / enriched ISA / real compiled asm proposed, not run; the IDDFS engine grew into the addchain campaign (§10).

### [05_meta_synthesis/docs/research/swarm_exp20_weird_hacks.md](05_meta_synthesis/docs/research/swarm_exp20_weird_hacks.md)
- **Tried:** CEGIS pipeline (hill-climb + Z3 QF_BV loop) on 9 specs — 2 Hacker's Delight controls + 7 deliberately weird specs.
- **Result:** 3/9 certified: both controls rediscovered (non-minimally) and exactly 1 weird spec (`mux_double_if_odd`) got a Z3-certified structurally novel 5-op program; 6/9 stalled.
- **Aftermath:** OPEN — Tier-4 topological guidance port and richer ops proposed, not completed.

### [05_meta_synthesis/docs/research/swarm_exp21_non_mul_ops.md](05_meta_synthesis/docs/research/swarm_exp21_non_mul_ops.md)
- **Tried:** Fixed-length-8 per-op escape test: can any single non-MUL nonlinear generator (AND_NOT, ADD_ROT, MUM) match MUL-level SAC?
- **Result:** affine and affine+AND_NOT pinned at exactly 0.5000; ADD_ROT partial (0.0766); **MUM matches/beats MUL** (0.0173 vs 0.0192) — "MUL unique? NO... every full-escape generator is multiply-family."
- **Aftermath:** ADOPTED as the refined MUL-necessity statement; length-sweep/SAC-fitness reruns OPEN.

---

## 4. sparse_poly_discovery — control agent, closure witnesses, discovery frontiers

### [sparse_poly_discovery/docs/research/control_emergence.md](sparse_poly_discovery/docs/research/control_emergence.md)
- **Tried:** Five falsifiable questions on whether the "active inference engine" actually controls, vs a model-based safety-action variant.
- **Result:** As-built agent (48.20 fail/1k) worse than always-discharge (26.60); model-based selection 2.97 fail/1k greedy (~19× better than random); macros/meta layer harmful or inert; mechanism traced to attractor recognition.
- **Aftermath:** ADOPTED as the mechanism explanation for all later control docs; feeds [cp3_repulsion_floor.md](sparse_poly_discovery/docs/research/cp3_repulsion_floor.md) and [generalization.md](sparse_poly_discovery/docs/research/generalization.md).

### [sparse_poly_discovery/docs/research/generalization.md](sparse_poly_discovery/docs/research/generalization.md)
- **Tried:** Froze the greedy mb_safety controller and dropped it cold into 4 held-out regimes vs rest-floor and oracle baselines.
- **Result:** Transfer ≤ oracle in every regime, but what generalizes is sub-trivial — always-rest beats it everywhere; stochastic noise a severe failure mode (11.45 vs 0.00).
- **Aftermath:** MODIFIED — opens the substrate question answered by [expressiveness_ceiling.md](sparse_poly_discovery/docs/research/expressiveness_ceiling.md).

### [sparse_poly_discovery/docs/research/expressiveness_ceiling.md](sparse_poly_discovery/docs/research/expressiveness_ceiling.md)
- **Tried:** Tested the "linear basin" hypothesis using synthetic XOR-affine dynamics as a representable-class control.
- **Result:** Hypothesis falsified and corrected — even on representable dynamics error floors at 0.2423, traced to a 0.25 repulsion forcefield in the learning rule; removing it collapses error 5.4× (0.0445).
- **Aftermath:** MODIFIED — opens CP3 ([cp3_repulsion_floor.md](sparse_poly_discovery/docs/research/cp3_repulsion_floor.md)).

### [sparse_poly_discovery/docs/research/cp3_repulsion_floor.md](sparse_poly_discovery/docs/research/cp3_repulsion_floor.md)
- **Tried:** CP3 removed the 0.25 repulsion floor to test whether 5× better prediction improves CONTROL on the trivial battery task.
- **Result:** Falsified and reversed — prediction improved 5× (0.255→0.052) but control WORSENED everywhere (2.97→10.99 fail/1k): competence rides on prototype discriminability.
- **Aftermath:** ⚠️ Trivial-task conclusion REVERSED on the band task by [non_trivial_task.md](sparse_poly_discovery/docs/research/non_trivial_task.md) (stock 162.94 vs pure 33.62 — pure ~5× BETTER); kept as the "task triviality decides the sign" lesson.

### [sparse_poly_discovery/docs/research/non_trivial_task.md](sparse_poly_discovery/docs/research/non_trivial_task.md)
- **Tried:** Introduced the homeostatic-band task (no constant policy optimal) and re-ran the CP3 ablation on it.
- **Result:** Carries its own E1 CORRECTION withdrawing the "20.80 thermostat" framing (a grid-tuned thermostat scores 0.00); surviving claim: all constant policies fail 205–333 fail/1k and CP3-pure (33.62) beats CP3-stock (162.94) ~5×.
- **Aftermath:** ⚠️ Self-REFUTED in part (E1 banner) and REFUTES the generality of [cp3_repulsion_floor.md](sparse_poly_discovery/docs/research/cp3_repulsion_floor.md).

### [sparse_poly_discovery/docs/research/closure_escape_control.md](sparse_poly_discovery/docs/research/closure_escape_control.md)
- **Tried:** Demonstrated the closure-wall escape in control: XOR/bundle VSA cannot represent total mass; adding the SUM feature (`mb_mass`) escapes.
- **Result:** Self-correction up top — "beats hand-coded" was a strawman (tuned thermostat 0.00 crushes mb_mass 11.02); what survives: mb_mass beats all XOR-substrate agents (33.62–162.94) and the ceiling is representational (best linear readout over 8192 bits = 0.513, chance).
- **Aftermath:** ⚠️ Self-REFUTED headline, corrected in place; ADOPTED as the control witness in [CLOSURE_PRINCIPLE.md](CLOSURE_PRINCIPLE.md) with the correction attached.

### [sparse_poly_discovery/docs/research/falsification_hunt.md](sparse_poly_discovery/docs/research/falsification_hunt.md)
- **Tried:** RQ I53 attacked the project's own closure claim: MLP readout over the XOR encoding plus a training-free information-collapse test.
- **Result:** Attack FAILED decisively — MLP over XOR bits at chance (0.505) vs 0.998 on raw cells; the encoder collapses 4000 grids to 64 encodings with sum spanning [29,67] inside one bucket — destroyed information, unbreakable by ANY readout.
- **Aftermath:** ADOPTED — strengthened the principle; recorded as #53 ✅ in RESEARCH_QUESTIONS.md.

### [sparse_poly_discovery/docs/research/emergent_escape.md](sparse_poly_discovery/docs/research/emergent_escape.md)
- **Tried:** RQ #53/#38: falsify the closure principle with affine-only search, and test whether some escapes are irreducibly op-PAIRS (exact search, 2-register u8 programs).
- **Result:** Principle survived (affine base 0/5 nonlinear targets); found 2 "emergent" pair escapes at the searched depth; self-corrected the "greedy provably misses" overclaim by testing.
- **Aftermath:** ⚠️ Pair-necessity REFUTED as an unqualified claim by [i53_falsification_2026_07_10.md](docs/research/i53_falsification_2026_07_10.md) (SUB alone at depth 6; an {SHR,SHL,XOR,NOT,AND}-only witness) — this doc's own depth-qualified text was fine; the CLOSURE_PRINCIPLE.md summary wasn't.

### [sparse_poly_discovery/docs/research/pair_search.md](sparse_poly_discovery/docs/research/pair_search.md)
- **Tried:** Built `pairGrow()` — atom-forge growth escalating from single-op greedy to exhaustive O(n²) pair search when greedy stalls — tested on the isolated emergent-escape case plus op-power rankings across 5 nonlinear bit-op targets.
- **Result:** Pair-grow reaches 1/1 on the isolated case where greedy gets 0/1; no single op dominates (AND/OR/MUL each 1/5, ADD/SUB 0/5 alone) yet ADD/SUB are essential in pairs; OR+MUL strongest pair (3/5); no triplet-emergent targets found — emergence saturates at depth 2.
- **Aftermath:** ADOPTED as the "escalate to pair search when greedy stalls" design principle, transferred to the control domain and wcore (EXP-15).

### [sparse_poly_discovery/docs/research/parity_closure.md](sparse_poly_discovery/docs/research/parity_closure.md)
- **Tried:** The closure principle on canonical k-sparse parity: linear, MLP, and linear+product-monomial across k=1..4.
- **Result:** Linear at exact chance for k≥2 (0.500–0.520); MLP 1.000 at every k; linear+monomial 1.000 — the textbook fifth witness.
- **Aftermath:** ADOPTED as CLOSURE_PRINCIPLE.md's fifth witness; continued in [sparse_parity.md](sparse_poly_discovery/docs/research/sparse_parity.md) and [parity_phase_boundary.md](sparse_poly_discovery/docs/research/parity_phase_boundary.md).

### [sparse_poly_discovery/docs/research/higher_order_closure.md](sparse_poly_discovery/docs/research/higher_order_closure.md)
- **Tried:** Measured the degree staircase — can a degree-d monomial substrate represent k-parity for d<k?
- **Result:** "Theory confirmed, cleanly" — chance for d<k, exact 1.000 at d=k for every k (one class-imbalance artifact at k=4,d=3 = 0.551).
- **Aftermath:** ADOPTED as a closure witness; opens the sparse-parity sample-complexity line.

### [sparse_poly_discovery/docs/research/sparse_parity.md](sparse_poly_discovery/docs/research/sparse_parity.md)
- **Tried:** Sample-complexity growth for k-parity (k=2,3) vs irrelevant-bit count n.
- **Result:** Design artifact at n=k diagnosed; for n>k, k=2 flat (100–500 samples), k=3 grows (50→2000) but still polynomial — the exponential wall not yet reached.
- **Aftermath:** OPEN — the larger experiment needed to find the bend was specified but not run.

### [sparse_poly_discovery/docs/research/parity_phase_boundary.md](sparse_poly_discovery/docs/research/parity_phase_boundary.md)
- **Tried:** Mapped the (k, n_train) MLP parity phase boundary plus a hard-parity (random relevant bits) test.
- **Result:** Boundary at k=6, n_train∈(100,500); hard-parity null — random bits NOT harder at N=16,k≤4, contradicting the author's own SQ-bound prediction.
- **Aftermath:** OPEN — the genuine wall needs N=64–128, k=4–8, "not run here."

### [sparse_poly_discovery/docs/research/dual_band.md](sparse_poly_discovery/docs/research/dual_band.md)
- **Tried:** Added a second simultaneous band constraint to test single-feature and thermostat control.
- **Result:** 2D readout CONFIRMED needed — sum controllers fail (83.3 fail/1k vs 0.00 single-band); best single feature 39.02; nonzero_count catastrophic (499.98).
- **Aftermath:** SUPERSEDED — solved at 0.00 fail/1k by the learned quadratic basis in [basis_degree_control.md](sparse_poly_discovery/docs/research/basis_degree_control.md).

### [sparse_poly_discovery/docs/research/pair_feature_control.md](sparse_poly_discovery/docs/research/pair_feature_control.md)
- **Tried:** Exhaustive pair-feature search on dual-band control.
- **Result:** The "obvious" pair (sum, left_mass) catastrophic (270.30 fail/1k); the non-obvious (left_mass, max_cell) nearly perfect (0.25) — emergent coverage.
- **Aftermath:** ⚠️ Durability REFUTED by [triple_band.md](sparse_poly_discovery/docs/research/triple_band.md) (same pair degrades 400× under a third constraint).

### [sparse_poly_discovery/docs/research/triple_band.md](sparse_poly_discovery/docs/research/triple_band.md)
- **Tried:** Extended the dual-band winning pair to a third simultaneous constraint plus exhaustive triplet search.
- **Result:** The dual-band-optimal pair degraded 400× (0.25→98.40); best triplets tie at 3.79 — "N constraints need N features"; direct coverage robust, emergent brittle.
- **Aftermath:** ADOPTED as the principle; raw numbers superseded by the learned basis (0.00) in [basis_degree_control.md](sparse_poly_discovery/docs/research/basis_degree_control.md).

### [sparse_poly_discovery/docs/research/correlation_feature_discovery.md](sparse_poly_discovery/docs/research/correlation_feature_discovery.md)
- **Tried:** Three retrospective failure-correlation methods to discover the winning pair without O(N²) search.
- **Result:** All three NEGATIVE (259.93–291.40 fail/1k vs known-good 0.25) — max_cell has 0.000 out-of-range fraction at failure time; proactive features are retrospectively invisible.
- **Aftermath:** ABANDONED as a discovery method; the prospective variant tried in [prospective_disagreement.md](sparse_poly_discovery/docs/research/prospective_disagreement.md).

### [sparse_poly_discovery/docs/research/prospective_disagreement.md](sparse_poly_discovery/docs/research/prospective_disagreement.md)
- **Tried:** Forward-looking action-disagreement ranking vs the retrospective method on DUAL_BAND.
- **Result:** Partial positive — max_cell rose to rank #2, but the worst feature still topped the ranking (0.577) via a volatility confound.
- **Aftermath:** MODIFIED — volatility normalization proposed, not implemented.

### [sparse_poly_discovery/docs/research/adaptive_feature.md](sparse_poly_discovery/docs/research/adaptive_feature.md)
- **Tried:** AdaptiveAgent detecting model disagreement then autonomously probing candidate features to self-repair its policy.
- **Result:** Detection fired on 3/5 seeds but all 3 switched to the WORST feature, driving mean failure to 184.13 fail/1k — worse than never switching.
- **Aftermath:** MODIFIED — probe-quality fix in [adaptive_feature_v2.md](sparse_poly_discovery/docs/research/adaptive_feature_v2.md).

### [sparse_poly_discovery/docs/research/adaptive_feature_v2.md](sparse_poly_discovery/docs/research/adaptive_feature_v2.md)
- **Tried:** v1 fix: WARMUP 1500→3000, PROBE_STEPS 2000→10000, 4-seed probe averaging.
- **Result:** 0/5 wrong switches (from 3/5); mean 29.78 fail/1k (from 184.13); still never finds the better left_mass feature — short probes favor sum.
- **Aftermath:** OPEN — the probe-horizon limitation stands unfixed.

### [sparse_poly_discovery/docs/research/delta_corruption_fix.md](sparse_poly_discovery/docs/research/delta_corruption_fix.md)
- **Tried:** Fixed delta-learning corruption across environment-reset steps by skipping post-failure updates.
- **Result:** Mixed — (sum,left_mass) improved 291.40→83.30 but (left_mass,max_cell) regressed 0.25→35.40 (the blanket skip discards ~8% informative deltas).
- **Aftermath:** MODIFIED — a magnitude-threshold filter proposed but not implemented; the regression explanation unverified (OPEN).

### [sparse_poly_discovery/docs/research/basis_degree_control.md](sparse_poly_discovery/docs/research/basis_degree_control.md)
- **Tried:** Replaced hand-designed features with a learned TD danger value over linear vs quadratic bases of the raw 16 cells.
- **Result:** BREAKTHROUGH — quadratic basis 0.00 fail/1k worst-case (8 seeds) on single/dual/triple band, beating every hand-engineered optimum; linear unreliable (triple mean 72.91).
- **Aftermath:** ADOPTED as the standard control substrate; its open H4 answered by [concentration_control.md](sparse_poly_discovery/docs/research/concentration_control.md).

### [sparse_poly_discovery/docs/research/concentration_control.md](sparse_poly_discovery/docs/research/concentration_control.md)
- **Tried:** Purpose-built concentration environment testing whether max(x)≥T defeats polynomial bases.
- **Result:** DECISIVE — max provably outside polynomial closure at every finite degree (matched power sums force exact 0.500; one max feature restores 1.000); quad+max cut overflow ~4× (9.66→2.31/1k).
- **Aftermath:** ADOPTED — "the cleanest closure-boundary witness in the project"; extended by the order-statistics lattice.

### [sparse_poly_discovery/docs/research/order_statistics_closure.md](sparse_poly_discovery/docs/research/order_statistics_closure.md)
- **Tried:** Mapped whether median/rank statistics reduce to {poly + max + min}; tested two intermediate hypotheses; built a truncated-moment instrument.
- **Result:** Median NOT reducible (chance vs 1.000 with median); both intermediate hypotheses REFUTED; the moment instrument confirmed the graded law (residual 0.159→0.347 max→median); IQR needs exactly 2 rank features.
- **Aftermath:** ADOPTED — feeds the diagnosis ladder in [primitive_class_inference.md](sparse_poly_discovery/docs/research/primitive_class_inference.md).

### [sparse_poly_discovery/docs/research/primitive_class_inference.md](sparse_poly_discovery/docs/research/primitive_class_inference.md)
- **Tried:** 5-rung diagnosis ladder inferring which primitive class a target needs, closed with a forge+promote step on parity-of-count.
- **Result:** 6/6 known-class targets correctly diagnosed; parity correctly flagged beyond-ladder then forged (cos(π·count)) and promoted to 1.000 with every decoy failing.
- **Aftermath:** ADOPTED — honestly scoped "a diagnoser, not a generator"; the family-discovery gap measured in [family_gradient.md](sparse_poly_discovery/docs/research/family_gradient.md).

### [sparse_poly_discovery/docs/research/family_gradient.md](sparse_poly_discovery/docs/research/family_gradient.md)
- **Tried:** RQ C23: can gradient descent (vs grid) discover the parity frequency ω in cos(ω·count)?
- **Result:** Confirmed negative — grid 1.000 at ω≈π; gradient 0/40 runs >0.95 (best 0.728): the gradient exactly vanishes at ω=π for integer counts.
- **Aftermath:** ADOPTED as the "gradient structurally blind" result; the spectral fix built in [spectral_discovery.md](sparse_poly_discovery/docs/research/spectral_discovery.md).

### [sparse_poly_discovery/docs/research/spectral_discovery.md](sparse_poly_discovery/docs/research/spectral_discovery.md)
- **Tried:** Periodicity-aware spectral-peak operator targeting the ω=π frequency gradient descent cannot find.
- **Result:** Found ω=3.1416=π exactly, acc 1.000 (vs gradient 0.663) — "discoverable iff the discoverer's inductive bias matches the generator's structure."
- **Aftermath:** ADOPTED — core operator reused across the discovery stack.

### [sparse_poly_discovery/docs/research/multi_period.md](sparse_poly_discovery/docs/research/multi_period.md)
- **Tried:** Spectral period-finding on XOR- and AND-composed periodic predicates.
- **Result:** Single and XOR-composed found exactly (1.000); AND-composed FAILED (near-DC peak, 0.789) — sparse AND compositions are DC-dominated.
- **Aftermath:** MODIFIED — fixed by the accuracy-grid in [period_candidate_search.md](sparse_poly_discovery/docs/research/period_candidate_search.md).

### [sparse_poly_discovery/docs/research/period_candidate_search.md](sparse_poly_discovery/docs/research/period_candidate_search.md)
- **Tried:** Three period-finding strategies against the AND-composition failure.
- **Result:** Accuracy-grid FIXED it (1.000 vs 0.822); iterative-residual did NOT; triple-period 0.950 vs 0.869.
- **Aftermath:** ADOPTED — the "sp-grd" substrate in later docs.

### [sparse_poly_discovery/docs/research/operator_inference.md](sparse_poly_discovery/docs/research/operator_inference.md)
- **Tried:** Power-accuracy-mismatch signal for detecting composed/relational predicates the raw spectral operator misapplies.
- **Result:** Signal real (raw 0.503 vs inner-spectral 1.000 on inversion-parity) but the power-ratio rule FAILED to trigger (3.6× < 5.0); corrected rule proposed.
- **Aftermath:** MODIFIED — the corrected rule became the blind selector mechanism in [structure_discovery.md](sparse_poly_discovery/docs/research/structure_discovery.md).

### [sparse_poly_discovery/docs/research/composed_discovery.md](sparse_poly_discovery/docs/research/composed_discovery.md)
- **Tried:** Frontier 5: recursive closure test on two composed predicate families requiring staged pipelines.
- **Result:** Inversion-parity CONFIRMED (singles at chance; staged pipeline 1.000); product-parity PARTIAL — the quadratic expansion leaks the product term.
- **Aftermath:** OPEN question ("can the decomposition be discovered?") answered later by the blind selector.

### [sparse_poly_discovery/docs/research/antisymmetric_relational.md](sparse_poly_discovery/docs/research/antisymmetric_relational.md)
- **Tried:** Shared-basis Clifford encoding testing whether the grade-2 bivector reads an oriented/antisymmetric predicate.
- **Result:** Bivector 1.000 on the oriented predicate (real pairwise 0.583, chance) while correctly near-chance (0.510) on symmetric XOR.
- **Aftermath:** ADOPTED — closes the open question from [clifford_binding.md](sparse_poly_discovery/docs/research/clifford_binding.md): Clifford earns its keep on relational predicates only.

### [sparse_poly_discovery/docs/research/clifford_binding.md](sparse_poly_discovery/docs/research/clifford_binding.md)
- **Tried:** RQ A10: swap the VSA XOR bind for a Clifford geometric-product bind (Hadamard-real control) on band/sum predicates.
- **Result:** Escape CONFIRMED (0.503 → 0.967) but DEFLATION: Clifford does not beat the plain real Hadamard bind (0.974–0.984) — the lever is "leave GF(2)."
- **Aftermath:** MODIFIED — replicated at 6 seeds in [a10_clifford_binding.md](sparse_poly_discovery/docs/research/a10_clifford_binding.md); bivector case answered in [antisymmetric_relational.md](sparse_poly_discovery/docs/research/antisymmetric_relational.md).

### [sparse_poly_discovery/docs/research/a10_clifford_binding.md](sparse_poly_discovery/docs/research/a10_clifford_binding.md)
- **Tried:** 6-seed replication of A10 with shuffle-label and raw-probe controls.
- **Result:** Ceiling broken on all 6 seeds (0.508 → ~0.976–0.978); Clifford (0.976±0.006) statistically indistinguishable from Hadamard-real (0.978±0.008).
- **Aftermath:** ADOPTED as the settled A10 answer; the relational question continued in [swarm_exp03_clifford_relational.md](sparse_poly_discovery/docs/research/swarm_exp03_clifford_relational.md).

### [sparse_poly_discovery/docs/research/feature_discovery.md](sparse_poly_discovery/docs/research/feature_discovery.md)
- **Tried:** Can the out-of-closure generator itself be discovered? Four-level ladder: selection → unsupervised PCA → supervised → supervised+nonlinear.
- **Result:** Selection works (sum found at 11.02; decoys 37–333); PCA works when salient (cosine 0.9987) but FALSIFIED as general (0.000 on a hidden feature); supervised one-sided 0.999 but band 0.139; a tiny MLP solves the hidden band (1.000 vs linear 0.523).
- **Aftermath:** ADOPTED as the discovery ladder, each rung self-falsifying the previous rung's generality — "closure all the way up," matching wcore Claim C.

### [sparse_poly_discovery/docs/research/gradient_discovery.md](sparse_poly_discovery/docs/research/gradient_discovery.md)
- **Tried:** Frontier 12: shadow gradients identifying which degree-3 monomial extension solves k3-parity, vs random control.
- **Result:** Correct monomial found with a 29× signal gap (0.0623 vs 0.0022), accuracy chance→0.851; random stayed at chance.
- **Aftermath:** ADOPTED — foundation of the F14–F22 chain.

### [sparse_poly_discovery/docs/research/discovery_loop.md](sparse_poly_discovery/docs/research/discovery_loop.md)
- **Tried:** Frontier 14: full iterative loop (train→shadow-gradient→add→retrain) across 8 predicates.
- **Result:** k2-parity solved in 1 step; k3 cases found all features but plateaued 0.834–0.877 (optimizer); k2⊕k3 a genuine discovery failure; out-of-pool cases failed gracefully.
- **Aftermath:** MODIFIED — split into two phases and a better stop rule ([two_phase_discovery.md](sparse_poly_discovery/docs/research/two_phase_discovery.md), [dual_stop_discovery.md](sparse_poly_discovery/docs/research/dual_stop_discovery.md)).

### [sparse_poly_discovery/docs/research/two_phase_discovery.md](sparse_poly_discovery/docs/research/two_phase_discovery.md)
- **Tried:** Frontier 15: separate discovery from training (gap-stopped Phase 1, clean retrain Phase 2), 5 known + 20 random predicates.
- **Result:** Single-monomial predicates 14/14; k3-parity 0/6 — the gap-based stop halts wrongly on ties; overall 14/20.
- **Aftermath:** MODIFIED — the conjunctive dual-stop built in [dual_stop_discovery.md](sparse_poly_discovery/docs/research/dual_stop_discovery.md).

### [sparse_poly_discovery/docs/research/dual_stop_discovery.md](sparse_poly_discovery/docs/research/dual_stop_discovery.md)
- **Tried:** Frontier 16: conjunctive stop (gap<1.5 AND |g|<0.008).
- **Result:** All 4 k3-parity features found; 18/20 unknowns solved (from 14/20); k4-parity correctly rejected; the remaining 0.877 ceiling is purely optimizer convergence.
- **Aftermath:** MODIFIED — "Frontier 17: fix the optimizer" executed in [adaptive_retrain.md](sparse_poly_discovery/docs/research/adaptive_retrain.md).

### [sparse_poly_discovery/docs/research/adaptive_retrain.md](sparse_poly_discovery/docs/research/adaptive_retrain.md)
- **Tried:** Frontier 17: fixed-LR vs adaptive LR-halving retraining on the F16 features.
- **Result:** Adaptive SOLVED k3-parity, k3-random, and 20/20 blind predicates at 1.0000; k2∧k3 still fails (0.859) from pool insufficiency.
- **Aftermath:** ADOPTED for degree≤3; pool extension in [extended_pool.md](sparse_poly_discovery/docs/research/extended_pool.md).

### [sparse_poly_discovery/docs/research/extended_pool.md](sparse_poly_discovery/docs/research/extended_pool.md)
- **Tried:** Frontier 18: degree-4/5 monomial pool (62 features) for k4-parity and k2∧k3.
- **Result:** k2∧k3 SOLVED (1.0000); k4-parity FAILED (0.928, pool pollution); k5 worse (0.531); k6 correctly rejected.
- **Aftermath:** MODIFIED — guided-pool/force-add frontiers in [submonomial_solver.md](sparse_poly_discovery/docs/research/submonomial_solver.md).

### [sparse_poly_discovery/docs/research/submonomial_solver.md](sparse_poly_discovery/docs/research/submonomial_solver.md)
- **Tried:** Frontiers 19–21: guided pool pre-filter, online refinement, sub-monomial force-add against k4/k5-parity.
- **Result:** F19 fails k4/k5 (pass-1 signal algebraically zero); F20 broke k2∧k3; F21 force-add SOLVED k3/k4 and k2∧k3 at 1.0000, k5 stalled at 0.9125 (optimizer gap).
- **Aftermath:** MODIFIED — the k5 gap closed by Newton IRLS in [newton_solver.md](sparse_poly_discovery/docs/research/newton_solver.md).

### [sparse_poly_discovery/docs/research/newton_solver.md](sparse_poly_discovery/docs/research/newton_solver.md)
- **Tried:** Frontier 22: Newton/IRLS as the final-retrain solver for the k5-parity gap.
- **Result:** k5-parity SOLVED at 1.0000 in ≤30 steps (vs AdaptGD 0.9359 at 100k steps); k3/k4/k2∧k3 all 1.0000 — the discovery algorithm complete over the degree-5 pool.
- **Aftermath:** ADOPTED as the final form of the F12→F22 arc.

### [sparse_poly_discovery/docs/research/predicate_tomography.md](sparse_poly_discovery/docs/research/predicate_tomography.md)
- **Tried:** 12 predicates × 9 substrates accuracy-fingerprint matrix.
- **Result:** All 12 profiles distinct; 3 predicates defeat every substrate (max-first 0.910 peak, k3-parity 0.563, k4-parity 0.628); class imbalance masks baselines (0.918–0.932 by majority alone).
- **Aftermath:** OPEN — 5 follow-up RQs posed; RQ1 tested in [symmetry_discovery.md](sparse_poly_discovery/docs/research/symmetry_discovery.md).

### [sparse_poly_discovery/docs/research/symmetry_discovery.md](sparse_poly_discovery/docs/research/symmetry_discovery.md)
- **Tried:** Does empirical symmetry-group fraction predict which substrate class solves a predicate (12 predicates)?
- **Result:** 8/12 correct — "real but incomplete"; inv-parity measured 0.501 matching the theoretical 0.5 exactly.
- **Aftermath:** OPEN — two follow-up RQs unresolved.

### [sparse_poly_discovery/docs/research/basis_comparison.md](sparse_poly_discovery/docs/research/basis_comparison.md)
- **Tried:** Frontier 13: cos, step, square-wave, and dual classifier bases vs the fixed cos basis.
- **Result:** Step closed variance-high to 1.000; dual solved count-AND to 1.000; k-parity unsolved by any basis (~0.640).
- **Aftermath:** ADOPTED — STAGED_DUAL folded into the substrate library.

### [sparse_poly_discovery/docs/research/structure_discovery.md](sparse_poly_discovery/docs/research/structure_discovery.md)
- **Tried:** All prior operators assembled into one blind argmax selector over (inner⊗outer) pairs, 7-predicate zoo + one out-of-menu predicate.
- **Result:** 7/7 in-menu correctly routed (4/7 genuine escapes); the out-of-menu hidden pair correctly capped at its 0.591 ceiling — the selector diagnoses its own closure limit.
- **Aftermath:** ADOPTED — "the on-ramp to #3"; its 0.591 ceiling broken by [menu_growth.md](sparse_poly_discovery/docs/research/menu_growth.md).

### [sparse_poly_discovery/docs/research/inventable_substrate_design.md](sparse_poly_discovery/docs/research/inventable_substrate_design.md)
- **Tried:** Design doc for the #3 line: Phase B certified menu-growth, Phase C open inner-transform forge, built on wcore's terminal verdict.
- **Result:** No numbers of its own; predicted Phase B escapes and Phase C saturates — both later confirmed exactly.
- **Aftermath:** SUPERSEDED by its implementations: [menu_growth.md](sparse_poly_discovery/docs/research/menu_growth.md) and [inner_forge.md](sparse_poly_discovery/docs/research/inner_forge.md).

### [sparse_poly_discovery/docs/research/menu_growth.md](sparse_poly_discovery/docs/research/menu_growth.md)
- **Tried:** Phase B: grow the fixed menu by one certified parameter (which pair) via discover→certify→promote against the Frontier-24 ceiling.
- **Result:** POSITIVE — 0.591 → 1.000 on the hidden pair, certified escape + irreducibility; but the wall relocated — no single pair reaches a hidden triple (0.501) while a triple-relation inner solves it (1.000).
- **Aftermath:** ADOPTED then MODIFIED — Phase C follows ([inner_forge.md](sparse_poly_discovery/docs/research/inner_forge.md)); the arity ladder continued in the swarm fork docs.

### [sparse_poly_discovery/docs/research/inner_forge.md](sparse_poly_discovery/docs/research/inner_forge.md)
- **Tried:** Phase C: open unbounded-arity certified-promotion forge over centered monomials against the 5-target zoo.
- **Result:** Discovered the exact hidden monomials blind, then SATURATED at round 2 (4/5 solved; T5 parity stuck at 0.50) — "saturates at the monomial closure."
- **Aftermath:** ADOPTED as the second-substrate replication of wcore's atom-forge result; T5 later escaped via the operator menu (Fork 1, [parallel_forks_2026.md](sparse_poly_discovery/docs/research/parallel_forks_2026.md)).

### [sparse_poly_discovery/docs/research/boolean_fourier.md](sparse_poly_discovery/docs/research/boolean_fourier.md)
- **Tried:** Mapped every hand-rolled discovery probe onto the exact Walsh–Hadamard transform.
- **Result:** WHT recovers exact hidden support in <1s each vs ~30s custom forges; Fourier degree predicts the linear-readout ceiling exactly.
- **Aftermath:** SUPERSEDED the ad-hoc forge machinery for analysis; sets up [clone_lattice.md](sparse_poly_discovery/docs/research/clone_lattice.md).

### [sparse_poly_discovery/docs/research/clone_lattice.md](sparse_poly_discovery/docs/research/clone_lattice.md)
- **Tried:** Post's lattice (5 maximal Boolean clones) applied to explain every empirical closure ceiling as an exact clone-membership fact.
- **Result:** Every prior ceiling confirmed as a maximal-clone obstruction; {AND,XOR,CONST1}, {AND,NOT}, {NAND} each provably universal.
- **Aftermath:** ADOPTED — "the grand unification of the #3 arc"; its k≥3 limit documented in [kary_frontier.md](sparse_poly_discovery/docs/research/kary_frontier.md).

### [sparse_poly_discovery/docs/research/kary_frontier.md](sparse_poly_discovery/docs/research/kary_frontier.md)
- **Tried:** Exposition of clone-lattice combinatorics: why purist invention terminates cleanly at k=2 but not k≥3.
- **Result:** 2/16 binary ops universal (NOR, NAND); k=2 has 5 maximal clones (Post 1941); k≥3 a continuum (Janov–Mučnik 1959) — no finite closure fingerprint.
- **Aftermath:** OPEN — names where k≥3 work should build; no successor built it.

### [sparse_poly_discovery/docs/research/family_closures.md](sparse_poly_discovery/docs/research/family_closures.md)
- **Tried:** 4×4 predicate-vs-algebra matrix: are tropical, real-affine, GF(2)-affine, and multilinear families genuinely incomparable closures?
- **Result:** Matrix is diagonal — each algebra reads only its native predicate (~1.0), chance elsewhere; one explained tropical/affine bleed (0.78/0.70).
- **Aftermath:** ADOPTED — retroactively unifies the concentration/menu/emergent-escape results as matroid-closure facts.

### [sparse_poly_discovery/docs/research/representation_discovery.md](sparse_poly_discovery/docs/research/representation_discovery.md)
- **Tried:** Single learnable power-mean exponent p (mean↔max): can gradient discover the right order-statistic rung? Plus a TD-control transfer and a signed-Boltzmann extension.
- **Result:** MAX task decisive (p 2.00→54.14, acc 1.000); SUM right-region-not-exact (0.890); TD-control transfer NEGATIVE (0/8 seeds); Boltzmann variant broken and reverted.
- **Aftermath:** ADOPTED (dense supervised) / documented NEGATIVE (control transfer); follow-ups proposed, not run.

### [sparse_poly_discovery/docs/research/bit_state_mechanism.md](sparse_poly_discovery/docs/research/bit_state_mechanism.md)
- **Tried:** Frontier 23: bit-addressed state machine at the same 256-bit budget as float-scan, targeting the unreached recall+parity corner.
- **Result:** CONFIRMED — 1.0000 on parity_long AND all recall levels (scan: 0.2578 at K100; attention: 0.4977 parity); novelty distance 0.688 (>0.35).
- **Aftermath:** ADOPTED as refutation of the "inherent tradeoff" reading; 4 open questions remain.

### [sparse_poly_discovery/docs/research/hardness_router_integration.md](sparse_poly_discovery/docs/research/hardness_router_integration.md)
- **Tried:** Wired the Q38 hardness-router classification inline into `boundary_crossing/verify_learn_invent.zig` for English "discover" intents.
- **Result:** Routing matched the full unified_invention loop on all 3 sample targets (all certified 1.000); inner_forge alone 5/7 vs unified 7/7.
- **Aftermath:** ADOPTED — Fork 5/2 lineage in [parallel_forks_2026.md](sparse_poly_discovery/docs/research/parallel_forks_2026.md).

### [sparse_poly_discovery/docs/research/parallel_forks_2026.md](sparse_poly_discovery/docs/research/parallel_forks_2026.md)
- **Tried:** Consolidated re-run of seven research forks with fresh `--release=fast` measurements.
- **Result:** All 7 PASS (T5 0.50→1.00 via spectral menu; router matches brute at 2.4× fewer evals; engine beats binary addition chains 735/1023); synthesis: every forge/router/menu "bottoms at its injected closure."
- **Aftermath:** ADOPTED as the fork-ecology integration point; the addition-chain fork grew into the addchain campaign (§10).

### [sparse_poly_discovery/docs/research/swarm_exp01_menu_growth.md](sparse_poly_discovery/docs/research/swarm_exp01_menu_growth.md)
- **Tried:** Re-ran and verified the menu-growth pair-selection discovery on hidden pair (2,5) plus a regression check of the F24 structure-discovery baseline.
- **Result:** PASS — every number matched the prior doc exactly (ceiling broken 0.591→1.000, P0–P6 all 1.000, no regressions); the hidden triple showed the pair family cannot escape (best pair 0.501 ≈ chance).
- **Aftermath:** MODIFIED — the triple-arity question executed in [swarm_fork_triple_arity.md](sparse_poly_discovery/docs/research/swarm_fork_triple_arity.md).

### [sparse_poly_discovery/docs/research/swarm_exp02_pair_router.md](sparse_poly_discovery/docs/research/swarm_exp02_pair_router.md)
- **Tried:** Correlation-based "guided" pair-selection router replacing brute-force 28-pair logistic search for degree-2 predicates.
- **Result:** PASS — matched brute-force pair identity and accuracy on 6/6 targets at 2.5× fewer fits (11 vs 28); the anchor-based O(N) scan failed 0/6 and was not shipped.
- **Aftermath:** ADOPTED — reused as RQ1++ step 3 and in the two-feature control harness.

### [sparse_poly_discovery/docs/research/swarm_exp03_clifford_relational.md](sparse_poly_discovery/docs/research/swarm_exp03_clifford_relational.md)
- **Tried:** Clifford bivector binding vs plain product(i,j) on symmetric, oriented, real-grid, and blind focal-pair predicates.
- **Result:** Mixed — ties/loses on symmetric XOR (0.998 vs 1.000) and the real grid control, but WINS cleanly on oriented sign(v1−v0) (1.000 vs 0.583).
- **Aftermath:** ADOPTED (narrow) — verdict "KEEP niche / DROP default": oriented(i,j) kept as a menu inner, Clifford dropped as the general relational bind.

### [sparse_poly_discovery/docs/research/swarm_exp04_rq1_gap.md](sparse_poly_discovery/docs/research/swarm_exp04_rq1_gap.md)
- **Tried:** Diagnosed per-target why RQ1's no-menu battery certifies only 6/11, tracing which escalation step closes each saturated target.
- **Result:** Baseline reproduced at 6/11; pair-growth alone closes only B1 (7/11); adding gated Walsh correlation search projects 11/11.
- **Aftermath:** MODIFIED — implemented and confirmed as RQ1++ in [swarm_fork_rq1_escalation.md](sparse_poly_discovery/docs/research/swarm_fork_rq1_escalation.md).

### [sparse_poly_discovery/docs/research/swarm_exp05_rq9_taxonomy.md](sparse_poly_discovery/docs/research/swarm_exp05_rq9_taxonomy.md)
- **Tried:** Taxonomy (basis-repro / synthesis-only / pipeline-only / genuinely-novel) of RQ9's 6 escape claims under v1 vs v2 expanded bases.
- **Result:** v1 4/6 reproducible (66.7%); v2 reclassified E5-F-A to synthesis-only (0.508→0.952), leaving E4-G00 as the sole genuinely-novel survivor (v2 test 0.463).
- **Aftermath:** MODIFIED — the E4-G00 fork executed in [swarm_fork_e4_g00_mint.md](sparse_poly_discovery/docs/research/swarm_fork_e4_g00_mint.md).

### [sparse_poly_discovery/docs/research/swarm_exp08_planning.md](sparse_poly_discovery/docs/research/swarm_exp08_planning.md)
- **Tried:** Multi-step planning (H-step exhaustive rollout over the learned mb_mass delta model) vs greedy control on the band task.
- **Result:** FAIL — best planning (H=3) 10.92 fail/1k vs greedy 11.02 (within noise); H=5 doubled failures (23.39); both 10.9× worse than the tuned thermostat (0.00).
- **Aftermath:** ABANDONED as a competence lever; the thermostat gap picked up as falsification hunt I56 in [swarm_exp10_thermostat.md](sparse_poly_discovery/docs/research/swarm_exp10_thermostat.md).

### [sparse_poly_discovery/docs/research/swarm_exp09_two_feature.md](sparse_poly_discovery/docs/research/swarm_exp09_two_feature.md)
- **Tried:** Autonomous 2-feature search (exhaustive, correlation, hardness-guided) on dual-band where single-feature control fails (83.31 fail/1k).
- **Result:** Exhaustive and hardness-guided both found the true pair (left_mass, max_cell) at 35.13–35.40 (beating best single 39.02) at ~5× lower cost; correlation-based FAILED (83.33) — max_cell is proactive, invisible retrospectively.
- **Aftermath:** ADOPTED (guided routing) / OPEN (retrospective escalation); notes the pre-[delta_corruption_fix.md](sparse_poly_discovery/docs/research/delta_corruption_fix.md) 0.25 number is corrected to ~35.40.

### [sparse_poly_discovery/docs/research/swarm_exp10_thermostat.md](sparse_poly_discovery/docs/research/swarm_exp10_thermostat.md)
- **Tried:** Falsification hunt I56: is mb_mass's win over hand-coded control fragile to harder hand-tuning (grid, hysteresis 8,064 configs, lookahead)?
- **Result:** CONFIRMED FRAGILE — best hand-tuned reaches 0.00 fail/1k, decisively beating mb_mass's 11.02; "prior win was STRAWMAN" (the stock 20.80 thermostat was under-tuned).
- **Aftermath:** ADOPTED — REFUTES the original "mb_mass beats hand-coded" claim and confirms the corrected framing in [closure_escape_control.md](sparse_poly_discovery/docs/research/closure_escape_control.md); the closure-escape residual (beats XOR agents) survives.

### [sparse_poly_discovery/docs/research/swarm_exp11_multi_objective.md](sparse_poly_discovery/docs/research/swarm_exp11_multi_objective.md)
- **Tried:** Multi-objective (safety vs delivered work) Pareto comparison of thermostat grid, mb_mass, and mb_mass2 (C27).
- **Result:** PASS — learners hold 3 of 14 Pareto points; mb_mass found an interior trade-off no hand grid point reaches (11.02 fail / 750 work); no learner beat hand-coded on both axes at either anchor.
- **Aftermath:** OPEN — dual-band multi-objective and work-aware learner forks never picked up.

### [sparse_poly_discovery/docs/research/swarm_exp22_parity_phase.md](sparse_poly_discovery/docs/research/swarm_exp22_parity_phase.md)
- **Tried:** Mapped the (k,n,samples) phase boundary (F41) where SGD on degree-k monomials stops finding sparse parity.
- **Result:** PASS — 9/15 cells FOUND / 6/15 WALL; rule: solvable when n≥k+4; min samples 100 (k=2) → 500 (k=3) → 5000 (k=4); no exponential wall through k=4, n=20.
- **Aftermath:** OPEN — k=4 at n∈{24–48}, k=5, and LPN noise probes proposed, not run.

### [sparse_poly_discovery/docs/research/swarm_exp23_sample_curve.md](sparse_poly_discovery/docs/research/swarm_exp23_sample_curve.md)
- **Tried:** Sample-complexity curve (F43) for supervised recovery of a hidden non-salient feature behind a loud decoy, sweeping label budgets.
- **Result:** PCA flat at cosine 0.000 at every budget; supervised recovery monotone (0.441→0.903), crossing 0.90 at n=1000 labels (~2% of pool).
- **Aftermath:** OPEN — F45 (decoy-to-signal variance sweep) named as follow-up, not executed.

### [sparse_poly_discovery/docs/research/swarm_fork_e4_g00_mint.md](sparse_poly_discovery/docs/research/swarm_fork_e4_g00_mint.md)
- **Tried:** Does the "genuinely-novel" mint G00 generalize across held-out grid seeds, and does promoting it lift downstream solve rate?
- **Result:** Novelty stable across 4 seed pairs (mean 0.460, max|ρ|<0.995) but promotion gave ZERO downstream lift (0/20 → 0/20).
- **Aftermath:** ADOPTED as a falsification anchor / ABANDONED as a library primitive — "novel but 0 lift" became the failure mode Tier-8 T8-AG-28 targeted.

### [sparse_poly_discovery/docs/research/swarm_fork_triple_arity.md](sparse_poly_discovery/docs/research/swarm_fork_triple_arity.md)
- **Tried:** Extended the menu-growth certify/promote loop to triple-arity relations against the hidden triple (1,3,6).
- **Result:** PASS — triple discovered blind at test 1.000 (pair-menu baseline 0.513 ≈ chance), certified and promoted; next wall at hidden quad (best triple 0.503).
- **Aftermath:** MODIFIED — quad rung executed in [swarm_fork_quad_arity.md](sparse_poly_discovery/docs/research/swarm_fork_quad_arity.md).

### [sparse_poly_discovery/docs/research/swarm_fork_quad_arity.md](sparse_poly_discovery/docs/research/swarm_fork_quad_arity.md)
- **Tried:** Extended the arity ladder to quad relations against the hidden quad (0,4,5,7).
- **Result:** PASS — quad discovered blind at 1.000 (triple-menu baseline 0.499), certified (kill-test R²=1.000) and promoted; next wall at hidden quint (best quad 0.504).
- **Aftermath:** MODIFIED — quint rung executed in [swarm_fork_quint_arity.md](sparse_poly_discovery/docs/research/swarm_fork_quint_arity.md).

### [sparse_poly_discovery/docs/research/swarm_fork_quint_arity.md](sparse_poly_discovery/docs/research/swarm_fork_quint_arity.md)
- **Tried:** Extended the ladder to quint-arity relations, completing the pair→triple→quad→quint chain.
- **Result:** PASS — quint discovered blind at 1.000 (quad-menu baseline 0.506), certified and promoted; quint is the last nontrivial arity step before full-grid degree-8 on NCELL=8.
- **Aftermath:** ADOPTED as the ladder terminus — "saturates at arity 8"; Phase C's unfixed-arity open forge remains the open item.

### [sparse_poly_discovery/docs/research/swarm_fork_rq1_escalation.md](sparse_poly_discovery/docs/research/swarm_fork_rq1_escalation.md)
- **Tried:** Implemented the 4-step "RQ1++" structural escalation ladder (frozen monomial → count synth/pipelines → pair router → gated Walsh) with no pre-labeled menu.
- **Result:** PASS — 6/11 → **11/11** certified with 0 saturated, matching E1's handed-menu coverage while keeping routing structural.
- **Aftermath:** ADOPTED — the strongest new result of the 2026-07-05 swarm; became the staged-escalation pattern in the production invention engine.

---

## 5. sparse_poly_discovery — the open-invention program (E1–E28, RQ1–RQ10)

### [docs/research/open_invention_experiments.md](docs/research/open_invention_experiments.md)
- **Tried:** Master doc for 12 experiments (E1–E12) testing whether a verifier-native stack can invent outside a handed operator menu.
- **Result:** Mixed — genuine positives E3 (parity 1.000 via mod(count,2)), E4 (0%→90%), E5 (→1.000 blind), E11 (1 novel LLM proposal); honest failures E6 (0/16 aliens), E7 (+0 corpus lift), E2 (14/24 oracle-only); verdict: "search inside a fixed closure composes... not minting new mathematics from nothing."
- **Aftermath:** MODIFIED — followed by [docs/research/open_invention_followup.md](docs/research/open_invention_followup.md) (RQ1–RQ10).

### [docs/research/open_invention_followup.md](docs/research/open_invention_followup.md)
- **Tried:** Ten follow-up RQs probing the passing/partial E1–E12 results (menu removal, XOR injection, transfer, certifier soundness, equivalence tax).
- **Result:** RQ2 11/11 gap closed; RQ4 "100% equivalent — not real minting"; RQ9 4/6 = 67% of escapes reproducible (remix); RQ10 0/64 false promotes (certifier sound).
- **Aftermath:** ADOPTED as the honest correction layer over E1–E12; extended by the E13+ series and RQ1++ staged escalation in the 2026-07-05 swarm.

### [sparse_poly_discovery/docs/research/open_invention_e1.md](sparse_poly_discovery/docs/research/open_invention_e1.md)
- **Tried:** Froze the 11-atom library after zoo-A training, then ran 11 blind battery-B targets with a discovery menu, monomial forge disabled.
- **Result:** PASS — 11/11 solved, 9 via primitives outside the frozen menu, 0 false-promotes; but 0/11 saturated because the menu spans every family present.
- **Aftermath:** ⚠️ Headline corrected by [open_invention_rq1.md](sparse_poly_discovery/docs/research/open_invention_rq1.md): without the handed menu only 6/11 certify — "substantially menu-assisted."

### [sparse_poly_discovery/docs/research/open_invention_e2.md](sparse_poly_discovery/docs/research/open_invention_e2.md)
- **Tried:** POET-lite adversarial target generator (hard for the library, trivial for an oracle), then the open forge on 24 kept targets.
- **Result:** PARTIAL FAIL — forge matched the oracle on only 10/24 (42%); every gap an XOR-cell/parity-on-XOR predicate.
- **Aftermath:** MODIFIED — [open_invention_rq2.md](sparse_poly_discovery/docs/research/open_invention_rq2.md) injects `xor_popcount` and closes 11/11 of the residual gap.

### [sparse_poly_discovery/docs/research/open_invention_e3.md](sparse_poly_discovery/docs/research/open_invention_e3.md)
- **Tried:** Certify parity using only monomials/sums/rank stats plus depth≤4 count-program synthesis — no spectral/Walsh/Clifford.
- **Result:** PASS — parity 1.000 via synthesized `mod(count,2)`, plus 10/10 random Boolean χ_S targets.
- **Aftermath:** MODIFIED — generalized by [open_invention_rq3.md](sparse_poly_discovery/docs/research/open_invention_rq3.md) and [open_invention_e16.md](sparse_poly_discovery/docs/research/open_invention_e16.md).

### [sparse_poly_discovery/docs/research/open_invention_e4.md](sparse_poly_discovery/docs/research/open_invention_e4.md)
- **Tried:** VM program synthesizer minting opaque certified primitives from a minimal menu against 20 hard predicates.
- **Result:** POSITIVE (bounded) — 2 minted primitives lifted solve rate 0%→90% (18/20), but the forge saturated after 1 round.
- **Aftermath:** ⚠️ REFUTED as "real minting" by [open_invention_rq4.md](sparse_poly_discovery/docs/research/open_invention_rq4.md) (100% VM-equivalent) — that refutation itself later REVERSED by [open_invention_e21.md](sparse_poly_discovery/docs/research/open_invention_e21.md) once outside generators entered the mint space.

### [sparse_poly_discovery/docs/research/open_invention_e5.md](sparse_poly_discovery/docs/research/open_invention_e5.md)
- **Tried:** Blind 2-stage meta-menu (neutrally named operators) discovering composed structure without being told "product" or "spectral."
- **Result:** PASS 2/2 — both families certified at 1.000 (from 0.540/0.431 stage-1-only).
- **Aftermath:** MODIFIED — grammar frozen and transferred in [open_invention_rq5.md](sparse_poly_discovery/docs/research/open_invention_rq5.md), extended in [open_invention_e17.md](sparse_poly_discovery/docs/research/open_invention_e17.md).

### [sparse_poly_discovery/docs/research/open_invention_e6.md](sparse_poly_discovery/docs/research/open_invention_e6.md)
- **Tried:** Open certified-promotion forge with k≥3 substrate against 16 random "alien" targets never designed into the pool.
- **Result:** FAIL — 0/16 solved, 0 certified alien promotions; immediate saturation at the 8-singleton base.
- **Aftermath:** MODIFIED-AND-CONFIRMED — [open_invention_e24.md](sparse_poly_discovery/docs/research/open_invention_e24.md) reran with a different schedule, also 0/16: schedule-independent closure.

### [sparse_poly_discovery/docs/research/open_invention_e7.md](sparse_poly_discovery/docs/research/open_invention_e7.md)
- **Tried:** Forged byte-pair "runes" from a 250KB EN/ZH corpus as features on grid predicates where monomials saturate.
- **Result:** FAIL — zero lift beyond the frozen symbolic menu; T7 stuck at 0.871 in every arm.
- **Aftermath:** MODIFIED — retried with terminal traces in [open_invention_e22.md](sparse_poly_discovery/docs/research/open_invention_e22.md), again zero lift.

### [sparse_poly_discovery/docs/research/open_invention_e10.md](sparse_poly_discovery/docs/research/open_invention_e10.md)
- **Tried:** Novelty-only forge vs usefulness-driven forge on a 128-target random battery and the T1–T5 zoo.
- **Result:** Tension confirmed — novelty forge 10.9% battery / 2/5 zoo; useful forge 1.6% / 4/5.
- **Aftermath:** MODIFIED — knob sweep in [open_invention_e25.md](sparse_poly_discovery/docs/research/open_invention_e25.md) found the surface flat (untunable).

### [sparse_poly_discovery/docs/research/open_invention_e11.md](sparse_poly_discovery/docs/research/open_invention_e11.md)
- **Tried:** LLM authored 20 JSON feature proposals over 3 grid targets, Zig harness as sole certifying judge plus a novelty gate.
- **Result:** PASS — 8/20 pairs certified (test=1.000 each), 1 novel under the gate (`sum_mod7_indicator`); all creative misfires rejected.
- **Aftermath:** ⚠️ MODIFIED — [open_invention_rq7.md](sparse_poly_discovery/docs/research/open_invention_rq7.md) RECLASSIFIED `sum_mod7_indicator` as world-pool-reproducible (not novel); wake-sleep extension in [open_invention_e19.md](sparse_poly_discovery/docs/research/open_invention_e19.md).

### [sparse_poly_discovery/docs/research/open_invention_e12.md](sparse_poly_discovery/docs/research/open_invention_e12.md)
- **Tried:** 75-round POET-style propose/solve/verify self-play over a typed TargetSpec DSL.
- **Result:** All 7 depth tiers solved and held (100% of 225 proposals), but the curriculum collapsed to 0–1 entries — solver too strong for the easy mutators.
- **Aftermath:** MODIFIED — hard-mutator fix in [open_invention_rq8.md](sparse_poly_discovery/docs/research/open_invention_rq8.md), stress-tested in [open_invention_e20.md](sparse_poly_discovery/docs/research/open_invention_e20.md).

### [sparse_poly_discovery/docs/research/open_invention_e14.md](sparse_poly_discovery/docs/research/open_invention_e14.md)
- **Tried:** Hardness router auto-classifying 50 held-out targets and auto-picking xor_popcount/mod/pipeline routes, no manual hints.
- **Result:** PASS — 42/50 (84.0%) certified with 2.0% wrong-route waste; closed all 11/11 of E2's oracle-only gaps via routing alone.
- **Aftermath:** ADOPTED — reused on real DeepSeek activations in [open_invention_e28.md](sparse_poly_discovery/docs/research/open_invention_e28.md).

### [sparse_poly_discovery/docs/research/open_invention_e16.md](sparse_poly_discovery/docs/research/open_invention_e16.md)
- **Tried:** Extended the E3 synthesis escape to a 20-target mod battery (bar ≥12/20 synthesis-certified, 0 Walsh).
- **Result:** PASS — 20/20 certified, 15/20 via synthesis, 0 Walsh; composed affine mod needed explicit sum+count leaves.
- **Aftermath:** ADOPTED — its families feed the E26 tax basis.

### [sparse_poly_discovery/docs/research/open_invention_e17.md](sparse_poly_discovery/docs/research/open_invention_e17.md)
- **Tried:** Meta-search over 2–3 stage grammars (novel `inner_mid` glue) on 50 held-out composed targets.
- **Result:** FAIL on certify bar (33/50 = 66.0% vs 35 required) but PASS on novelty (3 novel 3-stage compositions); failures cluster on the known bind_abs borderline.
- **Aftermath:** OPEN — the residual bind_abs cluster has no successor experiment.

### [sparse_poly_discovery/docs/research/open_invention_e19.md](sparse_poly_discovery/docs/research/open_invention_e19.md)
- **Tried:** DreamCoder-style 10-round wake-sleep loop (500 LLM proposals) with the expanded tax as novelty gate.
- **Result:** FAIL on cert-rate (5.4% vs ≥15%) but PASS on novelty (10 RQ9-novel vs ≥5); library plateaued rounds 4–9.
- **Aftermath:** UNCLEAR — no downstream doc retries the wake-sleep shortfall.

### [sparse_poly_discovery/docs/research/open_invention_e20.md](sparse_poly_discovery/docs/research/open_invention_e20.md)
- **Tried:** RQ8's hard-mutator POET fix run 200 rounds under a stricter bar.
- **Result:** PASS — solve rate ~50.7%, curriculum saturated at cap (48) and held; frontier depth 17.
- **Aftermath:** ADOPTED as the long-horizon confirmation of the RQ8 fix.

### [sparse_poly_discovery/docs/research/open_invention_e21.md](sparse_poly_discovery/docs/research/open_invention_e21.md)
- **Tried:** E4-style minting rerun after unlocking mod-synthesis, xor_popcount, and pipeline generators, 42 targets.
- **Result:** PASS — 9/10 promotions escaped depth≤8 VM equivalence, reversing RQ4's 100%-equivalent finding.
- **Aftermath:** ADOPTED as the E4/RQ4 resolution — REFUTES the generality of [open_invention_rq4.md](sparse_poly_discovery/docs/research/open_invention_rq4.md).

### [sparse_poly_discovery/docs/research/open_invention_e22.md](sparse_poly_discovery/docs/research/open_invention_e22.md)
- **Tried:** E7's rune protocol on 200 live terminal execution traces (35,630 bytes) instead of prose.
- **Result:** FAIL — +0.000 lift on both T5 and T7; trace bigrams are shell/path fragments irrelevant to grid geometry.
- **Aftermath:** OPEN — "cross-modal trace→grid encoder" named as the missing piece, never built.

### [sparse_poly_discovery/docs/research/open_invention_e24.md](sparse_poly_discovery/docs/research/open_invention_e24.md)
- **Tried:** E6's 16 alien targets rerun with the k3_order_escape forge engine/schedule.
- **Result:** FAIL — 0/16, immediate saturation, same as E6.
- **Aftermath:** ABANDONED-in-place — the closure law is schedule-independent at k≥3.

### [sparse_poly_discovery/docs/research/open_invention_e25.md](sparse_poly_discovery/docs/research/open_invention_e25.md)
- **Tried:** 12-point sweep of the certifier's R²×escape knobs hunting a Pareto point for the E10 tension.
- **Result:** FAIL — all 12 points identical to baseline (ratio 0.14×, 2.34/100); the surface is completely flat.
- **Aftermath:** ABANDONED — "cannot be tuned into" resolution on this substrate.

### [sparse_poly_discovery/docs/research/open_invention_e26.md](sparse_poly_discovery/docs/research/open_invention_e26.md)
- **Tried:** RQ9's equivalence tax with an expanded basis (mod synthesis, xor_popcount, E5 pipelines) against 20 escapes from E1–E12.
- **Result:** FAIL for "genuine invention" — 17/20 (85.0%) reproducible; only 3 novel survivors (E4-G00 0.463, E2 parity-XOR 0.746, E12 rank2 0.793).
- **Aftermath:** ADOPTED as the definitive tax reading — the direct motivation for the Tier 8 tax-gate program (§7).

### [sparse_poly_discovery/docs/research/open_invention_e27.md](sparse_poly_discovery/docs/research/open_invention_e27.md)
- **Tried:** Certified invention stack vs an honest best-of-3 transformer-proxy (no verifier) on 100 checker-verifiable tasks.
- **Result:** PASS — stack 50/50 (100%) holdout vs proxy 20/50 (40%), 2.50× (bar ≥2.0×); proxy 0/13 on compress.
- **Aftermath:** UNCLEAR — no follow-up; tool-augmented LM comparison flagged as a different experiment.

### [sparse_poly_discovery/docs/research/open_invention_e28.md](sparse_poly_discovery/docs/research/open_invention_e28.md)
- **Tried:** Hardness-router + unified invention loop on real captured DeepSeek V4 L30 expert activations.
- **Result:** PASS — 16/16 candidate experts certified (lift ≥5%), all RQ9-novel; champion e38 held-out R²=0.188, 28.0% lift.
- **Aftermath:** ADOPTED as the capstone real-data application.

### [sparse_poly_discovery/docs/research/open_invention_rq1.md](sparse_poly_discovery/docs/research/open_invention_rq1.md)
- **Tried:** E1's blind battery rerun with the spectral/Walsh/Clifford/world menu stripped out.
- **Result:** Only 6/11 certify without the menu (vs E1's 11/11), 5/11 saturate — exactly the menu-dependent targets.
- **Aftermath:** ADOPTED as the honest E1 correction; "RQ1++" staged escalation later reached 11/11 (2026-07-05 swarm); ⚠️ N4 in [results/NEGATIVE_RESULTS_LEDGER.md](results/NEGATIVE_RESULTS_LEDGER.md) notes RQ1's candidate families are authored in source — search within a human hypothesis space.

### [sparse_poly_discovery/docs/research/open_invention_rq2.md](sparse_poly_discovery/docs/research/open_invention_rq2.md)
- **Tried:** Injected a minimal `xor_popcount(mask)` primitive (mask search only) into E2's forge.
- **Result:** PASS — closed 11/11 (100%) of the residual oracle-only XOR gap; fixed a popcount-vs-LSB parity bug.
- **Aftermath:** ADOPTED — `xor_popcount` became a standard route (E14 routing, E21 minting).

### [sparse_poly_discovery/docs/research/open_invention_rq3.md](sparse_poly_discovery/docs/research/open_invention_rq3.md)
- **Tried:** Generalized the E3 mod-synthesis escape to 20 non-parity periodic/composed targets (bar ≥3/20).
- **Result:** PASS — ≥9/20 certified via synthesized mod(·,k); sign-pattern mods stayed outside the closure.
- **Aftermath:** MODIFIED — extended by the dedicated mod battery [open_invention_e16.md](sparse_poly_discovery/docs/research/open_invention_e16.md).

### [sparse_poly_discovery/docs/research/open_invention_rq4.md](sparse_poly_discovery/docs/research/open_invention_rq4.md)
- **Tried:** Equivalence oracle (exhaustive depth≤6 VM search, 8192 programs) testing whether E4's minted programs are outside the base VM closure.
- **Result:** FAIL for real minting — 100% (2/2) VM-equivalent with zero disagreement: selection+certification inside a closed VM.
- **Aftermath:** ⚠️ REFUTED-IN-GENERALITY by [open_invention_e21.md](sparse_poly_discovery/docs/research/open_invention_e21.md) — 9/10 escape depth≤8 once mod/xor_popcount generators enter the mint space.

### [sparse_poly_discovery/docs/research/open_invention_rq5.md](sparse_poly_discovery/docs/research/open_invention_rq5.md)
- **Tried:** Froze E5's 2-stage grammar and tested transfer to 30 novel held-out two-stage specs (bar ≥50%).
- **Result:** PASS — 24/30 (80.0%) certified; failures cluster on borderline bind_abs routes (~0.70).
- **Aftermath:** MODIFIED — extended to 3-stage meta-search in [open_invention_e17.md](sparse_poly_discovery/docs/research/open_invention_e17.md), which hits the same cluster.

### [sparse_poly_discovery/docs/research/open_invention_rq7.md](sparse_poly_discovery/docs/research/open_invention_rq7.md)
- **Tried:** Scaled the LLM-proposer protocol to 100 proposals / 5 families with an expanded novelty gate.
- **Result:** PASS — 25/100 certified, 9 novel across 3 families; `sum_mod7_indicator` reclassified as world-equivalent (not novel).
- **Aftermath:** MODIFIED — scaled to wake-sleep in [open_invention_e19.md](sparse_poly_discovery/docs/research/open_invention_e19.md); production wiring became Tier-8 T8-AG-07.

### [sparse_poly_discovery/docs/research/open_invention_rq8.md](sparse_poly_discovery/docs/research/open_invention_rq8.md)
- **Tried:** Replaced E12's easy mutators with hard mutators (Walsh deg 3–5, composed AND, label noise) over 50 POET rounds.
- **Result:** PASS — solve rate a healthy 44.0% (from degenerate 100%), curriculum 48 (from 1), in-band ≥10 for 44/50 rounds.
- **Aftermath:** ADOPTED — hardened over 200 rounds in [open_invention_e20.md](sparse_poly_discovery/docs/research/open_invention_e20.md).

### [sparse_poly_discovery/docs/research/open_invention_rq9.md](sparse_poly_discovery/docs/research/open_invention_rq9.md)
- **Tried:** Built the cross-cutting "equivalence tax" (monomial+Walsh+world+VM basis, 8697 candidates) testing 6 escapes (bar <30% reproducible).
- **Result:** FAIL — 4/6 (66.7%) reproducible in the rich basis; only E5-F-A (0.508) and partially E4-G00 (0.830) survive as genuine.
- **Aftermath:** SUPERSEDED-BY [open_invention_e26.md](sparse_poly_discovery/docs/research/open_invention_e26.md) (expanded basis, 85%); the tax became the Tier 8 Phase-1 instrument.

### [sparse_poly_discovery/docs/research/open_invention_rq10.md](sparse_poly_discovery/docs/research/open_invention_rq10.md)
- **Tried:** Certifier soundness stress: forge on 64 pure-random-label and 5 shuffled-label targets, expecting 0 false promotions.
- **Result:** PASS — 0/64 and 0/5 false promotes while the structured control still promoted 3/5 — neither hallucinating nor vacuous.
- **Aftermath:** ADOPTED as the standing certifier validation for the whole E-series.

---

## 6. boundary_crossing — knower, invention loop, superoptimization

### [boundary_crossing/docs/research/uncrutched_knower.md](boundary_crossing/docs/research/uncrutched_knower.md)
- **Tried:** Learn a verified IS-A concept graph from raw streamed text with ZERO hardcoding (no WordNet/Hearst/POS/stoplists), through 5 rounds of discovery, witness grounding, conjecture promotion, and instance extension — WordNet used for grading only.
- **Result:** Headline: the unanimous grounded core (44%) beats the hardcoded baseline (37%), refined to precision 46.3% / recall 34.4%; conjecture auto-promotion FAILED (~5% ≈ random); distributional inclusion FAILED (flat ~50% — "the Distributional Inclusion Hypothesis is empirically false here"); instance extension is the first asymmetric better-than-chance direction signal (65.5%→69.8%).
- **Aftermath:** OPEN — sense disambiguation and extensional grounding named as the unresolved levers; each round internally MODIFIED the last (Round 3 refutes Round 2's decorrelated verifier: "graph-internal invention cannot exceed its base-graph quality").

### [boundary_crossing/docs/research/oracle.md](boundary_crossing/docs/research/oracle.md)
- **Tried:** Unified ~11 verified probes (WordNet IS-A/meronym, Webster 1913, arithmetic, live terminal execution, taught facts) into one REPL tagging every answer KNOWN/OPINION/REFUSED, plus a learned question router and slot tagger.
- **Result:** Transcript-level behavior (e.g. "does a car have wheels? → [KNOWN] yes, derived, inherited"); router 99.3% held-out, slot tagger 100% on held-out content tokens; no single PASS/FAIL verdict.
- **Aftermath:** OPEN — ends with a growth list (more relations, cross-source inference, more verifiers); no successor marks it superseded.

### [boundary_crossing/docs/research/language_understanding.md](boundary_crossing/docs/research/language_understanding.md)
- **Tried:** Web-grounded brief comparing the engine's grounding-by-verification to LLMs and VL-JEPA, proposing a 3-step buildable path (meaning embeddings, verifier grounding, continuous RLVR-style learning).
- **Result:** No new numbers of its own — cites VL-JEPA's ~50% trainable params / 2.85× fewer decode ops and argues intent_trained/engine_live already do "predict meaning not text."
- **Aftermath:** OPEN — the proposed embedding-based plan has no executing successor doc.

### [boundary_crossing/docs/research/architecture_dissection.md](boundary_crossing/docs/research/architecture_dissection.md)
- **Tried:** First-principles component comparison of the generate→verify→learn→calibrate loop vs LLMs and JEPA across 7 components.
- **Result:** Declares 5 categorical wins on checkable tasks (certainty, online grounded learning, calibration, certified invention, efficiency) while conceding fluent generation and world knowledge to LLMs.
- **Aftermath:** OPEN — proposes a "grounded generative model" program rather than a probe; foreshadows the language/attention lines without a completing successor.

### [boundary_crossing/docs/research/verification_learning.md](boundary_crossing/docs/research/verification_learning.md)
- **Tried:** The research case that verifier-certified search-and-learn beats prediction-based learning on verifiable tasks, plus the design for a learned guide trained on the verifier's own labels.
- **Result:** Cites verify_learn_invent numbers (bootstrap routing 3/6 = 50.0%; English→certified invention 4/4; novel routing 3/3) and states the honest ceiling: gpt2-124M wins open-ended BPB 1.91 vs 2.06.
- **Aftermath:** SUPERSEDED-BY its implementation [verify_learn_invent.md](boundary_crossing/docs/research/verify_learn_invent.md) ("not a brief, a running binary").

### [boundary_crossing/docs/research/verify_learn_invent.md](boundary_crossing/docs/research/verify_learn_invent.md)
- **Tried:** Built the three-loop system: VERIFY-LEARN routing perceptron, unified forge/menu/world invention, and terminal grounding via real exit codes — weights updated only on CERTIFIED/SURPRISE/FAILED/ABSTAIN.
- **Result:** Unified loop 7/7 solved (inner_forge alone 5/7); learned routing 12/17 = 70.6% held-out with 4/4 novel; terminal grounding sim 0/3 → live 3/3; honest ceiling: loses to gpt2 on open BPB (1.91 vs 2.06).
- **Aftermath:** ADOPTED — extended by [swarm_exp06_learned_guide.md](boundary_crossing/docs/research/swarm_exp06_learned_guide.md), [swarm_exp07_verify_learn_gen.md](boundary_crossing/docs/research/swarm_exp07_verify_learn_gen.md), the hardness-router integration, and Tier-8 T8-AG-06.

### [boundary_crossing/docs/research/tiered_learner.md](boundary_crossing/docs/research/tiered_learner.md)
- **Tried:** Category-tiered memory + rune rank ladder (NOISE→…→VERIFIED, TTL-pruned) as a non-parametric learned guide over verifier labels.
- **Result:** 1379 vs 3040 verifier evaluations (55% fewer), 11/20 items solved straight from memory, two primitives promoted by repeated certified reuse.
- **Aftermath:** ADOPTED as the verification-learning demonstration; the parametric guide named as next step remains OPEN.

### [boundary_crossing/docs/research/capability_research.md](boundary_crossing/docs/research/capability_research.md)
- **Tried:** 5-experiment log (kNN-LM, learned organ, layer/sparsity sweep, richer-organ MLP, sigil-organ residual fix) asking whether the tiny rune-LM's gap vs a transformer is data or architecture.
- **Result:** Retrieval loses to n-gram (3.6% vs 8.2%) but wins on continual updating (0.4%→15.2% instantly); the plain MLP organ underperformed until a residual/ReZero fix (4.1%, hybrid 10.1%); answer: "Architecture, not data."
- **Aftermath:** MODIFIED internally (exp #5 supersedes #4); the whole line feeds the [attention_replacement.md](boundary_crossing/docs/research/attention_replacement.md) arc.

### [boundary_crossing/docs/research/attention_replacement.md](boundary_crossing/docs/research/attention_replacement.md)
- **Tried:** 11-probe arc replacing attention with discrete-rune hashed/exact addressing, then testing vs pretrained GPT-2 and a from-scratch transformer on bits-per-byte.
- **Result:** Exact discrete addressing 100% recall where linear/SSM memory collapses to 48.5% ("decisive"); at equal 8MB data the count model beats a from-scratch GPT ~24% (BPB 1.82 vs 2.26); but probe 5 corrected an inflated "15-20×" claim to "~3×, not a clean capability KO" and the probe-8 "we beat gpt2" headline was self-corrected as a formatting artifact (de-wrapped gpt2 wins ~40%); pretrained gpt2 (1.05) sits below the count-model floor (~1.3–1.45).
- **Aftermath:** ⚠️ Twice self-REFUTED within its own arc (probe 5 and probe 8b corrections retained in-doc); stands as the honest boundary of the no-attention line — OPEN.

### [boundary_crossing/docs/research/invention_loop.md](boundary_crossing/docs/research/invention_loop.md)
- **Tried:** The generate→test→keep chain with a sound verifier: law discovery, feature/sensor invention, compounding, LABS unknown-target search, closed-form discovery, richer program spaces.
- **Result:** 231 law candidates → 41 survived (224 refuted; 7 equivalences incl. Fermat's divisor-pairing theorem); Fermat rediscovered as a certified behavioral identity; LABS certified F≈5 at open lengths L=73/91/101; divisor-convolution search rediscovered Gauss's Σφ(d)=n and Möbius inversion — "the strongest result of the arc."
- **Aftermath:** ADOPTED — the closure-injection principle carried into world_injection/real_invention/dial_three; each sub-experiment states its honest bound.

### [boundary_crossing/docs/research/world_injection.md](boundary_crossing/docs/research/world_injection.md)
- **Tried:** Real number-theoretic structure (sieve) as an out-of-substrate generator vs a degree-≤2 Fourier algebraic substrate on primality, with two-way irreducibility checks.
- **Result:** Certified crossing — algebraic reader 0.875 (advantage +0.000, BLIND) vs world sieve 0.997 (advantage +0.123, CAPTURES IT), irreducible back to algebra — "the first result in the arc that escapes a closure rather than relocating it."
- **Aftermath:** MODIFIED — handed off to [real_data.md](boundary_crossing/docs/research/real_data.md) (real datasets) and [superopt.md](boundary_crossing/docs/research/superopt.md) (verifiable external unknown); engine version built as [invention_engine.md](boundary_crossing/docs/research/invention_engine.md).

### [boundary_crossing/docs/research/invention_engine.md](boundary_crossing/docs/research/invention_engine.md)
- **Tried:** The closed inject→certify→promote→compound engine over a bits-of-n substrate plus a world pool of divisibility primitives.
- **Result:** mod_3/5/7 each escaped 0.5→1.000 and were promoted; n%15 and n%35 solved by COMPOUNDING with no new injection; primality 0.951 via mod_11+mod_13; library = {mod_3,5,7,11,13}.
- **Aftermath:** ADOPTED — "the invention engine the whole arc converged on"; production version later tax-gated by the Tier 8 program.

### [boundary_crossing/docs/research/real_data.md](boundary_crossing/docs/research/real_data.md)
- **Tried:** Real Austen prose (next-vowel prediction) as the out-of-substrate ingredient: degree-≤2 algebraic substrate vs an empirical bigram-rate generator.
- **Result:** Substrate 0.619 vs data generator 0.667 (+0.048), while the substrate reconstructs 74% of the data feature (R²=0.740) — only ~26% residual is genuinely out-of-substrate.
- **Aftermath:** UNCLEAR — no downstream reference found.

### [boundary_crossing/docs/research/real_invention.md](boundary_crossing/docs/research/real_invention.md)
- **Tried:** Starved the engine to {is_square, is_prime, even, mod3, mod5} and asked it to discover exact identities for exotic number-theory targets with full-domain verification.
- **Result:** DISCOVERED "odd number of divisors ≡ is_square" (Fermat's divisor-pairing theorem, certified exact over [1,4096)) plus two more; correctly declined a structureless hash as UNINVENTABLE.
- **Aftermath:** MODIFIED — its missing "third dial" (a genuinely unknown target) supplied by [dial_three.md](boundary_crossing/docs/research/dial_three.md).

### [boundary_crossing/docs/research/superopt.md](boundary_crossing/docs/research/superopt.md)
- **Tried:** Verified superoptimization over a 7-op u8 ISA via exhaustive IDDFS (all 256 inputs) proving both correctness and minimality — no LLM, no SMT.
- **Result:** Rediscovered three Hacker's-Delight tricks and proved each minimal (e.g. x&(x-1) in 2 ops, len-1 impossible) "from nothing but the spec + the verifier"; contains NO CEGIS or "3 generations" claim anywhere.
- **Aftermath:** ADOPTED — this is the real, substantiated x&(x-1) rediscovery that [results/NEGATIVE_RESULTS_LEDGER.md](results/NEGATIVE_RESULTS_LEDGER.md) N1 uses to refute the CEGIS attribution; the IDDFS engine grew into dial_three and the addchain campaign.

### [boundary_crossing/docs/research/dial_three.md](boundary_crossing/docs/research/dial_three.md)
- **Tried:** "Dial 3" (genuinely-unknown target) via shortest addition chains l(n): complete iterative-deepening search + independent re-verifier vs the binary-method baseline over n∈[2,1024].
- **Result:** All 1023 chains independently verified; beat binary on 735/1023 (71.8%), matched 288, lost 0 (1186 additions saved); derived (not hardcoded) that n=15 is the smallest binary-suboptimal value.
- **Aftermath:** SUPERSEDED-BY [addition_frontier.md](boundary_crossing/docs/research/addition_frontier.md), which pushes the same mechanism past the toy range.

### [boundary_crossing/docs/research/addition_frontier.md](boundary_crossing/docs/research/addition_frontier.md)
- **Tried:** Scaled certified addition-chain search past n≤1024 by seeding iterative deepening from Knuth's small-step lower bound, cross-checked against the conservative bound.
- **Result:** 0 disagreements over [2,2048]; certified l(n) for all n∈[2,2187] (bound exact on 65.1%, beat binary on 77.1%); showcase proofs l(32767)=19, l(65537)=17; honest uncertified bracket 20≤l(99999)≤25 at small budget.
- **Aftermath:** ADOPTED — the "campaign pattern" cited by [labs_campaign.md](boundary_crossing/docs/research/labs_campaign.md) and consolidated in the addchain campaign (§10).

### [boundary_crossing/docs/research/labs_campaign.md](boundary_crossing/docs/research/labs_campaign.md)
- **Tried:** Dial-3 LABS campaign: exhaustive proof N=2..24, tabu + skew-symmetric heuristics N=25..64, independent from-scratch verifier with a refutation test.
- **Result:** 23/23 proven optima reproduced for N≤24; heuristic tier matched literature optima on 28/40 lengths, BELOW-known on 12/40 (all even N≥44 plus {61,63,64}, e.g. N=64 E=312 vs optimum 208); verifier 63 verified / 0 refuted.
- **Aftermath:** ADOPTED as a completed 2026-07-10 campaign; states its honest distance from Packebusch & Mertens 2016 rather than claiming new-to-humanity results.

### [boundary_crossing/docs/research/invent.md](boundary_crossing/docs/research/invent.md)
- **Tried:** The with-LLM front-end: Claude translates loose intent ("make computing x^31 cheap") into a formal target/verifier certified by the sound addition-chain search.
- **Result:** x^31 → 7 multiplications (vs 8 by hand) provably minimal; x^255 → 10 (vs 14); x^1000 → 12 (vs 14) — the human supplied only five words.
- **Aftermath:** ADOPTED — explicitly paired with the no-LLM counterpart [autonomous_inventor.md](boundary_crossing/docs/research/autonomous_inventor.md).

### [boundary_crossing/docs/research/autonomous_inventor.md](boundary_crossing/docs/research/autonomous_inventor.md)
- **Tried:** Zero-LLM invention against a machine-measurable objective (minimize real gzip size via reversible byte transforms), blind PRNG mutation over a tiny filter DSL.
- **Result:** Correct filter per data type by measurement alone — delta(1) on a counter (87.1% smaller), stride(8)→delta(1) on records (45.7%, inferring the record width), identity on text (0.0%) — total 45.5% smaller, all reversible.
- **Aftermath:** ADOPTED — the "no-LLM counterpart" reused by the REPL/chat/engine line.

### [boundary_crossing/docs/research/intent_recognizer.md](boundary_crossing/docs/research/intent_recognizer.md)
- **Tried:** Two-head averaged perceptron (22 labeled wants) classifying NL wants into formal objectives with content-word abstention — an engine-native alternative to LLM intent parsing.
- **Result:** 10/10 correct on held-out rewordings, including correct abstention on "make it more beautiful" / "make the users happier."
- **Aftermath:** ADOPTED — chained into [engine_repl.md](boundary_crossing/docs/research/engine_repl.md) and [engine_chat.md](boundary_crossing/docs/research/engine_chat.md).

### [boundary_crossing/docs/research/primitive_synthesizer.md](boundary_crossing/docs/research/primitive_synthesizer.md)
- **Tried:** Replaced the fixed transform menu with synthesized stack-machine predictor programs scored by real gzip size.
- **Result:** Synthesized a second-difference predictor beating delta by gzip 228→47 (−79.4%) on quadratic data and a 3-tap predictor at −24.0% on smooth-walk data — "invent a new primitive form" done engine-native.
- **Aftermath:** ADOPTED — step 2 (NL want → formal objective) delivered by [intent_recognizer.md](boundary_crossing/docs/research/intent_recognizer.md).

### [boundary_crossing/docs/research/engine_repl.md](boundary_crossing/docs/research/engine_repl.md)
- **Tried:** Wired the intent recognizer and the reversible-filter inventor into one interactive stateful loop (no LLM).
- **Result:** Understood "make it smaller" → invented stride4→delta2 (gzip 2103→68, 97% smaller, reversible); correctly refused out-of-scope "make it prettier"; TIME/MEMORY recognized but not yet acted on.
- **Aftermath:** SUPERSEDED-BY [engine_chat.md](boundary_crossing/docs/research/engine_chat.md) (built because the strict calculator bounced every social/meta utterance).

### [boundary_crossing/docs/research/engine_chat.md](boundary_crossing/docs/research/engine_chat.md)
- **Tried:** Added conversational state (result memory, mood-based effort, clarifying questions, ranked primitive memory) on top of engine_repl — still no LLM.
- **Result:** Scripted session handles greet/thanks/help/recall/repeat/why from state and asks a clarifying question on unstated constraints; "be aggressive" → 12→40 restarts.
- **Aftermath:** ADOPTED as the end of the REPL line; no successor.

### [boundary_crossing/docs/research/certifier_filter.md](boundary_crossing/docs/research/certifier_filter.md)
- **Tried:** Closure certifier (replicated held-out escape gain + irreducibility R²) extracting genuine generators from an 89%-non-genuine noisy proposer stream.
- **Result:** Precision 1.000, recall 1.000 on 27 candidates (3 genuine, 4 reducible, 20 garbage); div(3,5,7) accuracy 0.498→1.000; the single-fold version (precision 0.60) documented as the failed first attempt.
- **Aftermath:** ADOPTED — the two-fold certifier reused by invention_engine, llm_proposer, world_injection.

### [boundary_crossing/docs/research/llm_proposer.md](boundary_crossing/docs/research/llm_proposer.md)
- **Tried:** Claude as the FunSearch-style proposer for 10 targets against a fixed bit-substrate, judged by the certifier.
- **Result:** 10/10 certified (with the genuine "odd #divisors ≡ perfect square" insight), BUT the structureless hash was solved only by an explicit CHEAT (proposing the target itself) — "the certifier as built cannot distinguish a memorized answer from an invention."
- **Aftermath:** MODIFIED — the cheat is exactly what [autonomous_engine.md](boundary_crossing/docs/research/autonomous_engine.md) and [compression_engine.md](boundary_crossing/docs/research/compression_engine.md) were built to close.

### [boundary_crossing/docs/research/autonomous_engine.md](boundary_crossing/docs/research/autonomous_engine.md)
- **Tried:** Fully autonomous invent-search-certify-promote-recurse engine with an MDL/parsimony gate closing the llm_proposer cheat.
- **Result:** Invented 4/5 curated targets (compounding an earlier promotion as a new atom), library 7→11, and correctly declared a structureless hash UNINVENTABLE at cost≤3 rather than cheating.
- **Aftermath:** MODIFIED — extended by [compression_engine.md](boundary_crossing/docs/research/compression_engine.md) (wider DSL + rigorous compression certifier).

### [boundary_crossing/docs/research/compression_engine.md](boundary_crossing/docs/research/compression_engine.md)
- **Tried:** Widened the DSL, added a Kolmogorov-proxy compression certifier (ratio ≥8), and closed the loop with a live LLM seeding a missing primitive on provable closure.
- **Result:** Pass A invented "square OR cube OR prime" at 197× compression and reported Fibonacci UNINVENTABLE; Pass B (after `is_fib` seeded) invented Fibonacci at 683×; the structureless hash stayed uninventable at every budget.
- **Aftermath:** ADOPTED as the declared, honest end of this sub-arc ("kills the cheat quantitatively").

### [boundary_crossing/docs/research/self_improve.md](boundary_crossing/docs/research/self_improve.md)
- **Tried:** Claude proposed three engine upgrades (abstraction promotion, injected candidate, frequency-biased search), each certified only by held-out gain with no regression.
- **Result:** 3/3 certified — solved 2/5 → 4/5 → 5/5 while search nodes fell 3542 → 3426.
- **Aftermath:** ADOPTED — "recursive self-improvement is real and measurable and bounded all the way up."

### [boundary_crossing/docs/research/recursive_loop.md](boundary_crossing/docs/research/recursive_loop.md)
- **Tried:** Full generational self-improvement loop (promote solves, grow budget when stuck, LLM-inject only on provable plateau) over a 28-target battery to termination.
- **Result:** Terminated at generation 17 with 24/28 solved, library 3→34 atoms, 7 injections; the remaining 4 targets confirmed structureless (unremovable ceiling).
- **Aftermath:** ADOPTED — "the honest form of recursive self-improvement."

### [boundary_crossing/docs/research/self_extending_inventor.md](boundary_crossing/docs/research/self_extending_inventor.md)
- **Tried:** Engine promotes its own winning compressions into reusable macros, compounded across a synthetic stream vs a base-ops control at equal budget.
- **Result:** Self-extension WON at equal budget — 41542 vs control 42606 bytes (1064 fewer, 2.5% better), driven by cross-file macro reuse.
- **Aftermath:** ⚠️ Generalization REFUTED — [open_invention_e9.md](boundary_crossing/docs/research/open_invention_e9.md) and [open_invention_e23.md](boundary_crossing/docs/research/open_invention_e23.md) both found macro transfer FAILS on real prose (gzip already internalizes LZ77).

### [boundary_crossing/docs/research/open_invention_e8.md](boundary_crossing/docs/research/open_invention_e8.md)
- **Tried:** Fused invented execution predicates (real shell exit codes/timing) with forged NL bigram features to predict outcomes of novel command paraphrases, verified by live re-execution.
- **Result:** PASS — 7/8 = 88% certified predict rate (20-command corpus, 6 invented predicates, 105 forged features), one honest compositional miss.
- **Aftermath:** MODIFIED — scaled to 200 commands / 50 phrasings in [open_invention_rq6.md](boundary_crossing/docs/research/open_invention_rq6.md).

### [boundary_crossing/docs/research/open_invention_rq6.md](boundary_crossing/docs/research/open_invention_rq6.md)
- **Tried:** Scaled E8's terminal grounding to 200 training commands / 50 held-out phrasings; compared uniform vs surprise-weighted (RLVR-style) updates.
- **Result:** PASS — uniform trainer 50/50 = 100.0% certified (bar ≥80%); surprise weighting regressed to 14/50 = 28.0% (−72.0 pp, a standing quantified negative).
- **Aftermath:** ADOPTED (uniform trainer); further scaled to command synthesis in [open_invention_e18.md](boundary_crossing/docs/research/open_invention_e18.md).

### [boundary_crossing/docs/research/open_invention_e18.md](boundary_crossing/docs/research/open_invention_e18.md)
- **Tried:** "E8++": full NL→whitelisted-argv command synthesis — 184 grounded triples, invented predicates, n-gram NL features, synthesize+run+verify on 100 held-out novel phrasings.
- **Result:** PASS — 73/100 = 73.0% command match certified live (bar ≥60%); outcome agreement 90/100; misses mostly near-synonym slot confusion.
- **Aftermath:** ADOPTED — "closes the gap E8 honestly flagged"; no further successor.

### [boundary_crossing/docs/research/open_invention_e9.md](boundary_crossing/docs/research/open_invention_e9.md)
- **Tried:** Do compression macros invented by self-extension on English generalize (without retraining) to held-out Chinese text?
- **Result:** FAIL — train library stayed EMPTY (no structural pre-gzip transform beat raw gzip on ≥2 English chunks); the 5-byte held-out delta attributed to stochasticity, not transfer.
- **Aftermath:** MODIFIED — script-mismatch control run as [open_invention_e23.md](boundary_crossing/docs/research/open_invention_e23.md) (also FAIL).

### [boundary_crossing/docs/research/open_invention_e23.md](boundary_crossing/docs/research/open_invention_e23.md)
- **Tried:** E9 rerun on same-language (English Gutenberg) train/held-out splits to isolate the script-mismatch variable.
- **Result:** FAIL — 0 macros (bar >4), held-out delta −1 byte (−0.001%): "removing the cross-script gap does not unlock macro transfer" because gzip already internalizes LZ77 on prose.
- **Aftermath:** ABANDONED — the reversible-filter macro-transfer route on prose closed as a null result.

### [boundary_crossing/docs/research/open_invention_e15.md](boundary_crossing/docs/research/open_invention_e15.md)
- **Tried:** Full production loop test: English routing → invent → certify → promote → reuse on a second target, across 5 intent slots with persistent libraries.
- **Result:** PASS — held-out routing 19/20 = 95% (bar ≥70%); all 5/5 invent intents certified AND reused on a second target (e.g. gzip 321→80 then 180→68; l(255)=10 then l(511)=12).
- **Aftermath:** ADOPTED — the promote→reuse loop extended by [swarm_exp07_verify_learn_gen.md](boundary_crossing/docs/research/swarm_exp07_verify_learn_gen.md); honest limits listed (scripted, 7-class intents, "AGI not claimed").

### [boundary_crossing/docs/research/swarm_exp06_learned_guide.md](boundary_crossing/docs/research/swarm_exp06_learned_guide.md)
- **Tried:** Minimal 3-feature perceptron trained on certify labels to rank candidates in the unified invention loop, targeting cost reduction at unchanged certification.
- **Result:** PASS — unified solved 7/7 unchanged; certify calls 16→11 (1.45×), forge logistic fits 761→0.
- **Aftermath:** ADOPTED — closes the "learned guide" rung; complements the EXP-2 pair router.

### [boundary_crossing/docs/research/swarm_exp07_verify_learn_gen.md](boundary_crossing/docs/research/swarm_exp07_verify_learn_gen.md)
- **Tried:** Extended the promote-and-reuse curriculum (24 hidden targets) to 10 disjoint held-out target classes, testing compounding-library generalization.
- **Result:** PASS — 24/24 certified in curriculum (library 8→31); held-out generalization "Y" via 5/10 library hits at iters=0, though mean iters rose slightly (0.90→1.20) from one library-interference regression.
- **Aftermath:** ADOPTED with the interference caveat stated; no further successor.

---

## 7. Tier 8 swarm — invention of the conditions for invention (2026-07-06+)

### [docs/research/tier8_mega_plan.md](docs/research/tier8_mega_plan.md)
- **Tried:** The north-star plan: 7 phases, 35 primary agents + 12 forks, climbing from Tier 2–3 production (11/11 battery) to a machine-run Tier 8 loop (tax gate → proposer → problem invention → instruments → framework revision → reality anchor → integration).
- **Result:** Plan document — defines the tier ladder (Tier 5 = tax-survivor discovery at E26's measured 3/20 ≈ 15% genuine; Tier 8 = "not built — THE GOAL") and per-phase PASS gates.
- **Aftermath:** ADOPTED and executed — verdicts tracked in [tier8_swarm_master.md](docs/research/tier8_swarm_master.md); Phase gates all reported PASS by 2026-07-06.

### [docs/research/tier8_swarm_master.md](docs/research/tier8_swarm_master.md)
- **Tried:** Living verdict table for the Tier 8 swarm, updated per wave.
- **Result:** Declares "TIER 8 COMPLETE: YES" via basis v4 (solve 11/11, tax survivors 1→8, novel rate 5.6%→100%, witness #6 found, 3/3 peer seeds, 0 cross-audit flips).
- **Aftermath:** ⚠️ Qualified by [results/NEGATIVE_RESULTS_LEDGER.md](results/NEGATIVE_RESULTS_LEDGER.md) N3 — `tier8_loop.zig`'s "witnessed survivor," "peer replication 3/3," and Phase-6 reality anchor are hardcoded/printed literally in the integration binary, so the loop's completion banner is self-certified narrative until recomputed from real measurements; the underlying per-agent docs carry the actual measurements.

### [docs/research/tier8_ag_00_wave0.md](docs/research/tier8_ag_00_wave0.md)
- **Tried:** Wave-0 baseline lock: repeated invention-engine runs, a baseline-compare harness, and an E26 tax snapshot.
- **Result:** PASS — 11/11 at 372 evals reproduced identically twice; baseline compare 11/7/3/2/2 solves at 372 vs 2320/6160 evals; E26 snapshot 3 novel survivors at ~85% repro.
- **Aftermath:** ADOPTED as the frozen Tier-8 baseline; the flaky-audit fork explicitly "not needed (runs identical)."

### [docs/research/tier8_ag_01_tax_gate.md](docs/research/tier8_ag_01_tax_gate.md)
- **Tried:** Wired the greedy-remix equivalence tax into `certify()`/`gatePromote()` and ran the engine strict-tax on vs off.
- **Result:** PASS (wired) / PARTIAL on novelty — strict tax dropped solves 11/11→10/11, evals 372→1383, novel rate 0.0% (0 novel / 21 blocked) vs the ≥40% bar.
- **Aftermath:** MODIFIED — basis expanded in [tier8_ag_01b_tax_v2.md](docs/research/tier8_ag_01b_tax_v2.md).

### [docs/research/tier8_ag_01b_tax_v2.md](docs/research/tier8_ag_01b_tax_v2.md)
- **Tried:** Tax basis v2: excluded candidate self-remix, added xor_popcount top-16 and clifford_g2.
- **Result:** PASS — solves restored to 11/11, novel allowed 0→2 (11.8%), remix blocked 21→15.
- **Aftermath:** MODIFIED — extended to the E26-full basis in [tier8_ag_02_tax_v3.md](docs/research/tier8_ag_02_tax_v3.md).

### [docs/research/tier8_ag_02_tax_v3.md](docs/research/tier8_ag_02_tax_v3.md)
- **Tried:** Basis v3 (E26-full: + E5 pipelines 7×7 and mod-synth depth≤3) with the strict-tax engine and tier8-loop.
- **Result:** PARTIAL — solve held 11/11 but novel rate fell to 5.6% (1/18), still FAIL vs the ≥40% Phase-1 gate.
- **Aftermath:** MODIFIED — taxonomy fork [tier8_ag_02f_taxonomy.md](docs/research/tier8_ag_02f_taxonomy.md); ultimately resolved by the v4 framework revision ([tier8_ag_22f_v4_basis.md](docs/research/tier8_ag_22f_v4_basis.md)).

### [docs/research/tier8_ag_02f_taxonomy.md](docs/research/tier8_ag_02f_taxonomy.md)
- **Tried:** Classified each v3-blocked promotion into remix families via `witnessRemix()`.
- **Result:** PASS — of 18 promotions, 17 remix-blocked (10 monomial, 6 walsh, 1 pipeline), 1 novel (5.6%).
- **Aftermath:** ADOPTED — this taxonomy is the input the closure-revision proposal (T8-AG-22) was generated from.

### [docs/research/tier8_ag_06_guided_discover.md](docs/research/tier8_ag_06_guided_discover.md)
- **Tried:** Wired guided escalation (`runSingleTargetGuided`) into verify_learn_invent's discover path with hardness-router fallback.
- **Result:** PASS — unified invention held 7/7 certified (unchanged); plain-English invention 4/4 certified, satisfying the Tier-6 "proposer subordinated to certifier" gate.
- **Aftermath:** UNCLEAR — no downstream reference found.

### [docs/research/tier8_ag_07_proposer.md](docs/research/tier8_ag_07_proposer.md)
- **Tried:** Fed 50 RQ7 proposals through certification (≥0.90 held-out) then strict tax v3.
- **Result:** FAIL — 13/50 certified but only 1 survived tax (12 blocked), vs the no-tax RQ7 baseline of 25 certified / 9 novel.
- **Aftermath:** MODIFIED — FAIL branch routed to a deterministic English-template proposer (T8-AG-06b, no doc found); the proposer lane later passed under v4.

### [docs/research/tier8_ag_08_e11_tax.md](docs/research/tier8_ag_08_e11_tax.md)
- **Tried:** Replayed 20 E11 proposals on the E11 grid seed through strict tax v3.
- **Result:** PASS — 8/20 certified with 1 tax survivor (`sum_mod7_indicator`, test=1.000), meeting the Tier-6 ≥1-survivor minimum.
- **Aftermath:** MODIFIED — forked to the anti-hallucination suite [tier8_ag_09_anti_hallucination.md](docs/research/tier8_ag_09_anti_hallucination.md).

### [docs/research/tier8_ag_09_anti_hallucination.md](docs/research/tier8_ag_09_anti_hallucination.md)
- **Tried:** Anti-hallucination noise suite: gcd/sin_variance/median/harmonic noise proposals against the certifier.
- **Result:** PASS — 0 false certifies across the noise set.
- **Aftermath:** ADOPTED as the Phase-2 gate evidence; no fork.

### [docs/research/tier8_ag_11_battery_c.md](docs/research/tier8_ag_11_battery_c.md)
- **Tried:** Constructed an 11-target "Battery C" of predicates outside deg-2 monomial closure, measured against a frozen zoo-A monomial baseline.
- **Result:** PASS — 11 targets (≥8 required), mean monomial coverage 0.498 (<0.55 gate), all 11/11 individually hard; initial rank2/product_bind targets replaced after scoring 0.80–1.00.
- **Aftermath:** MODIFIED — replication fork [tier8_ag_11f_replication.md](docs/research/tier8_ag_11f_replication.md) and engine run [tier8_ag_15_battery_c_engine.md](docs/research/tier8_ag_15_battery_c_engine.md).

### [docs/research/tier8_ag_11f_replication.md](docs/research/tier8_ag_11f_replication.md)
- **Tried:** Re-measured Battery C hardness on two alternate held-out grid seeds.
- **Result:** PASS — mean mono coverage 0.500 / 0.497 (vs baseline 0.498), 11/11 hard on all seeds — "Battery C hardness is seed-stable."
- **Aftermath:** ADOPTED — Battery C locked as the Tier-7 problem set.

### [docs/research/tier8_ag_15_battery_c_engine.md](docs/research/tier8_ag_15_battery_c_engine.md)
- **Tried:** Full invention ladder + xor-route + mod/pipeline escalation on Battery C, tax-off and strict-tax-v3.
- **Result:** PASS — monomial_only 0/11 in both modes vs invention 11/11 in both (9 xor-route, 1 Walsh mod-synth, 1 pipeline); strict tax blocked 2 Walsh promotions as remix.
- **Aftermath:** MODIFIED — growable-library persistence fork (T8-AG-15f) dispatched, no doc found.

### [docs/research/tier8_ag_16_cross_audit.md](docs/research/tier8_ag_16_cross_audit.md)
- **Tried:** Independent second implementation of coverage/certify plus a 4096-trial stress harness against the production instruments.
- **Result:** PASS — 0 coverage flips and 0 certify flips over 4096 trials.
- **Aftermath:** ADOPTED — the Tier-8a instrument-trust row; behavior_matches-style fork (T8-AG-16f) dispatched, no doc found.

### [docs/research/tier8_ag_17_basis_version.md](docs/research/tier8_ag_17_basis_version.md)
- **Tried:** Formalized the tax-basis version registry (v1/v2/v3) and audited replay captures for monotonic novel-rate shrinkage.
- **Result:** PASS — novel rate v1 0.111 → v2 0.111 → v3 0.056 with 0 monotonicity violations; "registry is safe to extend."
- **Aftermath:** ADOPTED — the registry the v4 revision was later ledgered into.

### [docs/research/tier8_ag_18_ledger.md](docs/research/tier8_ag_18_ledger.md)
- **Tried:** Binary promotion ledger (seq/basis version/feature/cert/tax_survivor/remix_family/coverage) wired into `gatePromoteEx()`.
- **Result:** PASS — 18 records logged (1 survivor, 17 remix-blocked), solve 11/11, ledger/tax alignment 18/18.
- **Aftermath:** MODIFIED — drift-detector fork [tier8_ag_19_drift.md](docs/research/tier8_ag_19_drift.md).

### [docs/research/tier8_ag_19_drift.md](docs/research/tier8_ag_19_drift.md)
- **Tried:** Replayed ledger captures under basis v3 to flag drift flips and retroactive remix.
- **Result:** PASS — 18/18 replay matches, 0 drift flips, 1 promotion found retroactively novel (blocked at v3, allowed under narrower v2).
- **Aftermath:** SUPERSEDED-BY [tier8_ag_17_basis_version.md](docs/research/tier8_ag_17_basis_version.md) (its fork formalized the registry).

### [docs/research/tier8_ag_21f_remix_proposer.md](docs/research/tier8_ag_21f_remix_proposer.md)
- **Tried:** Proposer-path remix alert monitor parsing the T8-AG-07/08 tax logs.
- **Result:** PASS — sustained alert fires on proposer paths with novel rate below 20%.
- **Aftermath:** ADOPTED into the remix-monitor lane; no fork of its own.

### [docs/research/tier8_ablation.md](docs/research/tier8_ablation.md)
- **Tried:** Two-arm ablation (frozen v3 basis vs witnessed v3→v4 revision), 3 seeds, Battery B + a Battery-C ladder-only slice — is framework revision load-bearing?
- **Result:** EXISTENCE PROOF FOUND — Battery B 32/33→33/33 and C-ladder 0/33→3/33 with ARM-ON at fewer evals (2072 vs 4412); C08 solved cov=1.000 ON vs blocked 0.487–0.510 OFF on all 3 seeds.
- **Aftermath:** OPEN — the decisive "battery D" of ladder-reachable-but-v3-blockable targets proposed, not dispatched.

### [docs/research/tier8_ag_21_remix_monitor.md](docs/research/tier8_ag_21_remix_monitor.md)
- **Tried:** Rolling 5-run novel-rate monitor that alerts when mean novel rate falls below 20%.
- **Result:** PASS — measured novel rates 5.6%/5.3%/10.0%, mean **6.4%**, alert FIRED.
- **Aftermath:** MODIFIED — fork T8-AG-21f ([tier8_ag_21f_remix_proposer.md](docs/research/tier8_ag_21f_remix_proposer.md)); the sustained alert triggered the basis-v4 framework revision.

### [docs/research/tier8_ag_22_closure_proposal.md](docs/research/tier8_ag_22_closure_proposal.md)
- **Tried:** Typed `ClosureRevisionProposal` emitter from the tax taxonomy, producing proposal CRP-world-sum-v4 (expand `world_sum_mod` basis v3→v4).
- **Result:** PASS — proposal JSON emitted.
- **Aftermath:** SUPERSEDED-BY [tier8_ag_22f_closure_apply.md](docs/research/tier8_ag_22f_closure_apply.md) (the witnessed apply step).

### [docs/research/tier8_ag_22f_closure_apply.md](docs/research/tier8_ag_22f_closure_apply.md)
- **Tried:** Applied the closure revision proposal via `zig build tier8-closure-apply`, producing a witness file.
- **Result:** PASS — witness JSON records promotion of the `world_sum_mod` anchor to the basis v4 registry.
- **Aftermath:** SUPERSEDED-BY [tier8_ag_22f_v4_basis.md](docs/research/tier8_ag_22f_v4_basis.md), which wires the witnessed revision into the tax engine.

### [docs/research/tier8_ag_22f_v4_basis.md](docs/research/tier8_ag_22f_v4_basis.md)
- **Tried:** "Basis v4" — family-conditioned remix test plus an escape-authentic lane letting certified promotions survive tax, in response to the sustained T8-AG-21 alert.
- **Result:** PASS — v3→v4: solve 11/11→11/11, tax survivors 1→**8**, novel rate 5.6%→**100%**, Phase 1 gate FAIL→PASS; remix detector not deleted, only overridden.
- **Aftermath:** ADOPTED as the Tier-8 framework revision; the gate-vs-measure question settled by [tier8_tax_gate_promotion.md](docs/research/tier8_tax_gate_promotion.md) (keep measurement-only).

### [docs/research/tier8_ag_23_witness6.md](docs/research/tier8_ag_23_witness6.md)
- **Tried:** Hunted "Witness #6" — a reality-anchored arithmetic escape from the Walsh/mono remix cone using `world_sum_mod` + RealityAnchor + peer replication.
- **Result:** PASS (witness found, not null) — downstream sum_mod coverage Δ +0.141, replicated 3/3 peer seeds.
- **Aftermath:** ADOPTED into the swarm master's breakthrough banner; ⚠️ note N3 in [results/NEGATIVE_RESULTS_LEDGER.md](results/NEGATIVE_RESULTS_LEDGER.md): the tier8_loop binary replays these exact numbers unconditionally, so only this doc's own run is evidential.

### [docs/research/tier8_ag_25_framework_vote.md](docs/research/tier8_ag_25_framework_vote.md)
- **Tried:** `framework_vote.zig` — blocks auto-retirement of a framework element without a witness; records approved revisions.
- **Result:** PASS.
- **Aftermath:** ADOPTED — cited by [tier8_ag_22f_v4_basis.md](docs/research/tier8_ag_22f_v4_basis.md) as the witnessed-vote wiring behind the v4 lane.

### [docs/research/tier8_ag_26_reality_anchor.md](docs/research/tier8_ag_26_reality_anchor.md)
- **Tried:** `reality_anchor.zig` with pluggable FileAnchor and PeerReplayAnchor traits.
- **Result:** PASS on both anchors.
- **Aftermath:** ADOPTED by the Phase-6 docs (T8-AG-23/27/28 use the anchor language); ⚠️ N3 flags the loop-level Phase-6 gate as a hardcoded `true`, not this trait code.

### [docs/research/tier8_ag_27_deploy_feedback.md](docs/research/tier8_ag_27_deploy_feedback.md)
- **Tried:** Deploy-feedback stub measuring the downstream effect of promoting `world_sum_mod=7`.
- **Result:** PASS — sum_mod downstream coverage 0.859 → 1.000 (+0.141).
- **Aftermath:** UNCLEAR — the identical figures recur in T8-AG-28 without attribution; no successor names this doc.

### [docs/research/tier8_ag_28_wcore_lift.md](docs/research/tier8_ag_28_wcore_lift.md)
- **Tried:** `tier8-wcore-lift`: does the wcore/E4-G00 promotion lift downstream sum_mod coverage (fixing "novel but 0 lift")?
- **Result:** PASS — tax pass true; coverage base 0.859 → seeded 1.000.
- **Aftermath:** MODIFIED — fork [tier8_ag_28f_minimal_lift.md](docs/research/tier8_ag_28f_minimal_lift.md).

### [docs/research/tier8_ag_28f_minimal_lift.md](docs/research/tier8_ag_28f_minimal_lift.md)
- **Tried:** Minimal promote set test: does `[world_sum_mod=7]` alone suffice for the downstream lift?
- **Result:** PASS — the single feature achieves coverage 1.000 (≥0.90 threshold).
- **Aftermath:** ADOPTED — cited by [tier8_tax_gate_promotion.md](docs/research/tier8_tax_gate_promotion.md) as the reference model for a library-export-only gate.

### [docs/research/tier8_ag_30_peer_replicate.md](docs/research/tier8_ag_30_peer_replicate.md)
- **Tried:** `tier8-peer-replicate`: does the tax survivor `world_sum_mod=7` replicate across independent seeds/batteries?
- **Result:** PASS — 3/3 independent seeds (E11, RQ7, battery B).
- **Aftermath:** ADOPTED into the Tier-8 completion checklist; ⚠️ same N3 caution on the loop-level replay of "3/3."

### [docs/research/tier8_ag_31_orchestrator.md](docs/research/tier8_ag_31_orchestrator.md)
- **Tried:** `tier8_orchestrator.zig` + expanded `swarm_fork_dispatch.zig` coordinating 22+ agents (Phase 7).
- **Result:** PASS.
- **Aftermath:** UNCLEAR — no successor doc named.

### [docs/research/tier8_tax_gate_promotion.md](docs/research/tier8_tax_gate_promotion.md)
- **Tried:** A/B/C compounding experiment: tax-survival as a hard promotion CONDITION (A) vs the shipped measurement-only v4 lane (B) vs no promotion (C), 3 seeds, 19-target two-phase battery.
- **Result:** NEGATIVE for the gate — B 57/57 @ 1191 evals > A 55/57 @ 6398 evals > C 54/57; gating loses 2/33 phase-1 solves and costs 5.4× the evals.
- **Aftermath:** ABANDONED — "keep measurement-only; do not adopt tax-survival as a promotion condition."

---

## 8. wcore — zero-bias invention engine (atom-forge, irreducibility certifier)

### [wcore/PLAN_INVENTION_ENGINE.md](wcore/PLAN_INVENTION_ENGINE.md)
- **Tried:** Planning document for a tensor-primitive AutoML-Zero-style invention engine (Setup/Predict/Learn programs, regularized evolution + MDL selection, compounding library, phased kill-tests).
- **Result:** Lays out mission, forbidden moves (no LLM proposer, no NAS menu, no proxy fitness), architecture, and two expected "Tier-3" walls — no run data.
- **Aftermath:** UNCLEAR — no downstream reference found; the executed wcore research pursued the symbolic atom-composition line instead of this tensor plan as written.

### [wcore/docs/research/alien_novelty_limit.md](wcore/docs/research/alien_novelty_limit.md)
- **Tried:** 16-phase arc (frontier map, novelty certifier, alien substrate, QD hunt, ablations, coevolution, composition ladder, irreducibility instrument, atom-forge, superoptimization) testing whether execution-only search can invent a genuinely novel primitive.
- **Result:** Claim C confirmed at every level — the irreducibility test finds "0 irreducible, 7 false positives" among the certifier-"novel" solvers; the atom-forge's 8 invented atoms are short substrate-op programs, not new primitives; terminal conclusion: "a fixed substrate always has a bottom, and at the bottom, search composes — it does not invent."
- **Aftermath:** ADOPTED as the arc's foundational negative result — scaled by [claim_c_breadth.md](wcore/docs/research/claim_c_breadth.md) and cited by CLOSURE_PRINCIPLE.md as the invention witness.

### [wcore/docs/research/claim_c_breadth.md](wcore/docs/research/claim_c_breadth.md)
- **Tried:** Ran the irreducibility instrument across 16 seeds to turn the single-seed Claim C finding into a breadth claim.
- **Result:** 85 of 86 certifier-"novel" deep solvers reducible (98.8%); kill-test correctly flagged irreducible 16/16; one exception (seed 0xD00D, 1 irreducible).
- **Aftermath:** MODIFIED — the lone exception resolved by [budget_scan.md](wcore/docs/research/budget_scan.md) (it reduces at depth 5, a budget artifact).

### [wcore/docs/research/budget_scan.md](wcore/docs/research/budget_scan.md)
- **Tried:** Cranked the exhaustive reduction budget to DMAX=8 across 4 seeds to test whether the 0xD00D depth-4 "irreducible" solver was a genuine atom.
- **Result:** "0 survivors at DMAX=8 in every case" — the 0xD00D solver reduces at depth 5; the hand-built distinct-count kill-test stayed irreducible at depth 8 (instrument non-vacuous).
- **Aftermath:** MODIFIED — pushed to DMAX 9–12 in [swarm_exp12_dmax_push.md](wcore/docs/research/swarm_exp12_dmax_push.md) and instrument-audited in [instrument_audit.md](wcore/docs/research/instrument_audit.md); ⚠️ [i53_falsification_2026_07_10.md](docs/research/i53_falsification_2026_07_10.md) flags the reducer's depth budget as carrying the same depth-artifact risk it exposed elsewhere — "worth its own round" (untested).

### [wcore/docs/research/instrument_audit.md](wcore/docs/research/instrument_audit.md)
- **Tried:** Attacked the negative result's own instrument — re-judged every deep solver under EXACT (100%) matching at 4096 samples vs the loose 0.95 threshold.
- **Result:** "0 masked, every seed" — exact matching agrees with loose on all 24 solvers; distinct-count stayed irreducible under both; "it can't invent" survives the audit.
- **Aftermath:** MODIFIED — extended by the adversarial stress-test [swarm_i54_i55_behavior_matches.md](wcore/docs/research/swarm_i54_i55_behavior_matches.md); recorded as #46 ✅ in RESEARCH_QUESTIONS.md.

### [wcore/docs/research/swarm_exp12_dmax_push.md](wcore/docs/research/swarm_exp12_dmax_push.md)
- **Tried:** Pushed the reduction budget to DMAX 9, 10, 11, 12 across the same 4 seeds hunting a deeper irreducible survivor.
- **Result:** 0 survivors at every DMAX 9–12 (29 deep solvers per DMAX); histograms byte-stable from 8 through 12; max reduction depth stayed 5 — "RQ #10 closed for fixed atoms."
- **Aftermath:** ADOPTED — the fixed-atom question closed; the open-atom-set forge remains "the designed escape hatch."

### [wcore/docs/research/a1a6_iterated_promotion.md](wcore/docs/research/a1a6_iterated_promotion.md)
- **Tried:** 10-round atom-forge promotion loop (2 seeds) with an irreducibility census, held-out 18-target generalization probe, and deeper re-certification of promoted atoms (A1–A6).
- **Result:** No fixed point in 10 rounds (library 5→15); held-out reachability 3/18→7/18 but 6 of 8 flips were decoy self-re-draws — corrected genuine curve 3/18→4/18; retro-audit found 1/20 promotions was a depth-5-reducible false-irreducible and 3/20 became redundant.
- **Aftermath:** OPEN — promotion "relocates claim C, doesn't escape it" (per RESEARCH_QUESTIONS.md A1–A3 ✅); the deeper-certifier / held-out-coupled forge named as the unsolved lever.

### [wcore/docs/research/swarm_exp13_atom_minimize.md](wcore/docs/research/swarm_exp13_atom_minimize.md)
- **Tried:** Drop-each-atom ablation plus greedy minimization of the 13-atom promoted library (RQ A4).
- **Result:** PASS — 2/13 atoms REDUNDANT once later atoms enlarge the vocabulary; minimal set 11 atoms with coverage fully preserved (18% compression); all 5 base atoms ESSENTIAL.
- **Aftermath:** ADOPTED as the RQ A4 answer ("now measured, not open").

### [wcore/docs/research/swarm_exp14_invented_on_invented.md](wcore/docs/research/swarm_exp14_invented_on_invented.md)
- **Tried:** Enumerated all depth-≤3 composition behaviours of the final 13-atom library hunting tasks solvable only after ≥2 promotions with ≥2 invented atoms chained (RQ A6).
- **Result:** PASS — 764 late-flip tasks; 437 genuine invented-on-invented (earliest strict case inv#1∘inv#3 at round 3).
- **Aftermath:** ADOPTED as the RQ A6 answer, with the honest bound that this "relocates claim C rather than escaping it."

### [wcore/docs/research/swarm_exp15_synergy_atoms.md](wcore/docs/research/swarm_exp15_synergy_atoms.md)
- **Tried:** Hunted irreducible generator PAIRS (RQ 17/#38) in the u8 program substrate and cross-checked the wcore base atoms by withholding each.
- **Result:** sparse_poly side PASS — 2 emergent pair escapes found, affine base 0/5 nonlinear targets; wcore side 0 atom-pair synergies ("the five hand-built wcore atoms are complete solvers, not decomposable substrate ops").
- **Aftermath:** ADOPTED as the RQ 17 answer; ⚠️ the pair-necessity reading later depth-qualified by [i53_falsification_2026_07_10.md](docs/research/i53_falsification_2026_07_10.md); the "escalate to pair-search when greedy stalls" design implication remains OPEN.

### [wcore/docs/research/swarm_i54_i55_behavior_matches.md](wcore/docs/research/swarm_i54_i55_behavior_matches.md)
- **Tried:** Adversarial stress of `behaviorMatches` itself — 117 near-miss pairs at 4096 symbols, false-negative hunts at shrinking budgets, 32→256→4096 verdict-flip sweeps (I54/I55).
- **Result:** PASS — 0 verdict flips across 38 solver/seed checks, 0 false positives (nearest near-miss 64%, 31 points below the bar), 0 false negatives down to 32 symbols, 0 masked solvers.
- **Aftermath:** ADOPTED — instrument trust closed for the matching kernel; no further stress-test line.

---

## 9. deepseekexperiment — DeepSeek V4 binarization & streaming campaign (2026-06)

### [deepseekexperiment/DISCOVERIES.md](deepseekexperiment/DISCOVERIES.md)
- **Tried:** Running discoveries log across the DeepSeek binarization campaign.
- **Result:** Headlines: XOR-native format 0.95–0.98 cosine/matmul; held-out ppl 24.4→29.9 (+0.206 nats — intelligence survives); compute floor broken 3.4→26 tps (GPU kernel) but the system stays fetch-bound; storage-bandwidth wall settles the campaign; final engine 3.1–8.2 tps batched / ~0.37–0.49 interactive.
- **Aftermath:** ONGOING LOG — see the individual dated docs below.

### [deepseekexperiment/docs/signal_survival_findings.md](deepseekexperiment/docs/signal_survival_findings.md)
- **Tried:** Two-round test of whether DeepSeek matmuls survive XOR/popcount 1-bit and multi-plane bitplane quantization.
- **Result:** Naive 1-bit hits the theoretical sqrt(2/π)=0.798 gaussian wall; residual bitplanes + Hadamard rotation reach 0.974 (P3) / 0.986 (P4) cosine — H+P3w+P3a chosen (~3.2 bits/weight).
- **Aftermath:** ADOPTED — this format is the standard for the whole campaign.

### [deepseekexperiment/docs/ten_experiments_2026_06_10.md](deepseekexperiment/docs/ten_experiments_2026_06_10.md)
- **Tried:** Ten characterization experiments (E1–E10) of XOR quantization + full 61-layer forward with attention ablated.
- **Result:** XOR format 0.98 cosine/matmul; but the ablated stack collapses to 0/8 top-1 agreement by L60 at ALL precisions (P8 control); I/O ceiling ~0.23 tps (92% fetch stall).
- **Aftermath:** ⚠️ The "chaos collapse" reading REFUTED by [e11_perplexity_2026_06_11.md](deepseekexperiment/docs/e11_perplexity_2026_06_11.md) — substantially an attention-ablation artifact.

### [deepseekexperiment/docs/e11_perplexity_2026_06_11.md](deepseekexperiment/docs/e11_perplexity_2026_06_11.md)
- **Tried:** Standalone perplexity A/B (reference vs XOR-quantized) with real MLA attention restored, on held-out text.
- **Result:** Hidden cosine @L60 recovers to 0.833 (vs 0.225 ablated); held-out ppl 24.38 vs 29.94 (+0.206 nats), top-1 86/127; damage concentrated in the top-10 positions (92% of the gap).
- **Aftermath:** ADOPTED — "intelligence substantially survives" became the settled premise; REFUTES the E4/E9 collapse framing.

### [deepseekexperiment/docs/u3_cache_aware_routing_2026_06_11.md](deepseekexperiment/docs/u3_cache_aware_routing_2026_06_11.md)
- **Tried:** Cache-aware routing (LRU expert cache + gate-margin substitution) to cut expert fetches during decode.
- **Result:** Fetches cut 25.9% for +0.013 nats; aggressive eps=0.25 cuts 34% for +0.104 nats (better than no-policy +0.162).
- **Aftermath:** ADOPTED — the campaign's one CONFIRMED lever, carried into the strategy and engine docs.

### [deepseekexperiment/docs/research_roadmap_speed_campaign.md](deepseekexperiment/docs/research_roadmap_speed_campaign.md)
- **Tried:** Formal speed-campaign roadmap: U-ledger (U1–U10) and R-map (R1–R6) targeting 20 tps.
- **Result:** Established the 87× physics gap (0.23 tps vs 20); U3 the only confirmed lever at writing.
- **Aftermath:** MODIFIED — the master queue the rest of June worked through (U2 killed; surrogates killed; MTP deferred).

### [deepseekexperiment/docs/roadmap_to_100tps_2026_06_12.md](deepseekexperiment/docs/roadmap_to_100tps_2026_06_12.md)
- **Tried:** Tiered surrogate-engine roadmap (surrogate experts, then surrogate attention) toward 100 tps.
- **Result:** Projected 6–11 tps (tier 1) and 25–50 tps (tier 2), explicitly gated on an unproven surrogate-fidelity number.
- **Aftermath:** ⚠️ ABANDONED — the gating experiment failed decisively in [surrogate_verdict_2026_06_13.md](deepseekexperiment/docs/surrogate_verdict_2026_06_13.md) ("surrogate-expert verdict: DEAD").

### [deepseekexperiment/docs/two_floors_reconciliation_2026_06_12.md](deepseekexperiment/docs/two_floors_reconciliation_2026_06_12.md)
- **Tried:** Reconciled the fetch floor with a newly measured compute floor (~3.4 tps) and proposed surrogates as the dual-floor escape.
- **Result:** 37.8 GMAC/token → ~3.4 tps ceiling; surrogate projections rested on held-out fidelity of only 0.55.
- **Aftermath:** ⚠️ ABANDONED — surrogate premise killed by [surrogate_verdict_2026_06_13.md](deepseekexperiment/docs/surrogate_verdict_2026_06_13.md); its fallback ceiling estimate survived.

### [deepseekexperiment/docs/u2_compression_verdicts_2026_06_12.md](deepseekexperiment/docs/u2_compression_verdicts_2026_06_12.md)
- **Tried:** Linear weight compression (U2 cross-expert subspace, B8 per-expert SVD) and a first-pass activation-manifold test (B5, 488 samples).
- **Result:** U2 dead (rel-err 0.907 at 7×); B8 dead (rank ~2075/3072); B5 "promising" at 94.6% energy @128 dims but data-starved.
- **Aftermath:** ⚠️ B5's promise REFUTED as a "small-sample MIRAGE" by [b5_manifold_verdict_2026_06_12.md](deepseekexperiment/docs/b5_manifold_verdict_2026_06_12.md).

### [deepseekexperiment/docs/b5_manifold_verdict_2026_06_12.md](deepseekexperiment/docs/b5_manifold_verdict_2026_06_12.md)
- **Tried:** B5-v2: activation-manifold compression re-run at 15,616 samples (32×).
- **Result:** Verdict flips — held-out energy at k=128 collapses 94.6%→56.5%; k=1024 leaves 0.359 residual — "linear compression is now dead on BOTH axes."
- **Aftermath:** ADOPTED — closed the linear-compression direction for good.

### [deepseekexperiment/docs/STRATEGY_2026_06_12.md](deepseekexperiment/docs/STRATEGY_2026_06_12.md)
- **Tried:** 15-agent adversarial re-verification of prior assumptions, setting the batched-offline-engine strategy.
- **Result:** Three errors corrected (route_overlap is fidelity not locality; P3 store ~598GB fits no drive; 0.23 tps floor unbeatable in software); batched path projected 0.5–1.0 tps honest.
- **Aftermath:** ADOPTED — supersedes the optimistic roadmaps; E0 union-saturation folded into [batched_engine_validated_2026_06_13.md](deepseekexperiment/docs/batched_engine_validated_2026_06_13.md).

### [deepseekexperiment/docs/batched_engine_validated_2026_06_13.md](deepseekexperiment/docs/batched_engine_validated_2026_06_13.md)
- **Tried:** Validated the batched-GPU decode engine end-to-end from measured components before committing to the build.
- **Result:** B=512 batched decode projects 5.4 tps aggregate, gated on freeing ~440GB fast storage.
- **Aftermath:** MODIFIED — the fast-drive assumption failed ([storage_bandwidth_wall_2026_06_14.md](deepseekexperiment/docs/storage_bandwidth_wall_2026_06_14.md)).

### [deepseekexperiment/docs/engine_first_generation_2026_06_13.md](deepseekexperiment/docs/engine_first_generation_2026_06_13.md)
- **Tried:** Built `chat_v4` — first true end-to-end generation (tokenize → 61-layer XOR-quantized forward → sample).
- **Result:** "The capital of France is" → " Paris" (logit 23.78, decisive); correct generation PROVEN, at 0.23 tps unoptimized.
- **Aftermath:** ADOPTED — "the deliverable the research earned."

### [deepseekexperiment/docs/fetch_lever_kills_2026_06_13.md](deepseekexperiment/docs/fetch_lever_kills_2026_06_13.md)
- **Tried:** Super-expert clustering, surrogate kill-tests, and top-k routing reduction as fetch levers.
- **Result:** All three DEAD — clustering serves 0.0% of tokens under real routing; top-k costs +0.24 nats for 1.5× savings.
- **Aftermath:** MODIFIED — its in-progress locality re-measurement landed in [freqprec_and_mtp_2026_06_13.md](deepseekexperiment/docs/freqprec_and_mtp_2026_06_13.md).

### [deepseekexperiment/docs/freqprec_and_mtp_2026_06_13.md](deepseekexperiment/docs/freqprec_and_mtp_2026_06_13.md)
- **Tried:** Frequency-weighted precision (cold experts to 1-bit) plus MTP speculative-decode scoping.
- **Result:** Freq-precision CONFIRMED at top-64 (~2.1× fewer fetch bytes for +0.037 nats; top-32 too aggressive at +0.26); MTP only ESTIMATED (~55–65%), port deferred.
- **Aftermath:** ADOPTED (freq-precision) / OPEN (MTP never measured).

### [deepseekexperiment/docs/surrogate_verdict_2026_06_13.md](deepseekexperiment/docs/surrogate_verdict_2026_06_13.md)
- **Tried:** Decisive surrogate-experts test: 512-token capture + held-out fidelity (E19c/E19e).
- **Result:** DEAD — manifold near-full-rank (90% energy needs 292/3072 dims, not "84"); held-out fidelity plateaus 0.50–0.61 vs the 0.85 bar.
- **Aftermath:** ADOPTED as the direction-closing verdict — REFUTES both surrogate roadmaps ("a 128-SAMPLE MIRAGE, identical failure mode to B5").

### [deepseekexperiment/docs/weights_are_noise_2026_06_13.md](deepseekexperiment/docs/weights_are_noise_2026_06_13.md)
- **Tried:** Are expert weights distinguishable from gaussian noise by any statistic (WHT spectrum, autocorrelation, kurtosis, row-norm variance)?
- **Result:** Statistically IDENTICAL to noise (WHT top-1% 8.36% vs 8.37%; autocorr ~0) — "the math/representation space is CLOSED."
- **Aftermath:** ADOPTED as the closing theoretical result; rationale for the full pivot to systems work.

### [deepseekexperiment/docs/storage_bandwidth_wall_2026_06_14.md](deepseekexperiment/docs/storage_bandwidth_wall_2026_06_14.md)
- **Tried:** Analytically closed the speed campaign: routing skew × measured cold drive bandwidths × forged working-set sizes.
- **Result:** Smallest full-quality working set (P1, 250GB) exceeds all free fast storage (84GB); the wall is storage capacity×bandwidth, not compute or algorithm.
- **Aftermath:** ADOPTED as "the real, final gate" — escape requires hardware; the tiered engine was built within it.

### [deepseekexperiment/docs/tiered_streaming_engine_2026_06_15.md](deepseekexperiment/docs/tiered_streaming_engine_2026_06_15.md)
- **Tried:** Built and measured the four-tier streaming MoE engine (disk→RAM→VRAM→CPU) with real forged P3 experts.
- **Result:** GPU/CPU cosine 1.000000 (compute correct); 2.4–2.5 tps @B=512 / 4.7–5.0 @B=1024 (0.37 interactive); the P3 always-active core (17.6GB) exceeds 16GB RAM.
- **Aftermath:** MODIFIED same day — overhead fix reached 3.1/6.2 tps, block-256 projected ~4.1/~8.2 (final recorded state).

---

## 10. Addition-chain campaign (results/)

### [results/addchain_campaign_2026_07_07.md](results/addchain_campaign_2026_07_07.md)
- **Tried:** First dated claims ledger for the addition-chain campaign (SMALL n≤1024, COMPOSITE sets, IDDFS engine + independent verifier) plus a trust-repair audit of four inherited repo claims.
- **Result:** SMALL "VERIFIED minimal" (blind IDDFS, rediscovers OEIS A003313); COMPOSITE "VALID + BEATS-BINARY (7/8) + minimality UNPROVEN"; fake-chain negative control correctly REFUTED; trust repair: "CEGIS rediscovered x&(x-1) in 3 gens: REFUTED."
- **Aftermath:** SUPERSEDED-BY [results/addchain_campaign_2026_07_08.md](results/addchain_campaign_2026_07_08.md) (explicit "Supersedes/augments" header).

### [results/addchain_campaign_2026_07_08.md](results/addchain_campaign_2026_07_08.md)
- **Tried:** Augmented rerun adding Pollard-Rho 40-bit composites, a baseline battery, the negative control, N1–N4 ledger citations, and a window/hybrid engine-mode addendum.
- **Result:** Beats binary on 735/1023 (0 losses); window mode an explicit negative (beats_binary=0/20, worse=20); hybrid beats_binary=20 via factor-method fallback ("never worse than binary").
- **Aftermath:** ADOPTED (hybrid kept as safety net; window ABANDONED as a documented negative control); consolidated into [results/addchain_campaign.md](results/addchain_campaign.md).

### [results/addchain_campaign.md](results/addchain_campaign.md)
- **Tried:** Consolidated write-up of the full pipeline: IDDFS engine certifying l(n), independent verifier, /dev/urandom target generator, baseline battery.
- **Result:** SMALL VERIFIED minimal; COMPOSITE VALID+BEATS-BINARY+minimality UNPROVEN (NP-hard); LARGE (256-bit) explicitly ABSTAINED — no fake chain; negative control exits 1 "REFUTED non-minimal."
- **Aftermath:** ADOPTED — §5 declares it "self-contained and sound," independent of all four refuted ledger claims (exhaustive IDDFS, not CEGIS); extended by [boundary_crossing/docs/research/addchain_v2.md](boundary_crossing/docs/research/addchain_v2.md).

### [boundary_crossing/docs/research/addchain_v2.md](boundary_crossing/docs/research/addchain_v2.md)
- **Tried:** Campaign v2 (2026-07-10): added window/m-ary, Bos-Coster-style stochastic improver, and deletion-repair methods over 118 /dev/urandom targets up to 40 bits, all chains re-checked by the existing external verifier.
- **Result:** 118/118 independently VALID, 0 refuted; on 24–40-bit targets the honest invention yield is 52/60 (87%) beating the best classical heuristic (ablation: 12/60 of that is deletion-repair cleanup alone); the requested lower bound ⌈log₂n⌉+⌈log₂ν(n)⌉ was REFUTED as a bound (gap −1 at n=15); independent minimality proof pushed from n≤1024 to **n≤16384**.
- **Aftermath:** ADOPTED — completes experiment 2 of [docs/research/research_round_2026_07_10.md](docs/research/research_round_2026_07_10.md); its Frank Verdict states "nothing here is new-to-humanity" and defines exactly what a genuine record attempt would require (OPEN).

---

## 11. Swarm round 2026-07-05 (cross-project) & instrument audits

### [docs/research/swarm_2026_07_05_master.md](docs/research/swarm_2026_07_05_master.md)
- **Tried:** 27 primary experiments + 8 forks, one subagent per research question: instrument trust, menu/routing/invention, control, wcore atoms, theory, verified synthesis, sample complexity.
- **Result:** Instrument trust 4/4 after the G48 fix; menu/routing 8/8; wcore atoms 4/4 (EXP-12: 0 survivors D≤12); strongest new result RQ1++ staged escalation 11/11; honest failure: mb_mass does not beat a tuned thermostat (0.00 vs 11.02).
- **Aftermath:** ADOPTED — key harnesses re-verified twice on 2026-07-06; the open forks became the Tier 8 program.

### [docs/research/swarm_exp16_escape_counterexamples.md](docs/research/swarm_exp16_escape_counterexamples.md)
- **Tried:** Hunted counterexamples to the escape corollary via five constructed pathological cases.
- **Result:** "YES — four honest counterexamples to the naive corollary" (mis-identified generator, pair requirement, encoding mismatch, wrong outer) but "counterexamples to closure principle? NO" — survives, refined.
- **Aftermath:** ADOPTED — the refined corollary wording; CE-1 re-verified the emergent_escape refinement.

### [docs/research/swarm_exp17_degree_predictor.md](docs/research/swarm_exp17_degree_predictor.md)
- **Tried:** Does one cross-domain measure (algebraic degree, SAC, BRank) predict escape-gap magnitude across the 5 closure witnesses?
- **Result:** NO unified predictor — degree r≈0.35 (R²≈0.12); SAC-error tautological across domains; "three incompatible regimes, not one ruler."
- **Aftermath:** OPEN — the proposed Tier-B mixer experiment and f_esc metric never run.

### [function_hardness/docs/research/swarm_exp18_routing_priors.md](function_hardness/docs/research/swarm_exp18_routing_priors.md)
- **Tried:** EXP-18: used the exhaustive n=4 predicate hardness landscape to supply routing priors (monomial/spectral/pair/Walsh/world) for the sparse_poly discoverer escalation ladder, evaluated blind on 19 hidden targets.
- **Result:** PASS — route prediction 19/19 = 100% (threshold >80%; conservative argmax ground truth still 16/19 = 84.2%); priors skip entire escalation phases (5 of 7 unified targets routed to monomial with no menu/world probe).
- **Aftermath:** ADOPTED — the landscape-to-router bridge behind E14 and the Tier-8 Battery-C generator; honest limits note the Q38 pair route was never load-bearing on this battery (OPEN).

### [docs/research/swarm_g48_toaig_audit.md](docs/research/swarm_g48_toaig_audit.md)
- **Tried:** Exhaustive truth-table audit of `toAig` lowering vs `execute` for 5 ISA ops at widths 4 and 8.
- **Result:** Initial FAIL — 34,302 mismatches (AND lowered as XOR; SHL a no-op); after source fix, PASS with 0 mismatches.
- **Aftermath:** ADOPTED — the G48 fix is the prerequisite cited by G49 and the swarm master's instrument-trust row.

### [docs/research/swarm_g49_z3_cross_audit.md](docs/research/swarm_g49_z3_cross_audit.md)
- **Tried:** Cross-audited the native AIG/DPLL prover against libz3 on a 99-case equivalence battery.
- **Result:** First runs failed (toSat encoding, miter polarity, harness UB); after fixes, PASS — 99/99 (100%), 0 disagreements.
- **Aftermath:** ADOPTED and extended — the 5016-case from-scratch cross-audit in [i53_falsification_2026_07_10.md](docs/research/i53_falsification_2026_07_10.md) triangulates the kernel with a third instrument.

---

## 12. Research round 2026-07-10 — falsification & scaling

### [docs/research/research_round_2026_07_10.md](docs/research/research_round_2026_07_10.md)
- **Tried:** Eight parallel experiments toward "way better than AlphaEvolve": LABS campaign, addchain v2, Clifford ablation, iterated promotion, tax-gate-as-condition, Tier-8 ablation, H50 scaling laws, I53 falsification + G49.
- **Result:** LABS 23/23 match literature (best-known N=25–59); A10 0.508→0.976; A1–A6 "no fixed point, 3/18→4/18 genuine flips"; tax-gate "keep measurement-only"; H50 hard ceiling exactly 372 evals; I53 core theorem survived, pair block REFUTED as printed.
- **Aftermath:** ADOPTED as the current round banner — experiment 2 completed by [boundary_crossing/docs/research/addchain_v2.md](boundary_crossing/docs/research/addchain_v2.md) (52/60 beat the classical stack at 40-bit, 118/118 independently verified), making the round 8/8 landed.

### [docs/research/i53_falsification_2026_07_10.md](docs/research/i53_falsification_2026_07_10.md)
- **Tried:** Adversarial attack on the Closure Principle (domain-width abuse, depth-push on pair-necessity, register-bound probe, affine-theorem edge cases) plus a 5016-case from-scratch cross-audit of the native prover.
- **Result:** Core ceiling SURVIVED (exact u2 fixpoint proof; affine base 0/5 nonlinear targets everywhere); both pair-necessity claims BROKEN (SUB alone at depth 6 on the repo's own u8/K=2 substrate; a {SHR,SHL,XOR,NOT,AND}-only witness for x|(x*x)); T3 off-by-one found (order ≤65 for c≠0); G49 PASS 5016/5016.
- **Aftermath:** ADOPTED — four qualifiers proposed for CLOSURE_PRINCIPLE.md; wcore Claim C's depth-budget reducer flagged as the next falsification target (OPEN).

### [docs/research/scaling_laws_h50.md](docs/research/scaling_laws_h50.md)
- **Tried:** Battery-solve and novel-promotion yield vs eval budget {6…1536} on the production invention engine, 4 seeds.
- **Result:** Steep then hard-saturated — 10/11 solves by ~50 evals, 11/11 at exactly 372; one out-of-closure target consumes 87% of the budget; ≈0.42 certified solves/CPU-s (with an explicit anti-AlphaEvolve-comparison caveat).
- **Aftermath:** ADOPTED as experiment 7 of the 2026-07-10 round; H51/H52 remain OPEN.


---

## 13. Research round 2026-07-10b — aiming the escapes

### [docs/research/research_round_2026_07_10b.md](docs/research/research_round_2026_07_10b.md)
- **Tried:** Six parallel experiments building/testing the aiming mechanism round 1 identified as the binding resource: aimed forge (wcore), aimed proposer (battery-C wall), discriminating gate v5, Claim-C depth attack, LABS even-N moves, decisive battery-D.
- **Result:** In progress — battery-D landed first (3/11 decisive; ablation 1/9 vs 9/9).
- **Aftermath:** OPEN — live round master doc, updated per landing.

### [docs/research/breadth_vs_depth.md](docs/research/breadth_vs_depth.md)
- **Tried:** The direct equal-total-budget head-to-head (D1 headline) — depth (one deep proposer) vs breadth (N∈{4,8,16,32} diverse proposers sharing depth's exact consumed evals) across 3 seeds, with C09 as a proven out-of-closure negative control.
- **Result:** Breadth NEVER beats depth (12/12/12 vs 13/12/13); C09 falls to no arm on any seed (0/0/0); breadth loses the concentration-dependent target B11 to fragmentation at every N≥8; dominant-proposer share 83–100% (diversity mostly illusory); its only edge is a variance/portfolio hit on the ~17% probabilistic XOR layer, dominated by the B11 loss.
- **Aftermath:** ADOPTED — re-confirms the H50 ceiling for the breadth axis; the ceiling is representability/aim not quantity; pairs with [breadth_scaling.md](docs/research/breadth_scaling.md) and [diversity_predictor.md](docs/research/diversity_predictor.md).

### [docs/research/tier8_battery_d.md](docs/research/tier8_battery_d.md)
- **Tried:** Constructed 11 targets generalizing C08's decisive coincidence (ladder-certifiable escape that the v3 tax bank independently reconstructs) along sum%k, count3%k, and subset-Walsh; empirically classified band membership, then re-ran the two-arm ablation on the decisive subset.
- **Result:** 3/11 DECISIVE (D01 sum%2, D07 count3%3, D11 subset-parity via an unpredicted monomial sign-parity route); ablation 3 targets × 3 seeds: ARM-OFF 1/9 vs ARM-ON 9/9, zero reversals, battery B preserved at fewer evals (2072 vs 4412).
- **Aftermath:** ADOPTED — upgrades [tier8_ablation.md](docs/research/tier8_ablation.md)'s single-witness existence proof to a measured effect size; ⚠️ also exposed a second `equivalence_tax.greedyFit` defect (raw-vs-z-scored column scale mismatch let 5 candidates leak TOO_EASY — fix queued) and a ladder reachability gap (D08, OPEN).

### [docs/research/tier8_aimed_proposer.md](docs/research/tier8_aimed_proposer.md)
- **Tried:** Frontier-coupled proposer at the battery-C wall — mine near-miss evidence (monomial-sweep argmax + 256-Walsh sweep), scan generic per-cell lenses over the evidence mask, grow/shrink greedily, certify through the real coverage/R² bar; tax as export filter only.
- **Result:** Wall moved 3/33 → 8/33 (+5 flips, every evidence-mined mask byte-identical to ground truth, all novel by tax proxy); honest limit derived: aiming signal is (1/3)^k under the current lens → probabilistic (~17%/attempt deg-4, 0 at deg-5); C09's order-statistic family resists entirely.
- **Aftermath:** ADOPTED — confirms the round's frontier-coupling bet at the proposal layer; next lever named (better evidence lenses, not more attempts); C09 + [tier8_battery_d.md](docs/research/tier8_battery_d.md)'s D08 jointly mark the proposal-vs-family-invention frontier (OPEN).

### [boundary_crossing/docs/research/labs_even_n.md](boundary_crossing/docs/research/labs_even_n.md)
- **Tried:** Attacked the 12 LABS miss lengths (even N≥44 + {61,63}) with pair/triple-flip neighborhoods, memetic search, and three mirror-pair structural hypotheses at 160–185M evals/length.
- **Result:** 2/12 fully closed (N=44 E=122, N=50 E=153 = best-known), 3 partial, 4 regressed (arm-splitting underperformed one concentrated run); no mirror-pair hypothesis reproduces skew-symmetry's benefit (isolation: plain F=6.86 vs mirror 4.24); verifier 12/12 + 63/63, plant refuted.
- **Aftermath:** MODIFIED direction — the even-N restriction, if it exists, is outside the mirror-pair family (OPEN, genuine theory gap); process lesson adopted: winnow arms then concentrate budget; updates [labs_campaign.md](boundary_crossing/docs/research/labs_campaign.md)'s miss table.

### [wcore/docs/research/aimed_forge.md](wcore/docs/research/aimed_forge.md)
- **Tried:** Four equal-budget arms testing residual pressure toward the never-reached structured family: unaimed control (reproduced A1–A6 exactly), aimed-fitness flat + annealed, and aimed-promotion (promote highest-residual certified candidate); plus a residual-landscape diagnosis probe.
- **Result:** Aimed fitness F 0/9 both arms/seeds (search-level aiming fails; SELF pathology drops 75%→14–38%); aimed promotion scored the arc's first structured-family solves (hashtbl+union, 1/2 seeds, atom holds at all audit depths); distinct-count measured as a conjunction wall (climb plateau 0.862 < 0.95 bar); retro-audit 4/80 leaks (5%).
- **Aftermath:** ADOPTED as the architecture principle (with [tier8_aimed_proposer.md](docs/research/tier8_aimed_proposer.md) and round 1's tax finding): aim and gates act at selection boundaries, never inside inner loops; the conjunction-wall class is the named successor problem (OPEN, target: lift 0.862→≥0.95 via stepping-stone curricula / mechanism descriptors).

### [docs/research/tier8_gate_v5.md](docs/research/tier8_gate_v5.md)
- **Tried:** Shadow-audited 4 post-revision gate variants against 103 real captured gate decisions (live passes replicated the ablation byte-identically): leave-one-out ε sweep, marginal-coverage, and v5-ladder (remix quantified over the level-1 engine-expressible basis only).
- **Result:** Full-basis variants fail irreducibly (C08's test_acc = 1.0000 exactly equals true remix — no ε separates); v5-ladder passes all three bars: 3/3 C08 admission, 51/51 true remixes blocked, 6/6 wrongly-blocked escapes admitted; honest post-revision novel rate 41% vs the v4 lane's pinned 100%.
- **Aftermath:** ADOPTED — v5-ladder at the verdict layer, v4's vacuous lane retired, ladder-novel as wcore export filter, never bound in-loop; resolves the caveat in [tier8_ablation.md](docs/research/tier8_ablation.md); "novel" is now closure-relative (novel w.r.t. what the engine can express) — consistent with [CLOSURE_PRINCIPLE.md](CLOSURE_PRINCIPLE.md).

### [wcore/docs/research/claimc_depth_attack.md](wcore/docs/research/claimc_depth_attack.md)
- **Tried:** The I53 depth-push attack applied to wcore's irreducibility certifier: re-certified all 20 a1a6 promoted atoms at +1..+5 depth with checked reduction witnesses, plus a completed depth-8 kill-test enumeration.
- **Result:** 1/20 flips at +1 depth (the known a1a6 leak, independently re-verified), 0 flips at +2..+5 — artifact class is 5% and entirely front-loaded; kill-test correctly irreducible at completed depth 8 but with a 0.008 margin vs the 0.95 statistical matcher; depth ≥5 vs 14-atom libraries honestly budget-open.
- **Aftermath:** ADOPTED — corrected qualifier wording ("irreducible at depth ≤3 under the production evaluator", never "irreducible"); +1-depth promotion gate (~1s/candidate) closes the artifact class; ⚠️ next falsification target named: the 0.95 matcher, not depth; corrects [a1a6_iterated_promotion.md](wcore/docs/research/a1a6_iterated_promotion.md)'s framing and INDEX's certifier row.

---

## 14. Research round 2026-07-10c — crossing the conjunction wall

### [docs/research/research_round_2026_07_10c.md](docs/research/research_round_2026_07_10c.md)
- **Tried:** Six parallel experiments on round-b's successor problems: conjunction wall (stepping-stones + mechanism descriptors), evidence lenses vs (1/3)^k, greedyFit z-scoring fix, 0.95-matcher falsification, the assembled-engine coherence test, D08/C09 family-level reach gap.
- **Result:** In progress — taxfix landed first (decisive band 3→8, ablation 0/24 vs 22/24).
- **Aftermath:** OPEN — live round master doc, updated per landing.

### [docs/research/tier8_taxfix.md](docs/research/tier8_taxfix.md)
- **Tried:** Fixed greedyFit's scale mismatch (weights fit on raw columns, evaluated on z-scored columns) with train-stat scaling on both splits; pre-fix control reproduced all old results byte-identically before applying, then re-ran all three regression gates.
- **Result:** Stock production line-identical (11/11); all five battery-D leaks flip TOO_EASY→DECISIVE (band 3→8); B3 (sum%7) exposed as silently leaking in every prior strict-v3 run (honest ARM-OFF battery-B 29/33); updated ablation 0/24 vs 22/24 (26 ON-only proofs, 0 reverse); gate v5 survives and strengthens (60/60 blocked, 9/9 admitted).
- **Aftermath:** ADOPTED — the fix understated-not-inflated direction strengthens Tier 8's headline; ⚠️ corrects [tier8_battery_d.md](docs/research/tier8_battery_d.md)'s band classification and [tier8_ablation.md](docs/research/tier8_ablation.md)'s 32/33 ARM-OFF battery-B figure (honest: 29/33 under strict v3); migration CSVs kept separate so prior docs still match their data.

### [docs/research/tier8_evidence_lenses.md](docs/research/tier8_evidence_lenses.md)
- **Tried:** Built ≥5 evidence lenses with derived-then-verified signal formulas (pairwise (1/3)^(k−2), Gibbs (1/3)^(k−u), mod2-Walsh, exact GF(2) joint solve) against the (1/3)^k aiming-signal decay; full pipeline at 3 seeds vs the 8/33 baseline.
- **Result:** Battery-C saturated 33/33 at fewer evals than v1 (12,630 vs 13,152); C11 deg-5 0→100%, C09 0→60/60 (GF(2)+pairwise-order primitives only); 30/30 derivation chains byte-exact, zero false accepts; the (1/3)^k wall was an estimator artifact, not an information limit.
- **Aftermath:** ADOPTED — GF(2) identification supersedes correlation-argmax aiming; ⚠️ asterisk: exactness needs noiseless labels (LPN re-opens the wall under noise — successor battery needed, OPEN); battery-C retired as saturated.

### [docs/research/tier8_reach_gap.md](docs/research/tier8_reach_gap.md)
- **Tried:** Diagnosed D08/C09 unreachability via per-family exhaustive sweeps + information-basis Bayes ceilings; derived the minimal comparison-aggregate family; extended the ladder (+CMP, +MENUACC) and re-ran all batteries at 3 seeds.
- **Result:** C09 proven family-level (all family Bayes ceilings at chance, inversion basis 1.000); D08 is a selection bug (exact spectral member at gridpoint 100; discoverSpectral picks by DFT power not accuracy; same bug makes D09 seed-fragile); double dissociation confirmed; B 30→33, C 3→6, D 28→33 of 33, +11 flips, 0 regressions in 99 cells; cost signature = round-1's out-of-closure shape (∞ → 397–1,689 evals).
- **Aftermath:** ADOPTED — MENUACC as production bug-fix (selection statistic must equal certification statistic), CMP earns a ladder seat; ⚠️ corrects [tier8_battery_d.md](docs/research/tier8_battery_d.md)'s D08 TOO_HARD reading (selection, not reach) and exposes B11's production solve as metadata-gated; Bayes-ceiling diagnosis ADOPTED as the standard wall-classification method.

### [wcore/docs/research/matcher_falsification.md](wcore/docs/research/matcher_falsification.md)
- **Tried:** Four attacks on the 0.95 / 8×28 statistical matcher (constructed adversaries incl. a horizon bomb, random false-equal hunt, false-different hunt, 100-seed flip distribution), then derived a corrected protocol with empirical ROC and re-ran all prior verdicts under it.
- **Result:** CRACKED — 4.2% of real a1a6 "reducible" verdicts are false-equals (all witnessed); horizon bomb scores 1.000 at true agreement 10.9%; false-different 0/90k; seed-flips 0/2000. Corrected protocol (exact match, 64×256, 2 seeds, early-exit): 0 false-equals, true-equal 1.0000, cheaper (13ms vs 70ms). 20/20 promotion identities unchanged; inv8 depth-flip and kill-tests stand.
- **Aftermath:** ADOPTED — exact-match protocol replaces the 0.95 threshold (strictly better + cheaper); ⚠️ corrects [claimc_depth_attack.md](wcore/docs/research/claimc_depth_attack.md)'s "matcher is the thin axis" reading (per-verdict seed-robustness is fine; the lie was horizon/threshold, and it lived in census rows, not promotions); next target flagged: the coevo-side 12×32 matcher (OPEN).

### [docs/research/tier8_assembled.md](docs/research/tier8_assembled.md)
- **Tried:** First integration run of the settled architecture — framework revision + aimed proposer (post-ladder, stuck targets only) + v5-ladder verdict layer + export-filter tax — four arms × 3 seeds across batteries B/C/D with in-harness baselines against the taxfix.
- **Result:** Coheres: assembled hits every battery's best simultaneously (B 33/33, C 8/33 byte-identical flips, D-decisive 9/9) at revision-only's eval budget; zero decision-level interference in 300 rows; attribution exactly additive; revision cuts aimed cost 35%; independently reproduces the taxfix migrations.
- **Aftermath:** ADOPTED as the production default configuration; bounded pre-existing shared-scratch coverage drift flagged (cleanliness fix, OPEN); next rounds run on the widened 8-target decisive band.

### [wcore/docs/research/conjunction_wall.md](wcore/docs/research/conjunction_wall.md)
- **Tried:** Attacked the distinct-count conjunction wall (round-b's 0.862 plateau vs the 0.95 bar) with two levers — a stepping-stone curriculum (climb membership→noveltyflag sub-conjunctions, promote, compose) and mechanism-level descriptors M=m_rel·m_perm·m_dup at the promotion gate.
- **Result:** Curriculum CROSSES it — frontier reach 0→6/9 both seeds at the round noveltyflag promotes (distinct = noveltyflag→g_add composes), 0 depth-4 leaks; mechanism descriptors fail (0/9); the wall is not climbable under any of 4 lenses (probe 0.875/0.839), confirming a gradient absence not a weak-lens artifact; selftest all-PASS.
- **Aftermath:** ADOPTED — the escape is a discovered intermediate abstraction promoted at the selection boundary (Closure Principle at the curriculum level), extending round-b's [aimed_forge.md](wcore/docs/research/aimed_forge.md); honest bound: stones hand-designed, auto-discovering the decomposition is the next frontier (OPEN).

---

## 15. Documentation gap-fill (2026-07-11) — built-but-undocumented experiments

### [sparse_poly_discovery/docs/research/oriented_control.md](sparse_poly_discovery/docs/research/oriented_control.md)
- **Tried:** Clifford Cl(2,0) grade-2 (bivector) readouts vs the mb_mass sum baseline on the REAL grid control task (dynamics are oriented: charge→anode, discharge→cathode), 8 seeds, pre-registered H1/H2/H3.
- **Result:** sum wins everywhere — single-band 19.80 vs bivector 50.70 (H2 confirmed), dual-band sum 35.10 vs bivector 77.73 (H3 refuted); grade-2 wins on the TOY oriented predicate (1.000 on sign(v1−v0)) but not the real task.
- **Aftermath:** ADOPTED — closes A10's open caveat: the escape lever was "leave GF(2)," not the geometric product; grade-2 pays only when the target CONSTRAINT is oriented, and the real control constraint is symmetric mass-band (an oriented environment ≠ an oriented objective). Links [a10_clifford_binding.md](sparse_poly_discovery/docs/research/a10_clifford_binding.md).

### [boundary_crossing/docs/research/lm_baseline.md](boundary_crossing/docs/research/lm_baseline.md)
- **Tried:** Documented the built-but-unrun LLM-as-addition-chain-generator baseline: `claude -p` proposes a chain per target, every reply forced through the SAME independent verifier (`addchain_check`) the engine uses; cost measured in API calls.
- **Result:** N/A — harness built, not run (running makes live API calls, the user's call). No results claimed.
- **Aftermath:** OPEN — the fair AlphaEvolve head-to-head (LLM proposer + our sound verifier vs the engine + same verifier); when run, results go to `results/lm_baseline_<date>.csv`. Distinct from [llm_proposer.md](boundary_crossing/docs/research/llm_proposer.md).

---

## 16. Research round 2026-07-10d — does MORE go further? (breadth / diversity / non-human grammars)

### [docs/research/research_round_2026_07_10d.md](docs/research/research_round_2026_07_10d.md)
- **Tried:** Six experiments testing the user hypothesis (thinks-like-humans; pump-more-diverse-at-once), made falsifiable: breadth-vs-depth, breadth scaling law, non-human grammar, LABS swarm, auto-curriculum, diversity predictor.
- **Result:** In progress.
- **Aftermath:** OPEN — live round master doc, updated per landing.

### [wcore/docs/research/nonhuman_grammar.md](wcore/docs/research/nonhuman_grammar.md)
- **Tried:** Whether bulk machine-invented (non-human) atom grammars reach a proven out-of-human-family target (descent-parity, a streaming C09 analogue) that human-family proposers can't — testing "the ceiling is that it thinks in human primitive families."
- **Result:** Refuted both ways — 92.4% (1109/1200) of forged atoms are genuinely non-human (joint behavioral + opcode criterion), so it is NOT confined to human families; but the machine-atom pool reaches only ~chance (0.519 re-verified) on the target, WORSE than raw search (0.713) and human-op search (0.691) at equal budget; no arm crosses 0.95 (hand-written alien control confirms it IS solvable at 1.000).
- **Aftermath:** ADOPTED — grammar-level confirmation that the ceiling is AIM not grammar (escaping closure is cheap, escaping toward a target needs direction); consistent with [aimed_forge.md](wcore/docs/research/aimed_forge.md) and [conjunction_wall.md](wcore/docs/research/conjunction_wall.md).

### [boundary_crossing/docs/research/labs_swarm.md](boundary_crossing/docs/research/labs_swarm.md)
- **Tried:** Whether a diverse strategy swarm (3-arm / 9-arm pools, equal + adaptive allocation) beats a single concentrated arm on the 12 open LABS even-N gaps at EQUAL total budget (50M evals) — the round-b "concentrate beats split" rematch done apples-to-apples.
- **Result:** Diversity won 9/12 at equal budget (reverses round b), but the best single arm led all 48/48 pool runs (avg 3.25-3.5/9 arms contributed) — the edge is restart-diversification of one strategy, not diverse strategies winning; vs best prior number 2/12 improved, 3/12 tied, 7/12 regressed; no record; verifier 12/12, 2/2 lies caught.
- **Aftermath:** MODIFIED — refines [labs_even_n.md](boundary_crossing/docs/research/labs_even_n.md)'s "concentrate" lesson (diversity helps at equal budget but as restart-diversification, not structural diversity); records still need new theory / B&B (OPEN).

### [docs/research/breadth_scaling.md](docs/research/breadth_scaling.md)
- **Tried:** The H50 depth-plateau counterpart for parallelism — sweep N ∈ {1,2,4,8,16,32} diverse proposers at fixed per-proposer budget, measure union out-of-closure reach; the N-identical control isolates diversity from quantity.
- **Result:** Breadth plateaus like depth — diverse reach flat at 1 across all N; identical copies reached 2 at N=32, so diversity did NOT help; the plateau is a representability boundary (brute-verified: only 4/15 cells representable, C09 provably at chance 0.5343); breadth beats single-shot depth in the needle regime (independent re-selection) but is ~3 orders worse than in-closure escalation and neither crosses the closure boundary.
- **Aftermath:** ADOPTED — the breadth-scaling law: neither breadth nor diversity is a structural lever on a genuinely out-of-closure family, exactly parallel to [scaling_laws_h50.md](docs/research/scaling_laws_h50.md); confirms the ceiling is representability/aim, not quantity.

### [docs/research/diversity_predictor.md](docs/research/diversity_predictor.md)
- **Tried:** Regress out-of-closure reach against generator diversity D vs proposer count N vs eval budget over 285 pool configs, with an N-identical (D=1) control and two falsification targets; the round's unifying theory experiment.
- **Result:** D predicts reach (R²=0.405, partial 0.607) — dominant over N (partial −0.058) and budget (0.092); every D=1 row = 0 reach; conditional on D spanning the target's closure (wrong-direction diversity solves nothing; narrow-margin conjunctions still fragile at 13.5%); two bugs fixed (test-split leakage, unequal solo combo budget).
- **Aftermath:** ADOPTED as the round's unifying law — reconciles with [breadth_scaling.md](docs/research/breadth_scaling.md): diversity is the escape resource iff it spans the target's closure (D2's single-closure targets → concentrate; D6's multi-closure targets → diversify); "pump more DIFFERENT" validated conditionally, "pump more of the same" refuted.

### [wcore/docs/research/auto_curriculum.md](wcore/docs/research/auto_curriculum.md)
- **Tried:** Replaced round c's hand-designed stepping stones with a mechanism-blind generate-and-filter loop (bulk random programs + archive prefixes; filter = depth-3&4 certifiable AND makes a wall target composable at depth ≤3); swept bulk 0→1000 candidates/round × 2 seeds.
- **Result:** ZERO stones discovered — reach 0/9 both seeds at every bulk size vs the hand-curriculum's 6/9; 54,432 candidate-behaviours, n_payoff_pos = n_certified = 0 every round; 20× more bulk changed cost not outcome; positive control confirms detection works (S1 payoff 0/7, S2 6/7) so the failure is entirely in generation.
- **Aftermath:** ADOPTED as the round's capstone negative — quantity does NOT substitute for insight when the insight isn't cheap to stumble into; sharply bounds "pump more out at once"; localizes the missing capability to GENERATION (motivates Round E's E2 learned-aim / E3 auto-family). Successor to [conjunction_wall.md](wcore/docs/research/conjunction_wall.md).

---

## 17. Research round 2026-07-11 (Round E) — aim × representability

### [docs/research/research_round_2026_07_11.md](docs/research/research_round_2026_07_11.md)
- **Tried:** Six experiments attacking the arc's two proven levers: E1 representability expansion, E2 learned aim/target router, E3 smart generation for auto-discovery (the D5 pivot), E4 aimed engine on an open target, E5 aim×representability predictor, E6 coevo matcher audit.
- **Result:** COMPLETE (6/6) — representability grows by hand (E1) and the machine can auto-discover a missing mechanism with a tiny prior (E3); aim automates (E2) and buys efficiency not ceiling (E4); the law is quantified (E5); instruments hold (E6).
- **Aftermath:** ADOPTED — closes the 5-round arc (32 experiments): reach = representable ? aim-decides : 0; the next lever is machine-driven representability expansion via learned structural priors.

### [docs/research/aim_repr_predictor.md](docs/research/aim_repr_predictor.md)
- **Tried:** The theory capstone — regress reach against representability, aim-quality, diversity, and budget over 6,480 cells; test for a phase boundary (does aim only matter once representability is satisfied?).
- **Result:** Representability dominates (R²=0.652, 5–100× every other factor); aim is a sharp phase boundary — corr(aim,reach) 0.00/0.00/0.18 across LOW/MID/HIGH representability, solve rate 0%/0%/45.9%; diversity (D6) is a proxy for representability (corr 0.60) and flips negative once representability is controlled; falsification clean; fixed the D6 same-family-combo fairness bug (33%→0%).
- **Aftermath:** ADOPTED as the four-round arc's quantitative law — reach ≈ representable ? aim-decides : 0; retroactively explains [diversity_predictor.md](docs/research/diversity_predictor.md); provably narrows the levers to E1 (representability) + E2 (aim), with E1 gating E2.

### [boundary_crossing/docs/research/aimed_open.md](boundary_crossing/docs/research/aimed_open.md)
- **Tried:** The honest new-to-humanity attempt — point an AIMED search (residual-autocorrelation steering, clean aim on/off ablation) at LABS N=61 (closest open gap, 4 above best-known) and secondary N=48, aimed vs undirected at equal budget, all claims independently verified.
- **Result:** Aim buys efficiency/reliability (N=61 6/6 vs 5/6 seeds reach the E=230 floor, strict low-budget win) but NOT ceiling-crossing — both arms plateau at E=230 even at 500M evals (a hard representability floor); aim's biggest win was on the less-representable N=48 (148 vs 160); no record; 8/8 verified, planted-lie refuted.
- **Aftermath:** ADOPTED — confirms E5's law from the open-target side (aim is an efficiency lever, decisive only where representable structure exists); records still need a representability escape (new theory / B&B), not more aim or budget.

### [docs/research/target_router.md](docs/research/target_router.md)
- **Tried:** Whether aim generalizes from a fixed handed-in lens to a LEARNED selector — a k-NN router over a 10-feature failure descriptor picks among 3 aim mechanisms (base, gf2_joint, spectral_acc), vs fixed-best and random, on held-out targets with train/val/test split.
- **Result:** Router 12/13 (92.3%) held-out vs fixed-best 46.2% vs random 7.7%, and cheaper (4,701 vs 6,084 evals); ties fixed-best at n≤16 labeled examples, crosses by n=24; leakage guard caught a real duplicate-target leak; 12/12 solves re-derived by exact mask/statistic recovery.
- **Aftermath:** ADOPTED — the aim lever automates (a learned router beats fixed/random); consistent with [aim_repr_predictor.md](docs/research/aim_repr_predictor.md) (aim operates above the representability threshold, the router picks the right aim there); the 3 mechanisms are round-c's own lenses (selection automated, not new capability).

### [wcore/docs/research/coevo_matcher_falsification.md](wcore/docs/research/coevo_matcher_falsification.md)
- **Tried:** Mirror round-c's matcher-falsification method onto the coevo-side 12×32 matcher (inv_coevo.behaviorMatches, 0.95 threshold) named by round c as the next audit target — reproduce the 85/86 corpus from scratch, then hunt false-equals / false-differents / seed-flips and derive a corrected protocol.
- **Result:** Same false-equal bug class confirmed (7/9 constructed adversaries fool production at 100% of seeds, witnessed; random 20k found 0 — construction-driven), 1 census false-equal (0.87%) but 0/86 in the fingerprint-novel bucket → the 85/86 headline stands; false-different 0/1200; seed-flip 0/11,500; corrected exact-64×256 protocol cheaper (1ms vs 12ms), re-confirms 115/116.
- **Aftermath:** ADOPTED — closes round c's named follow-up ([matcher_falsification.md](wcore/docs/research/matcher_falsification.md)); the Claim-C 85/86 breadth headline survives the audit; corrected exact protocol recommended for the coevo matcher too; dev_k7/k8 sub-2e-4 deviators remain the irreducible finite-sample residual (OPEN, same as the sibling matcher).

### [docs/research/repr_expansion.md](docs/research/repr_expansion.md)
- **Tried:** Grow the ladder's expressible family menu under the certifier (thresh, mixr, ratio, run), each unlock proven unrepresentable before via Bayes ceilings then certified after; measure the closure-expansion lattice + battery-B/D regression.
- **Result:** mixr unlocks MIXMOD1 (.682→1.000), ratio unlocks RATIO1 (.582→1.000), thresh 0, 0 regressions; three outcome categories — family-unlocked (2 fresh targets), a standing unrepresentable core (GF(2)-XOR wall + ORDER2, ceiling .646), and RUN1 (representable exact-1.000 member but R²-novelty-gate-blocked = a certifier boundary, not a family boundary).
- **Aftermath:** ADOPTED — representability grows by hand (the E5 ceiling lever is movable), but ORDER2 is the standing family-boundary frontier (motivates E3 auto-family discovery) and RUN1 exposes a new distinct boundary type (the novelty certifier can reject a genuine expression); links [tier8_reach_gap.md](docs/research/tier8_reach_gap.md), [aim_repr_predictor.md](docs/research/aim_repr_predictor.md).

### [wcore/docs/research/smart_gen.md](wcore/docs/research/smart_gen.md)
- **Tried:** The round crux — keep D5's proven detector, swap in smart generators (gradient hill-climb, memory-bias sampling, forced-signature sampling, exhaustive behaviour-deduped coverage + signature-as-inclusion) to auto-discover the conjunction-wall decomposition D5's blind bulk couldn't.
- **Result:** Gradient/sampling/forced-sampling all fail (0/9, like D5); exhaustive coverage + the load;store-signature as a coverage INCLUSION crosses 0/9→6/9 both seeds, matching the hand curriculum, rediscovering noveltyflag from scratch (genuine, structurally distinct, clean at depth 4); ablation pins the minimal prior (coverage-alone 0/9, signature-as-sampling 0/9); generation is hard (no partial payoff, needle completion, length-3 uncoverable without steering).
- **Aftermath:** ADOPTED as the crux bound — human insight is partially (not fully) dispensable: the machine auto-discovers with a structural prior strictly smaller than a hand curriculum, so the frontier moves without vanishing; the generation-side analogue of E5's representability gate; successor to [auto_curriculum.md](wcore/docs/research/auto_curriculum.md) and [conjunction_wall.md](wcore/docs/research/conjunction_wall.md).

---

## 18. Research round 2026-07-11b (Round F) — the generator-of-generators

### [docs/research/research_round_2026_07_11b.md](docs/research/research_round_2026_07_11b.md)
- **Tried:** Six experiments building the arc's named next lever (machine-driven representability via learned structural priors): F1 infer-the-prior, F2 auto-family for ORDER2, F3 RUN1 novelty-gate audit, F4 prior transfer, F5 assembled generator-of-generators, F6 residual human-insight bit.
- **Result:** COMPLETE (6/6) — ORDER2's missing family is machine-discovered; mechanisms and priors transfer; the assembled loop reaches 58/73 vs hand 59/73. But F1 is invalid/inconclusive, F3 finds a known-bad novelty gate, and full autonomy is not established.
- **Aftermath:** MODIFIED — a compounding partially autonomous representability engine exists; the generator-of-generators claim remains OPEN pending a leakage-clean production-derived selector and a rerun under F3's corrected gate.

### [docs/research/insight_ledger.md](docs/research/insight_ledger.md)
- **Tried:** Quantify how much of the insight to solve a target is machine-supplied vs human-supplied per arc method (hand-curriculum / D5 blind bulk / E3 smart-gen / F1 projected), via a 9-unit ingredient decomposition tagged human-vs-machine, plus an independent bit-narrowing cross-check.
- **Result:** Machine-supplied fraction 0% (hand-curriculum) → 66.7% (E3, cross-check 70.7%); D5 = 0/9 (insight never assembled); F1 projected ~85–90% (unmeasured, honest); trend 100%→33% human-supplied (~3× drop, shrinking not vanishing); irreducible floor = alphabet + certifier + target + protocol; COVER-fair vs COVER-uniform (identical bits eliminated, only one solves) proves the prior's value is aim not quantity.
- **Aftermath:** ADOPTED as the arc's honest accounting — the residual human bit shrinks measurably but has a floor (the verifier definition); echoes [aim_repr_predictor.md](docs/research/aim_repr_predictor.md) at the insight scale; the "greatest invention machine" distance is now a tracked number.

### [docs/research/run1_gate_audit.md](docs/research/run1_gate_audit.md)
- **Tried:** Audit whether the novelty gate's rejection of E1's exact RUN1 member run(maxRunGE3) is correct de-dup or a false rejection — two generous greedy multi-feature reconstruction searches from the count basis + genuine-remix controls + a threshold ROC.
- **Result:** The gate is OVER-REJECTING — run(maxRunGE3) is genuinely irreducible (0.887 acc / R²=0.80 ceiling vs the run family's instant 1.000, remixes hit ≥0.998); the single-column linear-R² statistic is non-monotonic in true reconstructibility (ranking AUC 0.889; the inversions are exactly RUN1 & RUN-var2, irreducible, ranked above an exactly-reconstructible target), false-rejection 33% among novel targets, no threshold in [0.10,0.90] achieves zero errors (axis problem).
- **Aftermath:** ADOPTED — corrected measure (multi-feature COVER reconstruction reusing the existing certifier constant) recovers every established verdict and admits RUN1+RUN-var2; the third instrument-trust win of the arc (mirrors [tier8_gate_v5.md](docs/research/tier8_gate_v5.md)'s wrong-axis→right-axis fix); the novelty gate was silently costing the program genuine capabilities.

### [docs/research/autofamily_order2.md](docs/research/autofamily_order2.md)
- **Tried:** Generalize CMP's five fixed pair sets into an exhaustive subset-conditioned comparison-family search, then ask whether it independently discovers the missing family for E1's standing-unreachable ORDER2 target.
- **Result:** Yes — all four seeds, including a held-out seed, select `between({cell 0}) mod 2` at val=tst=1.000 from 50,490 candidates; a production-style ladder moves ORDER2 0.582→1.000 with zero regressions across Battery B plus controls.
- **Aftermath:** ADOPTED — the machine found the distinguished-cell family rather than being handed its member; the remaining supplied insight is the bounded comparison-shape prior, making this a clean low-dimensional representability-expansion result.

### [docs/research/genofgen_assembled.md](docs/research/genofgen_assembled.md)
- **Tried:** Assemble learned routing, signature probing, exhaustive family search, certification, and within-pass promotion into one autonomous 73-target loop, with hand-oracle, no-smart-generation, and no-router controls over three seeds.
- **Result:** Positive coherence, negative full equivalence — autonomous 58/73 vs hand 59/73; smart generation is load-bearing (36–37/73 without it; frontier 3/10→8/10), while routing preserves the ceiling and reduces mean evaluations 45,029→30,546 (32.2%).
- **Aftermath:** MODIFIED — adopt the integration and ablation result, not a full generator-of-generators victory; rerun with F3's corrected novelty gate and F1's inferred selector, and retain the honest blind-control caveat on WALL_HARD.

### [wcore/docs/research/prior_selector.md](wcore/docs/research/prior_selector.md)
- **Tried:** Learn a k-NN selector over failure descriptors for four structural-prior pools on a fresh proxy VM, with target-level splits and fixed/random controls.
- **Result:** INCONCLUSIVE — the instrument fails before learner evaluation: own-prior recall 14/20 vs no-prior 12/20, non-binary and degenerate targets, cross-family collisions, zero train/test descriptor distance, and router/fixed/random tied at 3/4.
- **Aftermath:** REBUILD REQUIRED — no positive or clean negative on learned priors; F6's 85–90% estimate remains projected. Require a binary non-degenerate battery, 20/20 own-prior reachability, meaningful exclusive labels, and a leakage-clean frozen split before rerunning.

### [wcore/docs/research/prior_transfer.md](wcore/docs/research/prior_transfer.md)
- **Tried:** Withhold or retain E3's promoted mechanism across ten held-out targets, comparing full transfer, prior-only regeneration, and equal-size cold generation.
- **Result:** Layered positive — the promoted atom composes into 5/10 targets at 0–4 ms and cuts total evaluation time 57.9%; the structural prior reaches 9/10 versus cold 2/10, while new siblings still need fresh generation.
- **Aftermath:** ADOPTED — discoveries amortize strongly through downstream composition and priors transfer across siblings, but atoms do not automatically stand in for whole families and one deeper target remains unreachable in every arm.

---

## 19. Research round 2026-07-11c (Round G) — remove the human prior choice

### [docs/research/research_round_2026_07_11c.md](docs/research/research_round_2026_07_11c.md)
- **Tried:** Repair the two blockers to the Round-F generator-of-generators claim—an over-rejecting novelty gate and invalid prior-selector corpus—then test learned selection and prior invention under frozen controls.
- **Result:** Live; G1 has landed.
- **Aftermath:** OPEN — only an end-to-end run with accepted gate/corpus can establish removal of the human per-target prior choice.

### [docs/research/gate_v6_round_g.md](docs/research/gate_v6_round_g.md)
- **Tried:** Replace F3's single-column R² novelty decision with candidate-excluded greedy multi-feature held-out-label COVER reconstruction, frozen over the original six-novel/three-remix battery.
- **Result:** 7/9→9/9 correct; both novel false rejections are repaired (2/6→0/6), while all three remix rejections remain correct (0/3 false admits).
- **Aftermath:** ADOPTED as Round G's decision-layer certification standard, with the explicit requirement that G5 execute it live before any production-wiring claim.

### [docs/research/prior_corpus_round_g.md](docs/research/prior_corpus_round_g.md)
- **Tried:** Rebuild F1's invalid proxy corpus from production-shaped 8-cell targets, with executable prior witnesses, quantitative/exclusive benefits, frozen 12/4/4 split, and descriptor leakage guards.
- **Result:** VALID — all 20 targets pass binary/non-degenerate, designated-prior exactness, benefit, and exclusivity checks; minimum standardized train-to-validation/test descriptor distance is 0.792565, above the 0.05 duplicate-warning gate.
- **Aftermath:** ADOPTED as the frozen input to G3; it establishes corpus validity only, not learned-selector performance.

### [docs/research/prior_invention_round_g.md](docs/research/prior_invention_round_g.md)
- **Tried:** After fixed threshold-menu failure plus an orientation-residual probe, search a fixed directed-partition comparison/residue grammar symmetrically for a held-out rank-modulo target; compare fixed-menu and random controls.
- **Result:** Constrained positive — it selects `mask=0x08, mod3==1` and reaches 1.000 validation/test on three seeds plus a held-out fourth, versus fixed-menu ≤0.647 and random ≤0.627.
- **Aftermath:** ADOPTED as grammar/parameter-level prior invention inside a human-provided primitive alphabet; it is not primitive invention and cannot be production-promoted until G1's live gate re-certifies it.

### [docs/research/prior_selector_round_g.md](docs/research/prior_selector_round_g.md)
- **Tried:** Fit a validation-selected 1-NN selector over only G2's six allowed behavioural descriptors, then compare it with fixed order and a frozen random arm on G2's untouched held-out targets under matched witness-evaluation budgets.
- **Result:** VALID NEGATIVE — all split and leakage gates pass (minimum distance 0.792634 > 0.05), but learned routing reaches 0/4 held-out versus fixed 1/4 and random 0/4 (uniform expectation 1/4).
- **Aftermath:** REJECTED for autonomous routing — the current six-descriptor nearest-neighbour design does not remove the human prior-choice bottleneck; G5 cannot claim an end-to-end autonomy result with it.

---

## 20. Research round 2026-07-12 (Round H) — failure evidence to autonomous prior choice

### [docs/research/research_round_2026_07_12.md](docs/research/research_round_2026_07_12.md)
- **Tried:** Turn Round G's constrained grammar-invention positive into trustworthy autonomous prior choice, while testing richer failure evidence, equal-budget proposing, and live corrected certification.
- **Result:** SETTLED — H1 is a valid negative and blocks H2; H3/H6 demonstrate constrained direct proposal (assembly 3/4 vs hand 4/4, fixed/cold 1/4); H4 narrows the regime; H5 supplies live gate evidence.
- **Aftermath:** MODIFIED — the result is reliable aiming inside a supplied singleton grammar regime, not autonomous general prior choice; next work must learn from search response and admit multi-cell directed structure.

### [docs/research/failure_repr_round_h.md](docs/research/failure_repr_round_h.md)
- **Tried:** Audit generic residual/orientation/probe-response descriptor banks under G2's frozen 12/4/4 split and train-only normalization, selecting the contract on validation only.
- **Result:** VALID NEGATIVE — validation-selected `full16` reaches 4/4 validation but only 1/4 untouched holdout, equal to fixed routing; leakage distance is 1.448328 > 0.05.
- **Aftermath:** REJECTED as an H2 input — adding static generic response correlations does not repair routing; future work must use a different observation, such as actual equal-budget search response.

### [docs/research/direct_proposer_round_h.md](docs/research/direct_proposer_round_h.md)
- **Tried:** Let labelled failure behaviour open a generic directed-partition grammar, then enumerate it symmetrically and compare global-threshold and blind directed search at the same 1,270 candidate evaluations.
- **Result:** CONSTRAINED POSITIVE — direct proposal is exact on three seeds and a held-out pivot/modulus variant; threshold menu is ≤0.649, while equal-budget blind directed search has 0.484–0.734 exact-hit frequency across 64 trials per data set.
- **Aftermath:** ADOPTED as reliable aiming inside a finite human-supplied grammar, not as primitive invention or proof of broad random-search separation; H6 may use it as a proposer input under live certification.

### [docs/research/gate_v6_live_round_h.md](docs/research/gate_v6_live_round_h.md)
- **Tried:** Execute G1's candidate-excluded multi-feature COVER rule live inside a deterministic promotion loop over RUN1, RUN-var2, a known count remix, and a G4-type directed candidate; compare legacy raw-R² decisions.
- **Result:** POSITIVE LIVE EVIDENCE — v6 is 4/4 correct versus legacy 2/4, admits both RUN novelties, preserves the remix rejection, and promotes 3 candidates versus legacy's 1.
- **Aftermath:** ADOPTED for the next experimental assembly as a live-tested certification standard; not production-adopted because the compact four-control synthetic loop does not establish broader engine economics.

### [docs/research/prior_invention_audit_round_h.md](docs/research/prior_invention_audit_round_h.md)
- **Tried:** Adversarially retest G4/H3 across pivots, moduli, residues, equal 1,270-candidate blind-directed controls, and a held-out two-cell partition.
- **Result:** MIXED — singleton variants are exact and robust, but equal-budget blind search exact-hits 56.25–68.75% of trials and the representable two-cell variant fails the singleton-orientation admission signal (0.592 < 0.75).
- **Aftermath:** NARROWED — the evidence supports selection inside a human-supplied singleton regime, not broad directed-partition grammar invention or a decisive random-search advantage.

### [docs/research/genofgen_round_h.md](docs/research/genofgen_round_h.md)
- **Tried:** Assemble H3's direct failure-guided proposer with H5's live candidate-excluded v6 promotion, comparing hand, fixed/cold, equal-budget random, no-signature, and no-v6 arms on held-out directed variants plus a threshold control.
- **Result:** CONSTRAINED PARTIAL POSITIVE — direct proposal exact-promotes 2/3 directed variants and safely declines the third; the full assembly reaches 3/4 versus hand 4/4 and fixed/cold 1/4.
- **Aftermath:** ADOPTED as a bounded direct-proposer path, not a learned router or human-structural-language escape; H4's two-cell miss marks the exact next representational gap.

---

## 21. Research round 2026-07-12b (Round I) — search response to general prior admission

### [docs/research/research_round_2026_07_12b.md](docs/research/research_round_2026_07_12b.md)
- **Tried:** Replace Round H's singleton-shaped static admission with target-agnostic search-response evidence, symmetric multi-cell admission, equal-budget scaling, allocation, and adversarial audit.
- **Result:** Live; I1 has landed as a limited positive.
- **Aftermath:** OPEN — static response atlas improves separation but has the decisive multi-cell/no-grammar confusion; allocator and audit are still required.

### [docs/research/search_response_atlas_round_i.md](docs/research/search_response_atlas_round_i.md)
- **Tried:** Build a 30-evaluation-per-route, target-agnostic micro-search response atlas across global, singleton-directed, partition-directed, and irrelevant routes, choosing descriptor contract only on validation.
- **Result:** LIMITED POSITIVE — gain/residual8 scores 4/4 validation and 2/4 untouched holdout, improving on H1's static 1/4 but confusing multi-cell and no-grammar; leakage/copy distance is 0.038243 >= 0.03.
- **Aftermath:** ADOPTED only as I3 input — it supports a predeclared allocator test, not an autonomous routing claim.
