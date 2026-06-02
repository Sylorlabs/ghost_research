# Instrument audit: did a loose threshold hide invention?

**Status:** built, measured — a deliberate attempt to **falsify my own negative
result.** Reproduce: `cd wcore && zig build -Doptimize=ReleaseFast &&
./zig-out/bin/wcore-invent auditscan <seed>`. New: `behaviorMatchesExact` /
`reducibleExact` in `src/inv_coevo.zig`, `auditScan` phase in `src/inv_main.zig`.

## The suspicion (the revolutionary reflex: distrust your instrument)

Every "reducible" verdict — including the budget-scan's "it can't invent, every
solver collapses to a composition" — rests on `behaviorMatches`, which uses
`MATCH_THRESHOLD = 0.95`. That means a known-atom composition matching a solver on
**95%** of symbols is counted as a **reduction**. A behaviour matched at 95% but
*differing on 5%* is genuinely **not** that composition — a candidate novelty the
loose threshold would silently mask as "reducible." If so, "it can't invent" was a
threshold artifact, and exact matching would reveal hidden irreducibles.

## The test

Re-judge every deep solver under **EXACT (100%) matching** with a much larger
sample budget (64 streams × 64 symbols = 4096, vs the loose 12 × 32 = 384), and
count solvers that are **reducible-loose but irreducible-exact** (the masked
candidates).

## Results

```
  seed   | deep | loose-reducible | exact-reducible | MASKED
  -------+------+-----------------+-----------------+-------
  0xD00D |  9   |       9         |       9         |   0
  0xBEEF |  8   |       8         |       8         |   0
  0x1111 |  7   |       7         |       7         |   0
  sanity: distinct-count = IRREDUCIBLE under BOTH loose and exact (non-vacuous)
```

**0 masked, every seed.** Exact matching agrees with the loose threshold: every
discovered solver is an *exact* composition of the atoms, not a 95%-approximation.

## Verdict

"It can't invent" **survives the instrument audit.** The 0.95 threshold was not
hiding novelty — the negative result is not a measurement artifact, it is real and
now more robust. The honest reflex (attack your own conclusion by attacking the
instrument that produced it) was the right move and made the finding *stronger*,
not weaker.

This is corroborated independently by the atom-forge's own verdict: its "8 invented
atoms" are short programs in substrate-ops the base atom set merely omitted — naming,
not invention; relative to the fixed opcode VM they remain compositions. Open-ending
the atom set **relocates** Claim C, never escapes it.

## The terminal frontier this pins down

On **any fixed substrate**, search-as-invention is composition all the way down to
the primitives — under exact matching, at depth, across seeds. The only regime where
"can it invent?" could answer *yes* is a substrate whose **primitives are themselves
not fixed** — a learned or physical substrate, not a fixed-opcode VM. That is the
real, and only, open direction; everything reachable on a fixed VM now consistently
says no.
