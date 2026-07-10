# Research Round 2026-07-10 — eight parallel experiments toward "way better than AlphaEvolve"

**Status:** LIVE — updated as each experiment lands. 3/8 complete.
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
| 5 | Tax gate as promotion gate (A/B/C) | pending | — | `docs/research/tier8_tax_gate_promotion.md` |
| 6 | Tier 8 framework-revision ablation | pending | — | `docs/research/tier8_ablation.md` |
| 7 | H50–H52 scaling laws | pending | — | `docs/research/scaling_laws_h50.md` |
| 8 | I53 falsification + G49 cross-audit | pending | — | `docs/research/i53_falsification_2026_07_10.md` |

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

*(Sections for experiments 2, 5, 6, 7, 8 to be added on completion.)*
