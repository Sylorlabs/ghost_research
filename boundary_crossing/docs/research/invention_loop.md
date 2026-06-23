# The Invention Loop — generate → test → keep, with a SOUND verifier

After concluding the knower is *lookup + transitive deduction* (memory, not a mind), the pivot: intelligence — if
anywhere in this lineage — lives in the **generate → test → keep** loop, and the lesson from the failed text
conjecture loop (~5%, correlated noise) is that the verifier must be **sound and outside the symbols**. Text isn't.
**Computation is.**

## `discover_laws.zig` — math-law discovery

Build computable integer features (mechanism — arithmetic, not handed answers): perfect-square, divisor-count d(n),
σ(n), ω(n), popcount, digit-sum, divisibility. Form predicates over them, then **generate every pairwise law
(P ⟺ Q, P ⟹ Q) and verify each by exact computation over [2, 200000]**, refuting by counterexample.

**Result:** 231 equivalence candidates generated · **224 refuted by counterexample** · 41 laws survived
(7 equivalences + 34 implications), in 0.67 s on CPU, no LLM. Cross-domain discoveries (genuine — each connects two
different feature families, so it could not be a restatement):

- `n is a perfect square ⟺ d(n) is odd` — **Fermat's divisor-pairing theorem**
- `n divisible by 3 ⟺ digit-sum divisible by 3` ; `… by 9 ⟺ … by 9` — the classic divisibility rules
- `sigma(n) is odd ⟺ n is square or twice a square` — a non-obvious σ characterization
- `n is prime ⟺ d(n) == 2`
- implications: `square ⟹ σ odd`, `prime ⟹ d even`, `power-of-two ⟹ {prime power, square-or-2·square, …}`

## Why this is invention, not lookup

| | the knower | the invention loop |
|---|---|---|
| mechanism | retrieve a stored IS-A edge | *generate* a candidate law, *compute* both sides for every n |
| `prime ⟺ d=2` | only if a text stated it | **discovered** by testing |
| verifier | cross-source text — failed ~5% (correlated noise) | **computation — sound; one counterexample kills a law** |
| output | facts it was told | true theorems **nobody handed it** |

The 224 refutations are the point: a sound verifier *enforces* the certifier discipline text could never provide.
The same generate→test→keep loop that scored ~5% on text is ~100%-clean here because the verifier touches ground
truth, not other text.

## Honest bound (what's still handed)

The **feature vocabulary was handed** (square/divisors/σ/digit-sum) and the law-template is fixed (pairwise ⟺/⟹).
It discovers which *relations* hold among given features — real discovery — but does not yet invent the features or
the template. This is *machine discovery within a given vocabulary*, a genuine component of intelligence, not
general intelligence.

## Next (toward inventing the vocabulary too)
1. **Invent the features** — search over short computable *programs* (the project's `autonomous_inventor` /
   `primitive_synthesizer` direction), so the engine discovers the predicates, not just the relations.
2. **Compound** — feed discovered laws back to reach laws unreachable in one step (the README's invention-engine
   compounding).
3. **Genuinely-unknown targets** — point the certified loop at open questions (shortest addition chains already
   done in `dial_three`; an open combinatorial conjecture next), where there is no stored answer to retrieve —
   the cleanest possible separation of invention from lookup.

This connects to the project's Closure Principle / invention-engine arc (`world_injection`, `real_invention`,
`autonomous_inventor`, `dial_three`): invention = inject an out-of-closure generator + a sound certifier. Here the
certifier is computation and the generator is candidate-law search; it discovers real theorems, soundly.
