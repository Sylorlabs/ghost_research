# #3 design — the inventable-primitive substrate: spec, the unified ceiling, and the boundary purism cannot cross

**Status:** design doc (planning). Implements Frontier 24's named on-ramp. Builds: Phase B
`zig build menu-growth`, Phase C `zig build inner-forge` (added by the respective probes).

This is the architecture note for #3 (chosen route: purist, no-LLM, autonomous invention).
It must open with an honest fact, because the repo already contains most of the answer.

## The honest starting point — wcore already ran the purist #3 to its terminal answer

`wcore/docs/research/alien_novelty_limit.md` is a 16-phase arc that built and pushed exactly the
"substrate whose atoms are themselves inventable" idea: an **atom-forge** (`inv_atomforge.zig`) where
novelty search generates behaviours, an irreducibility certifier (`inv_coevo.reducible`, depth-4,
≥0.95 agreement) decides which are irreducible to the current atom set, a certified one is promoted,
and irreducibility recurs. Its instrument-backed verdict:

> The open-ended atom set does **not escape** Claim C — it **relocates** it. The recursion bottoms out
> at the fixed opcode VM; relative to the substrate primitives, everything is composition. A fixed
> substrate always has a bottom, and at the bottom search composes — it does not invent.

It went further and named the deepest wall — the **novelty ↔ usefulness tension**: a task-agnostic
novelty metric gives diverse-but-useless behaviours; pinning usefulness needs a task, which
reintroduces the convergent attractor. *One fitness gives open-ended novelty OR task-grounded
usefulness — not both.* And the only escape it could name: a substrate whose primitives are grounded
in something **not fixed** — learned or physical (i.e. an out-of-substrate ingredient).

So the purist, autonomous, *unbounded* invention engine is, by the repo's own results, **closed**.
This is not defeat — it is the Closure Principle reaching its sharpest form. #3's job is therefore not
to "achieve unbounded invention" (proven impossible in the purist box) but to (a) instantiate the wall
cleanly in a **second, independent substrate** (cross-thread replication — the repo's gold standard,
cf. the five closure witnesses), and (b) pin the exact boundary where the purist constraint forecloses
progress, and hand that decision back.

## The unified ceiling — the Closure Principle applied to the discoverer itself

Three independent substrates, one law:

| substrate | the forge | where it bottoms out |
|---|---|---|
| meta-engine tiers (`05_meta_synthesis`) | search over search-algorithms (Tier 1/2/3) | 44–47 fitness; "more tiers" refuted |
| wcore atoms (`wcore`) | atom-forge over an opcode VM | the fixed opcode set; 0 irreducible past the VM |
| structure_discovery menu (Frontier 24) | argmax over (inner ⊗ outer) | the fixed menu; hidden-pair ceiling 0.591 |

The law: **a forge over a fixed substrate composes; "discover the generator" relocates one level up
(operator → which-cells → which-primitive) but the new level is itself a fixed closure with its own
bottom.** This is the Closure Principle re-applied to the discoverer: the discoverer can only mint what
its own primitive set spans. Optimising the forge (more search, more tiers, novelty pressure) cannot
escape — only injecting a generator outside the *discoverer's* closure can, and a fixed symbolic
substrate has no such generator inside it.

## Phase B (minimal) — certified menu-growth that escapes Frontier-24's *specific* ceiling

**Build:** a forge that grows the menu just enough to beat the hidden-pair predicate Frontier 24 fails.

- **Growable family:** inner transforms parameterised by *which pair* — `product(i,j)`, `oriented(i,j)`,
  `compare(i,j)` for all pairs (i,j), not just the focal (0,1).
- **Discover:** search candidate pairs; for each, fit the menu's outer operators on train, score on val.
- **Certify (two conditions, both from the repo's discipline):**
  1. **Escape** — the new inner (with an outer) solves the target on held-out *test* at ≥0.90, where the
     fixed menu sat at chance.
  2. **Irreducibility** — the new inner's scalar is *not* reconstructible (to behavioural agreement on
     held-out grids) by a readout over the existing menu inners. Reducible → don't promote; irreducible
     → promote. (This is wcore's `reducible` test, lifted from opcode programs to inner transforms.)
- **Falsifiable target:** beat 0.591 on the hidden pair (2,5) via a *certified, promoted* `product(2,5)`.
  - Fails if: pair-search overfits val and the promoted pair doesn't generalise to test; OR the
    irreducibility certifier wrongly calls `product(2,5)` reducible to the menu (a false negative that
    would itself be a finding about the certifier).
- **The honest caveat baked in:** this "escape" is **selection over a combinatorial-but-fixed family**
  (all pairs). It escapes the *specific* ceiling, but the family `{product(i,j), …}` is itself fixed →
  it has its own bottom (a predicate needing structure outside pairwise products — e.g. a 3-cell
  relation — that no `(i,j)` entry captures). Phase B demonstrates *escape of a named ceiling*; it does
  not repeal the law. The ceiling relocates from "which operator" to "which family".

## Phase C (general) — the inner-transform forge, and where it bottoms out

**Build:** a small typed VM for inner transforms (grid → scalar) and the atom-forge over it.

- **Substrate primitives:** `cell[i]`, `thresh(x,H)`, `compare(x,y)`, `mul`, `add`, `sum-reduce`,
  `parity-reduce`, `min/max-reduce`. Inner transforms are short programs in this VM.
- **Forge loop (wcore, lifted):** generate candidate inner-transform programs → certify irreducible to
  the current inner set (behavioural, depth-bounded) → promote a certified one → recurse. After each
  promotion, re-run the structure_discovery selector and log how many zoo predicates become solvable.
- **Measurement (the point):** does the inner set's coverage keep climbing, or **saturate**? Track
  (i) #zoo-predicates solved vs promotion round, (ii) minimal program-length of each promoted inner
  (flat ⇒ coverage, not complexity growth — wcore's tell), (iii) #irreducible-found per round → 0.
- **Expected (per wcore, to be re-measured here, not assumed):** it **saturates** at the VM's expressive
  closure. Every promoted inner is a VM program; relative to the VM primitives, all is composition. A
  fresh, clean witness of the unified ceiling in the sparse_poly substrate — confirmation by replication.
- **The one purist experiment wcore did *not* run in this form — the algebraic-irreducibility objective.**
  wcore's forge was driven by *behavioural-distance novelty* (which it showed relocates to the
  descriptor) or by task fitness (which converges). Here, drive the forge by a sharper, provable
  objective: **"irreducible to the current closure AND lowers held-out error on a target the closure
  can't fit."** This fuses novelty (algebraic, not metric) with usefulness (held-out) in *one* signal —
  a direct attack on the novelty↔usefulness tension. Honest hypothesis: it still bottoms out at the VM
  primitives (irreducibility is always *relative* to the current set, and the set is VM-bounded), but it
  may climb **further / more reliably** before saturating than behavioural novelty did. Falsifiable both
  ways. If it ever promotes a primitive that is irreducible *and* the coverage curve does not flatten,
  that would be the first crack in the law — distrust it and apply the certifier's kill-test (is it a
  behaviour-match false negative?), exactly as wcore did.

## The boundary — where purism forecloses, stated plainly

By the Closure Principle and wcore's 16 phases, the only sources of an out-of-closure generator are:
human · enumeration (= composition over a fixed substrate = bottoms out) · external data · a
richer-closure model. The purist constraint (no LLM, no external data) keeps only *human* and
*enumeration*. Enumeration is what the forge does, and it composes. **So purist autonomous unbounded
invention has a proof-shaped reason it terminates.** #3's terminal deliverable is therefore: a second
clean witness of that termination (Phases B/C), plus the precise statement that the *next* genuine step
requires relaxing exactly one constraint — an out-of-substrate ingredient. That is the decision #3
hands back: accept the terminal purist result as the honest end of this line, or relax "no external
ingredient" (the route declined earlier — superoptimization vs `-O3`, an open conjecture, real data, or
an LLM-as-generator subordinated to the certifier) to cross the boundary the purist box cannot.

## Falsification summary (what would surprise us)

1. Phase B: a certified, promoted pair generalises and beats 0.591 → expected POSITIVE (escape of the
   specific ceiling). A misroute/overfit or a certifier false-negative → finding about the method.
2. Phase C saturation: coverage curve flattens, minimal length stays flat, irreducible-found → 0 →
   expected (replicates wcore). **Non-flat coverage under the algebraic-irreducibility objective would
   be the one genuine surprise** — pursue and stress-test it if it appears.
3. The deepest: any purist run that promotes a primitive irreducible to the substrate VM itself (not
   just to the current subset) would refute the unified ceiling. Predicted impossible; worth one honest
   attempt.

## Reproduce / See

```
# Phase B
cd sparse_poly_discovery && zig build menu-growth --release=fast
# Phase C
cd sparse_poly_discovery && zig build inner-forge --release=fast
```

See: `structure_discovery.md` (Frontier 24, the fixed-menu baseline), `wcore/docs/research/
alien_novelty_limit.md` (the terminal purist answer this replicates), `composed_discovery.md`,
`operator_inference.md`, repo-root `CLOSURE_PRINCIPLE.md` and `RESEARCH_QUESTIONS.md` (§J, the
external-ingredient path that crosses the boundary).
