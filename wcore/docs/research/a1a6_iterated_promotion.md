# A1–A6: Iterated atom promotion — fixed point, generalisation, retro-reduction audit

**Date:** 2026-07-10
**Runner:** `wcore/src/inv_iterate.zig` (new standalone file; imports existing wcore
sources read-only, ports the two private chain helpers from `inv_atomforge.zig`)
**Build:** `zig build-exe -O ReleaseFast src/inv_iterate.zig` (Zig 0.14.1)
**Data:** `results/a1a6_openatom_2026_07_10.csv`
**Runtime:** 2m14s total, single-threaded, 2 seeds (0xA70F, 0x5EED2)
**Reproduce:** `./bin/inv_iterate ../results/a1a6_openatom_2026_07_10.csv 0xA70F 0x5EED2 --pop=90 --gens=45 --rounds=10`

## Loop design

Per round (same protocol family as `inv_atomforge.runPromotionSnapshots`):

1. **Forge:** novelty search over the alien substrate (`inv_open.search`, info
   descriptor, pop=90, gens=45, fresh RNG per round, fixed descriptor seed).
2. **Census (A1):** the ≤80 shortest *clean* archive members are each run through the
   irreducibility certifier (`forge.reducibleLib`, exhaustive chain enumeration,
   depth budget **3**, MATCH_THRESHOLD 0.95, 8 streams × 28 symbols).
3. **Promote:** the shortest certified-irreducible candidate joins the library.
4. **Generalisation probe (A4):** re-measure a **held-out battery fixed before
   round 1** — 18 target behaviours over a hidden 13-program library
   (5 base atoms + distinct-count + RMW counter + xor-scan + hash-table + union +
   3 random-clean decoys, decoy seed 0xBA77E71). A target counts as *reachable* iff
   some depth-≤3 chain over the **current** atom library matches it at ≥0.95
   agreement (fixed check seed 0x0F17ED, identical every round/seed). Each new flip
   is classified: **SELF** (witness = the new atom alone, depth 1 — the atom *is*
   the target) vs **COMPOSED** (witness is a genuine chain).
5. Stop at fixed point (no irreducible candidate in the census) or 10 rounds.

At the end, every promoted atom is **re-certified at deeper budgets** (A5/A6):
against its promotion-time library prefix at depth 4 and 5 (did a composition sneak
past the depth-3 certifier?), and against the final library minus itself at depth
3 and 4 (did it become redundant given later atoms?).

## Per-round results

Seed 0xA70F:

| round | lib | archive | clean | checked | irreducible | promoted len | held-out reachable | flips (self/composed) |
|---|---|---|---|---|---|---|---|---|
| 0 | 5 | – | – | – | – | – | 3/18 | baseline |
| 1 | 6 | 97 | 81 | 80 | 77 | 2 | 3/18 | – |
| 2 | 7 | 81 | 69 | 69 | 62 | 4 | 3/18 | – |
| 3 | 8 | 63 | 55 | 55 | 53 | 2 | 4/18 | +1 (0/1) |
| 4 | 9 | 106 | 95 | 80 | 74 | 6 | 4/18 | – |
| 5 | 10 | 65 | 55 | 55 | 46 | 4 | 4/18 | – |
| 6 | 11 | 90 | 81 | 80 | 72 | 5 | 6/18 | +2 (2/0) |
| 7 | 12 | 124 | 105 | 80 | 68 | 5 | 7/18 | +1 (1/0) |
| 8 | 13 | 106 | 96 | 80 | 64 | 3 | 7/18 | – |
| 9 | 14 | 57 | 46 | 46 | 23 | 5 | 7/18 | – |
| 10 | 15 | 122 | 110 | 80 | 62 | 4 | 7/18 | – |

Seed 0x5EED2 (same shape): lib 5→15, irreducible census 48–78 per round, held-out
3/18 → 7/18 with flips at rounds 1 (+1 composed), 3 (+2 self), 9 (+1 self).

## A2 — fixed point: NOT reached

Neither seed reached a fixed point in 10 rounds. Every round's census still found
23–78 irreducible candidates among ≤80 checked (a 30–97% irreducible rate). At this
budget (depth-3 certifier vs a 6-dim-descriptor-diverse novelty archive) the supply
of "irreducible at depth 3" behaviours is nowhere near exhausted; the irreducible
fraction declines only mildly as the library grows (e.g. 77→62 checked-irreducible,
seed 0xA70F). This does **not** contradict the earlier atomforge saturation claim —
that loop promoted only the *first* irreducible find of a smaller archive at
MAX_ROUNDS=8; the honest statement is: **at depth budget 3 the certifier bar is weak
enough that promotion can continue essentially indefinitely.** Termination in prior
runs was a property of the search/archive budget, not of the behaviour space.

## A3 — library growth

5 → 15 atoms in 10 rounds, both seeds (one promotion per round, never starved).
Promoted-atom program lengths: 2–7 instructions, **flat/noisy, no upward trend** —
consistent with the earlier "coverage, not growth" finding. The loop is not being
forced to invent increasingly complex atoms.

## A4 — generalisation: the key (mostly negative) result

Held-out reachability curve (both seeds): **3/18 → 7/18**. But decomposed by
witness type, the picture is much weaker than the curve suggests:

- **Self-flips (6 of 8 total flips across both seeds):** all three decoy targets
  flip *only* because a later promoted atom is behaviourally *identical* to the
  decoy (witness = `[new atom]`, depth 1). This is not generalisation — novelty
  search sampling the same random-program distribution the decoys came from
  eventually re-draws them. These flips would happen with *any* archive dump.
- **Composed flips (1 per seed):** the single genuine generalisation event, and it
  is the same event in both seeds: **xor-scan becomes reachable as a promoted atom
  applied twice** (0xA70F: `[7,7]` at round 3; 0x5EED2: `[5,5]` at round 1). The
  target was not the atom's spawning behaviour — the composition is real reach the
  base library did not have.
- **The structured held-out family never flips.** `distinct`, `hashtbl`, `union`,
  and *all nine* hidden compositions involving distinct-count or the RMW counter
  (`dist->gxor`, `dist->dist`, `shift->dist->gxor`, …) remain unreachable after 10
  promotions in both seeds. Ten closure escapes bought zero progress toward the
  behaviours that were actually hard at round 0.

**Verdict:** promoted atoms are *not* purely self-serving — one honest composed
flip per seed proves the enlarged set has genuinely new composite reach — but the
expansion is **local to the novelty-search sampling distribution**. Reachability
grows where the forge already lives, not toward held-out structured targets. If the
curve is corrected for self-flips it is 3/18 → 4/18 over 10 promotions.

## A5/A6 — retro-reduction audit

Deeper re-certification of all 20 promoted atoms (depth 4 and 5 vs promotion-time
prefix; depth 3 and 4 vs final-library-minus-self):

| seed | atom | promoted round | prefix d4 | prefix d5 | final−self d3 | final−self d4 |
|---|---|---|---|---|---|---|
| 0xA70F | inv0–inv9 | 1–10 | holds ×10 | holds ×9 (1 skipped, n>13) | holds ×10 | holds ×10 |
| 0x5EED2 | inv8 | 9 | **REDUCED** | **REDUCED** | holds | **REDUNDANT** |
| 0x5EED2 | inv0 | 1 | holds | holds | **REDUNDANT** | REDUNDANT |
| 0x5EED2 | inv5 | 6 | holds | holds | **REDUNDANT** | REDUNDANT |
| 0x5EED2 | others | – | holds | holds | holds | holds |

- **Degenerate promotion detected: 1/20.** Seed 0x5EED2's round-9 atom passed the
  depth-3 certifier but is a **depth-4 composition of atoms it was certified
  against** — a certifier false-irreducible that snuck into the library. Measured
  leak rate at this budget: ~5%.
- **Redundancy (RQ A#4): 3/20.** Two additional 0x5EED2 atoms became reducible to
  *other promoted atoms* after later promotions — the final set is minimisable.
  Seed 0xA70F's library is fully non-redundant even at depth 4.

## What this says about the Closure Principle

Each promotion is a certified escape from the depth-3 composition closure of the
current set, and such escapes **do not run out** at this budget — the ladder has no
visible top. But the escapes are cheap: the depth-3 bar admits a large supply of
short (2–7 instruction) behaviours, occasionally admits a fake (1/20), and the
enlarged closures barely reach outward. **The ladder keeps climbing but mostly
stops paying:** after stripping self-matches, ten rungs bought one held-out
behaviour (xor-scan, via atom²) and left the entire structured target family
untouched. Escaping closure is easy at a weak certifier depth; escaping *toward
anything you care about* is the unsolved part. The lever that would change this is
not more rounds — it is either a deeper certifier bar (raising irreducibility
quality, cutting the 30–97% census rate) or a forge whose novelty pressure is
coupled to the held-out frontier rather than to descriptor space alone.

## Honest limitations

- 2 seeds, 10 rounds, one substrate, one depth budget (3). The no-fixed-point
  result is a lower bound, not an asymptote.
- The census is capped at the 80 shortest clean candidates per round; "irreducible
  candidates found" is relative to that cap.
- Behaviour matching is 0.95 agreement on 8×28 random streams — statistical, not
  exact; the same criterion the existing forge/certifier uses (16/16 kill-tests),
  but retro-audit "holds" means "no chain found at that budget," not a proof.
- Depth-5 prefix audit skipped for the round-10 atoms (prefix n=14 > 13 cap);
  depth-4 was run everywhere.
