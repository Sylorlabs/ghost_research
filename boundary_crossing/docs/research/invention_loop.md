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

## `feature_invent.zig` — invent the vocabulary too

The first loop discovered laws among a *handed* feature list. This one removes that: the only handed things are
primitive ops. It **generates candidate feature-programs** over n from a tiny grammar (atoms `n, isqrt, d, σ, ω,
digitsum, popcount`; ops `% · isqrt²· * + −`; tests `==n, ==0, ==1, even, odd`), runs each over [2,100000], and
**dedups by behavior** — same behavior + different program = a *discovered identity*; the distinct behaviors are
the *invented predicates*. Then law-discovery runs over the invented predicates, verified by computation.

**Result:** 217 value-programs → 868 candidate predicates → **262 distinct invented features** (503 degenerate
dropped, 320 program-pairs collapsed as identities); 34,191 law candidates generated, **34,191 refuted by
counterexample**, 742 survived. The headline — **it rediscovered Fermat's theorem from primitives**, as a
certified behavioral identity (neither side hand-written):
```
isqrt(n)^2 == n   ≡   d(n) is odd        (perfect square ⟺ odd number of divisors — Fermat)
```
plus `d(n) % 4 == 1 ⟹ isqrt(n)^2 == n`, `isqrt(n)^2 == n ⟹ sigma(n) is odd`, `digitsum(n) % 6 == 0 ⟹ n % 3 == 0`,
and `isqrt(n)^2 is even ⟺ isqrt(n) is even` (x² even ⟺ x even). So **both the vocabulary and the laws are invented**
from primitive ops; a lookup system returns only what it was told — this generated two never-written programs and
proved they encode the same theorem.

**Honest bound:** the primitive *sensors* (`d`, `σ`, `ω`, `digitsum` — loop-based) are still given as atoms; the
*predicates over them* are invented, not the sensors themselves. The grammar is shallow (depth-bounded), and some
survivors are shallow (`X==n ⟹ n even`). Genuine invention within a primitive basis — not unbounded creativity,
but categorically past lookup.

## This connects to the project's Closure Principle / invention-engine arc (`world_injection`, `real_invention`,
`autonomous_inventor`, `dial_three`): invention = inject an out-of-closure generator + a sound certifier. Here the
certifier is computation and the generator is candidate-law search; it discovers real theorems, soundly.
