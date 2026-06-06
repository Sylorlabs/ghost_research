# Research questions to test — flagged by honesty

Legend: **🟢** answer genuinely unknown in advance (real research, can surprise) ·
**🟡** quantifies/maps something partly known · **🔴** likely just confirms known
(run only for completeness). `[solo]` = runnable in this repo now · `[needs X]` =
needs an external ingredient. The 🟢 `[solo]` rows are where to spend runs.

> **2026-06-03 round — four directions answered** (see `RESEARCH_ROUND_2026_06_03.md`):
> **A10 (new, Clifford binding)** ✅ — changing the bind off GF(2) moves the closure, but a
> plain real bind matches Clifford; "leave GF(2)," not the geometric product, is the lever
> (`sparse_poly_discovery/docs/research/clifford_binding.md`). **A1–A3 (atom-forge)** ✅ — iterated
> promotion covers a fixed substrate (flat complexity, bottoms out at the opcode VM); it
> relocates claim C, doesn't escape it. **Forge-parameter frontier** ✅ negative — gradient
> cannot learn the parity ω (vanishing gradient at the optimum); grid search can
> (`family_gradient.md`). **#53 (falsify)** ✅ — the XOR ceiling survived; it is information
> destruction (4000 grids → 64 encodings), not a weak-readout artifact (`falsification_hunt.md`).

---

## A. The open-atom-set frontier — the ONLY regime where "it can invent" can be *yes*
The budget-scan proved a *fixed* atom set can't invent (every behaviour is a
composition). The live edge is letting the atom set grow.

1. 🟢 [solo] ✅ If a certified depth-N survivor is **promoted** into the atom set, can the *next* round find a behaviour irreducible to the **enlarged** set? — **Yes (8 rounds), but the bar is weak; see #2/#3.** (`wcore atomforge`)
2. 🟢 [solo] ✅ Does iterated atom-promotion **terminate** (atom set stops growing) or grow unboundedly? Is there a fixed point? — **Effectively saturates: it COVERS the fixed opcode VM, bottoms out there. Composition all the way down.**
3. 🟢 [solo] ✅ Does each promotion let solvable-task **composition depth** keep rising, or plateau? — **Plateau: minimal program-length stays flat/noisy (coverage, not growth).**
4. 🟢 [solo] Is a promoted atom ever later **reducible to other promoted atoms** (redundant)? Can the atom set be minimised?
5. 🟢 [solo] Two different seed atom sets → do they converge to the **same closure** (path-invariant invention) or diverge?
6. 🟢 [solo] Is there a task solvable **only after ≥2 promotions** (invented-on-invented)?
7. 🟢 [solo] Do invented atoms **generalise** (help on held-out tasks they weren't forged for) or are they task-overfit?
8. 🟡 [solo] Does promotion lower **search cost** (iters-to-solve) for downstream tasks — do atoms act as useful abstractions?
9. 🟡 [solo] Does promotion **order** change what's eventually invented (path dependence)?
10. 🟢 [solo] ✅ **(A10, Clifford binding)** Does swapping the bind off XOR/GF(2) move the readout closure on the band/sum the XOR substrate can't read? — **Yes (0.50→0.97); but a plain real Hadamard bind matches Clifford — the lever is "leave GF(2)," not the geometric product. Clifford's grade-2 advantage untested (needs a two-sided/relational predicate).** (`clifford_binding.md`)

## B. Invention engine knobs (wcore) — push past where anyone's run
10. 🟢 [solo] Push DMAX to 9/10/11 — does survivorship ever become **nonzero**, or is 0 stable?
11. 🟡 [solo] Evolution budget 80k→800k iters: does the **min-reduction-depth** distribution deepen (harder-but-reducible solvers)?
12. 🟢 [solo] Sweep the novelty threshold — is there a setting where certifier-**novel ⟺ irreducible** (the false-positive rate hits 0)?
13. 🟢 [solo] Does coevolution ever assemble something **irreducible** that direct search missed, or only reducible compositions?
14. 🟢 [solo] Do other hand-built behaviours (besides distinct-count) come out **irreducible** to the atoms? How many, how "far"?
15. 🟡 [solo] Closure-coverage curve: what fraction of all k-bit functions is reachable by depth-≤D compositions, vs D?
16. 🟢 [solo] Is there a behaviour reachable at depth D but **not** at D−1 and **not** cheaper at D+1 — a genuine depth hierarchy?
17. 🟢 [solo] Two atoms A,B with **synergy**: {A,B} reaches behaviours neither {A} nor {B} (plus composition) reaches?
18. 🟡 [solo] Add one nonlinear atom (carry/AND) to an XOR-only set — which tasks **flip** from unsolvable to solvable?

## C. Control agent (sparse_poly_discovery) — beyond mb_mass
19. 🟢 [solo] Does **multi-step planning** (rollout over the scalar model) beat greedy mb_mass (11.02), or is greedy already optimal?
20. 🟡 [solo] Does mb_mass survive **stochastic** band dynamics, or collapse like the attractor-recogniser?
21. 🟢 [solo] A band variant where the **sum is insufficient** and a 2-feature readout is needed — does feature-search find the pair?
22. 🟡 [solo] Scale grid 16→64→256 — does the sum readout keep working? Sample/compute cost vs size?
23. 🟢 [solo] Controlling feature = a **nonlinear** function of cells (max, variance) — does feature-search + nonlinear readout discover it, at what sample cost?
24. 🟡 [solo] Does the **CP3 reversal** hold across other non-trivial tasks, or is it band-specific?
25. 🟢 [solo] Is there a task where the **attractor-recogniser beats mb_mass** (prototype-distance is the right bias)?
26. 🔴 [solo] Does VSA-readout + sum beat sum alone? (likely VSA adds nothing — confirm.)
27. 🟢 [solo] Multi-objective: keep mass in band **and** maximise delivered work — can a learner trade off and beat hand-coded?
28. 🟡 [solo] Does an **online value function** over the sum beat the min/max-midpoint heuristic?

## D. Mixer / meta-engine (BitForge)
29. 🟡 [solo] MUL-free best SAC-error vs **program length** — where does the affine ceiling stop improving?
30. 🟢 [solo] Is there a **non-MUL** nonlinear op (AND_NOT, ADD_ROT, MUM) that reaches MUL-level SAC at fixed length, or is MUL unique?
31. 🟡 [solo] Does the **44–47 meta-engine ceiling** move if SAC is added to the fitness (multi-objective)?
32. 🟢 [solo, verifier present] **Verified superoptimization:** for a chosen function, is there a formally-equal program **shorter than gcc -O3**?
33. 🟢 [solo] **Exhaustive certified minimal length** of f in ISA X — what is it? (unknown in advance, certifiable)
34. 🟢 [solo] Can CEGIS invent a bit-hack **not in Hacker's Delight** for a deliberately-unusual spec (vs rediscovering known ones)?
35. 🟡 [solo] Does the AIG identity-collapse (513→1) generalise — collapse-rate vs redundancy across many identities?

## E. The closure principle — theory & generalisation
36. 🟢 [needs theory] Is there a **decidable, budget-independent** irreducibility certificate for any closure class richer than affine?
37. 🟡 [solo] For the XOR/bundle VSA: is "predicate P ∈ readout closure" decidable; what's the expressible-predicate class / VC-dim?
38. 🟢 [solo] Can a **pair** of in-closure-looking ops jointly escape a closure (emergent escape), with neither escaping alone?
39. 🟢 [solo] Is there a closure where adding the obvious generator does **NOT** escape (counterexample to the escape corollary)?
40. 🟡 Across the 5 witnesses, is the escape gap predicted by a common measure (e.g., **algebraic degree** the generator adds)?

## F. Discovery ladder — sample-complexity & phase boundaries
41. 🟢 [solo] Map the **(k, n, samples)** phase boundary where SGD stops finding sparse parity.
42. 🟡 [solo] Does a **curriculum** (k=2→3→…) let the MLP reach higher-k parity than cold start?
43. 🟢 [solo] Hidden non-salient feature: **minimum #failure-labels** for supervised recovery vs decoy variance (sample-complexity curve).
44. 🟡 [solo] Does incremental **feature-lifting search** beat a fixed MLP on sparse parity?
45. 🟢 [solo] At what **decoy-to-signal variance ratio** does even supervised recovery fail?

## G. Instrument validation — make sure the tools aren't lying (do this BEFORE trusting results)
> **#46 DONE** (`instrument_audit.md`): the loose `MATCH_THRESHOLD=0.95` does **not** hide novelty — under exact 100% matching (4096 samples) 0/24 solvers across 3 seeds flip to irreducible. "It can't invent" survives the audit and is more robust.
46. 🟢 [solo] Does `behaviorMatches` (12 regs, 32 tests) ever declare two **non-equal** programs equal? Stress with adversarial pairs.
47. 🟡 [solo] Do reducible/irreducible verdicts change as `behaviorMatches` test count rises (32→256)?
48. 🟢 [solo] Is `domain_superoptimizer.toAig` **faithful**? (I found AND/SHL bugs.) Exhaustively check each op's AIG vs `execute` at small width.
49. 🟡 [solo] Does the native SAT prover agree with **libz3** on a battery of equivalence checks (cross-verifier audit)?

## H. Scaling laws & cost signatures
50. 🟢 [solo] iters-to-solve vs task composition depth — is it **exponential** (the Claim-C cost signature)?
51. 🟡 [solo] Closure coverage vs atom-set size — does coverage of k-bit functions grow linearly, or saturate?
52. 🟡 [solo] mb_mass control quality vs band width / dynamics granularity — where does it break?

## I. Falsification hunts — try hard to BREAK our own claims (highest value)
53. 🟢 [solo] ✅ Try to **falsify the closure principle**: any case where pure within-closure grinding (iters/tiers/length) escapes a ceiling? — **No. Attacked the XOR sum-ceiling with a nonlinear MLP and a training-free test: the encoder maps 4000 grids to 64 encodings (per-value count parities), sum spans [29,67] within one encoding → information-theoretically destroyed, unbreakable by ANY readout. Principle strengthened.** (`falsification_hunt.md`)
54. 🟢 [solo] Try to produce a search artifact **irreducible at unbounded budget** (a real atom) — and if found, distrust it: is it a `behaviorMatches` false negative?
55. 🟢 [solo] Find a "novel" certifier flag that is **actually irreducible** at high depth across many seeds (would weaken "all false positives").
56. 🟢 [solo] Is mb_mass's win **fragile** to a thermostat tuned harder? (Did I beat a strawman? Tune the hand baseline and re-check.)

## J. Things that need an external ingredient (the only path to genuinely-new at scale)
57. 🟢 [needs real code] Point the verified superoptimizer at **real compiled functions** — what fraction admit a certified shorter equivalent?
58. 🟢 [needs data] On a **real dataset**, does the expressiveness diagnostic predict which models plateau (held-out)?
59. 🟢 [needs conjecture] Attack a small **open combinatorial conjecture** with exhaustive + verified search.
60. 🟢 [needs real task] Apply the full method (falsifiable Qs + ablations + two verifiers) to a problem **neither of us knows the answer to.**

---

## Where to start (my pick of the 🟢 [solo] set, by surprise-potential)
1. **#1 open-atom-set promotion loop** — the only place "yes it can invent" is possible; directly extends the budget-scan.
2. **#10 push DMAX to 10/11** — cheap, and a survivor would be a genuine surprise.
3. **#48 + #46 instrument audit** — do this first; if the verifiers lie, everything downstream is theater.
4. **#32 verified superoptimization beating -O3** — verifiable, answer unknown in advance.
5. **#53 falsify the closure principle** — the most valuable possible outcome is breaking our own claim.
6. **#19 planning vs greedy on the band** — does lookahead beat 11.02?
7. **#38 emergent escape from an op pair** — genuinely unknown, tests the principle's edge.
