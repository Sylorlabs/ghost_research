# Non-human grammar — do machine-invented atoms escape the human-family wall? (round 2026-07-10d)
> **Belongs to: Round 2026-07-10d · experiment 3 of 6 (non-human grammar)** — [round index](../../../docs/research/research_round_2026_07_10d.md).

**Date:** 2026-07-11 (round 2026-07-10d)
**Runner:** `wcore/src/nonhuman_grammar.zig` (new standalone file; imports
`inv_alien` / `inv_coevo` / `inv_open` / `inv_atomforge` / `inv_frontier`
read-only; modifies nothing).
**Build:** `cd wcore && zig build-exe -O ReleaseFast src/nonhuman_grammar.zig -femit-bin=bin/nonhuman_grammar` (Zig 0.14.1)
**Run:** `./bin/nonhuman_grammar selftest` then `./bin/nonhuman_grammar full ../results/nonhuman_grammar_2026_07_10.csv --nseeds=24 --reach_cap=120`
**Data:** `results/nonhuman_grammar_2026_07_10.csv` (1251 data rows)
**Runtime:** 3m42s wall, single-threaded, deterministic per seed.

## The hypothesis under test

Micah's intuition ("it thinks the same way as humans"): the operative ceiling on
the whole atom-forge / Tier-8 arc is that **every primitive FAMILY the engine uses
is a human-conceived one** — XOR, mod, Walsh, comparison-aggregates, per-key
accumulators. If that framing is the ceiling, then **machine-invented, non-human
atom grammars** — bulk atom-forge output, *not* hand-picked human family solvers —
should let the loop reach targets that no human-family proposer can. This round
builds the bulk machine-atom grammar and measures, against a target proven outside
every human family, whether it escapes.

Culture (mandatory): "machine-invented atoms span the same closures as human
families, no escape" is a valid finding — it would say the human-grammar framing is
*not* the ceiling. An atom is only counted "genuinely non-human" if it is *verified*
outside the human families both behaviourally and mechanistically, not assumed.

## What "non-human" is measured as (both criteria, per atom, jointly)

An atom counts GENUINELY_NON_HUMAN iff **both** hold:
1. **Behavioural:** its output does not match (≥0.95 agreement, the arc's bar) any
   depth-≤3 composition of the deduped human-family library — measured by exhaustive
   composition search, chain-vs-atom, 8×28 streams.
2. **Mechanistic:** it uses ≥1 opcode outside the human vocabulary, **and that
   opcode is load-bearing** — stripping every non-human-vocab instruction changes the
   atom's own behaviour (self-agreement < 0.95). An atom that merely *contains* an
   alien opcode but behaves identically once it is stripped is ALIEN_DECORATIVE, not
   counted as non-human.

## Phase 0 — the human-family library and vocabulary (verified, not assumed)

Ten hand-authored candidate mechanisms were deduped by direct behavioural agreement
and a non-degeneracy ("clean" = OUT_R entropy > 0.30) filter. Survivors — **6
distinct families:** `g_xor, g_add, pk_xor, pk_add, shift, hashtbl`. Dropped, with
reasons printed and logged:
- `union` ≡ `hashtbl` (agreement ≥ 0.95 under the OUT_R stream convention),
  `rmw_counter` ≡ `pk_add` (same);
- `distinct`-count and `xor_scan` fail the non-degeneracy filter under this 4-symbol
  alphabet (their OUT_R entropy ≤ 0.30 on the canonical stream) — a genuine, reported
  measurement, not a hand-exclusion.

**Human opcode vocabulary, scanned from the survivors (not hand-typed): 6 of the
substrate's 19 opcodes** — `a_set, a_mov, a_xor, a_add, a_load, a_store`. The other
13 (`a_and, a_or, a_sub, a_mul, a_shl, a_shr, a_rotr, a_popcnt, a_mum, a_bswap,
a_eq, a_sel`, plus `nop`) have **never** appeared in a human-authored mechanism in
this codebase. That 6-of-19 gap is the concrete substrate for "non-human."

## Phase 1 — the bulk machine-atom pool and its classification

**1200 machine-invented atoms** were forged across 18 diverse seeds (novelty search
pop=90 gens=45 + irreducibility census vs the 5 base atoms — the exact
`inv_atomforge`/`inv_iterate` protocol; the pool cap of 1200 was hit at seed 18 of
the requested 24, so the pool is not seed-starved). These are *bulk, unranked,
unaimed* — not hand-picked solvers.

Joint classification of the pool:

| class | count | fraction |
|---|---|---|
| **GENUINELY_NON_HUMAN** (both criteria) | **1109** | **92.4%** |
| ALIEN_DECORATIVE (alien op present but not load-bearing) | 86 | 7.2% |
| ALIEN_MECH_HUMAN_FUNC (alien op load-bearing but behaviour spans a human family) | 4 | 0.3% |
| HUMAN_VOCAB (only human opcodes) | 1 | 0.1% |

**The premise's factual claim is false.** The forge does not re-derive human
families under new names: **92.4% of bulk atoms are provably outside the human
families** — behaviourally (0 of the 1109 span any human composition at ≥0.95) *and*
mechanistically (each uses a load-bearing opcode no human mechanism here uses).
Behavioural distance is not marginal: **938/1200 (78%) sit below 0.60 agreement with
*every* depth-≤3 human composition** (only 4/1200 reach the 0.95 human-span bar). The
non-human atoms lean heavily on `a_or, a_sub, a_mum, a_sel, a_eq, a_popcnt, a_mul,
a_rotr` — exactly the comparison/bit-mixing ops the human grammar lacks.

So the human-grammar framing is *not* what the forge is stuck inside. The sharp
question is the next one: does that genuine non-humanness buy reach?

## Phase 2 — the out-of-family target and its wall

**Target: descent-parity** — `out[i] = parity of #{ j ≤ i : sym[j] < sym[j-1] }`, a
running ORDER-RELATION aggregate. It is the streaming analogue of Tier 8's C09
(inversion-count parity), the family-level wall proven by Bayes ceilings in
`docs/research/tier8_reach_gap.md`. Order relations are outside every human family
here (all are value-accumulators or content-addressers; none compares adjacent
symbols).

**Feasibility positive control:** a hand-written 5-instruction alien program using
`a_sub` + `a_shr` (carry prev, subtract, extract the wraparound sign bit) computes
descent-parity **exactly (agreement 1.000)**. So the target IS reachable in the
substrate — a downstream "no reach" means "search didn't find it," not "nothing
could."

**The wall (human grammar cannot reach it):**

| human-grammar arm | best agreement | vs 0.95 bar |
|---|---|---|
| each human atom alone (6) | 0.221 – 0.367 | far below |
| human-family exhaustive depth-≤3 composition (258 combos) | **0.482** | far below |
| human-op-restricted raw search (300k evals/seed, 2 seeds) | **0.700** | far below |

No human-grammar approach — named atoms, their compositions, or a from-scratch
search restricted to the 6 human opcodes — clears 0.70. The family-level wall
reproduces on this fresh target.

## Phase 3 — the reach test (equal budget) — the headline

The machine-atom pool's best 120 atoms (non-human prioritised) were composed
exhaustively at depth ≤3 (1,742,520 combinations), and that combination count was
used as the **equal evaluation budget** for two from-scratch search controls.

| arm (equal budget = 1,742,520 evals) | best agreement |
|---|---|
| human-family composition (258 combos) | 0.482 |
| **MACHINE-ATOM-POOL composition (depth ≤3)** | **0.638** (search sample) → **0.519** (independent) |
| human-op-restricted search (matched budget) | 0.691 |
| unrestricted raw search, full 19-op set (matched budget) | 0.713 |

**Nothing crosses the 0.95 bar. Nothing solves.** And the ranking is the refutation:
at equal budget the **machine-atom grammar is the *worst* of the three
search-capable arms.** Its 0.638 is a maximum over 1.74M fixed-sample evaluations
(an overfit peak); re-verified on an independent, larger, disjoint-seed sample
(48×96) the best machine chain drops to **0.519 — essentially chance** for this
{0,1}-valued target. A depth+1 neighbourhood probe around that chain buys nothing.

Meanwhile a from-scratch raw search *with the same non-human ops available* also only
reaches 0.713 — so even direct access to `a_sub`/`a_shr`/`a_eq`/`a_sel` does not
surface the hand-written feasibility solver at this budget. Descent-parity is a
gradient-poor SEARCH target regardless of grammar.

## Phase 4 — the sharp question, answered

**Is any *winning* atom provably non-human?** There is no winner: no arm crosses
0.95, and the best machine chain generalises to ≈chance. The three atoms of that best
machine chain *are* each provably GENUINELY_NON_HUMAN (load-bearing
`a_sub/a_mul/a_rotr/a_popcnt/a_eq/a_sel/a_mum/…`, behavioural human-span ≤ 0.607) —
but they compose to a non-solve. **Non-human atoms are real and abundant; a
non-human atom that *reaches the out-of-family target* does not exist in this pool.**

## Verdict

**The "thinks like humans" (human primitive families) framing is refuted as the
mechanism of the wall — and refuted in *both* directions:**

1. **The premise is empirically false.** The atom-forge bulk-produces genuinely
   non-human atoms: 92.4% of 1200 are provably outside the human families,
   behaviourally and mechanistically; 78% are behaviourally far (<0.60) from every
   human composition. The engine is *not* confined to human-conceived grammars.
2. **The hoped-for consequence does not follow.** Replacing human grammar with bulk
   machine grammar buys **no** out-of-family reach. On a target proven outside every
   human family (human grammar caps at 0.70), the machine-atom-pool composition
   reaches only 0.638 in-sample / **0.519 out-of-sample (≈ chance)** — *worse* than
   both a matched-budget human-op search (0.691) and a matched-budget unrestricted
   search (0.713). None solves; the feasibility control proves the target is solvable.

The operative ceiling is therefore **not the human-family grammar — it is aim.**
Unaimed novelty produces non-human atoms whose behaviours scatter across descriptor
space in random directions; bulk composition of that scatter does not converge on a
specific out-of-family mechanism any better than from-scratch search does. This is
the grammar-level confirmation of the a1a6 finding ("escaping closure is cheap;
escaping *toward* a target you care about is the unsolved part") and of the
conjunction-wall result (the escape lever is a *directed* stepping-stone curriculum,
not a richer primitive supply). Non-human ≠ useful-for-this-target. Bulk
machine-atom breadth is not, by itself, a wall-crossing lever.

## Honest scope / limitations

- One target (descent-parity), one substrate, depth-≤3 composition, 0.95/8×28
  matcher — the arc's standard bar, but statistical (the independent-sample
  re-verification is exactly why the 0.638→0.519 drop is reported as the honest
  number).
- The reach test caps the machine pool at 120 atoms (of 1200) for the exhaustive
  depth-3 sweep (1.74M combos, 73 s); a larger pool would raise the combo count
  super-cubically. The equal-budget search controls were given that same 1.74M count,
  so the comparison is fair, but "more machine atoms" at deeper composition is
  enumeration-open beyond this budget and is the obvious next probe.
- "Genuinely non-human" is relative to *this* codebase's human-authored mechanisms
  and their 6-opcode vocabulary; it is a within-substrate operational definition, not
  a claim about human mathematics writ large.
- The feasibility control shows the target is reachable but was hand-written; whether
  an *aimed* forge (residual-coupled, as in `inv_aimed.zig`) could invent an atom
  that composes to descent-parity is the direct follow-up — this round tested *bulk
  unaimed* breadth specifically, and it does not cross.

## Files

- Harness: `wcore/src/nonhuman_grammar.zig` (selftest + full; 4 phases, one binary)
- Data: `results/nonhuman_grammar_2026_07_10.csv`
- Related: `wcore/docs/research/a1a6_iterated_promotion.md` (escaping closure is
  cheap, escaping toward a frontier is not), `wcore/docs/research/conjunction_wall.md`
  (the escape lever is a directed curriculum, not richer supply),
  `wcore/docs/research/aimed_forge.md` (frontier-coupled forge — the aimed
  counterpart this round's bulk-unaimed result points to),
  `docs/research/tier8_reach_gap.md` (C09 order-statistic family-level wall this
  target is modelled on)
