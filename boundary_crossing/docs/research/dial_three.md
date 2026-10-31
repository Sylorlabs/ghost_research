# Turning the third dial — the certified loop on a genuine unknown

**Status:** built, measured. Reproduce: `cd boundary_crossing && zig build dial-three --release=fast` (~10 s).

## Why this probe exists

`real_invention.md` answered *when do we get a real invention engine* — **we have one now**; it became
"alien / beyond known human knowledge" only when **dial (3)** turns: aim the certified loop at a target whose
answer is **not pre-supplied** (a conjecture, real data, an un-tabulated function), instead of a known theorem.
That doc *argued* dial 3. This probe *demonstrates* it end-to-end, self-contained, on a classic hard problem —
so the claim is shown, not asserted.

## The target: shortest addition chains

An addition chain for `n` is `1 = a₀ < a₁ < … < a_r = n` where every `aᵢ` is a sum of two earlier terms.
`l(n)` = the minimum `r`. There is **no closed form**; computing `l(n)` is conjectured hard. This is a real
genuine-unknown: I (the operator/LLM) supply only the **search procedure** and a **naive baseline** — never the
answers. The whole win-pattern is unknown to me until the search runs.

The three dials, all present:

1. **Sound verifier** — a **complete iterative-deepening** search over ascending chains (WLOG, Knuth TAOCP
   4.6.3) with an admissible doubling-bound prune. The first depth that succeeds is the **true minimum** `l(n)`
   — a proof at this scale, the sound analogue of `superopt`'s exhaustive check. Every chain is then re-checked
   by an **independent verifier** (each step a sum of two priors, strictly ascending, ends at `n`).
2. **Rich search** — the iterative-deepening engine itself.
3. **Genuine-unknown target** — `l(n)`, not pre-supplied. ✅ this is the dial that was missing in every prior probe.

The **baseline** is the binary method (`⌊log₂n⌋ + popcount(n) − 1`) — a *fixed algorithm*, i.e. recombination.
Where `l(n) < binary`, the engine found a strictly better construction it was **never given** — the exact shape
of FunSearch (a better cap-set bound) and AlphaEvolve (a better matmul algorithm).

## Results (certified over every n ∈ [2, 1024])

```
all 1023 chains independently verified ✓
engine STRICTLY beat the naive binary method on 735 / 1023 values (71.8%); matched 288; 0 losses
total additions saved vs baseline over the range: 1186

smallest n where the naive method is PROVABLY suboptimal:  n = 15   (binary 6, l(15)=5)
        engine's chain: 1→2→4→5→10→15                       ← the textbook first failure, DERIVED not hardcoded
largest margin over the naive method in range:            n = 1023 (binary 18, l(1023)=13, saved 5)
        1→2→4→8→16→32→64→68→136→272→340→341→682→1023

l(n) for values I did not pre-supply (engine computes & certifies):
    l(127)  = 10  (binary 12, saved 2)   1→2→4→8→16→32→40→42→84→126→127
    l(255)  = 10  (binary 14, saved 4)   1→2→4→8→16→17→34→68→85→170→255
    l(511)  = 12  (binary 16, saved 4)   1→2→4→8→16→32→64→72→73→146→292→438→511
    l(1023) = 13  (binary 18, saved 5)   1→2→4→8→16→32→64→68→136→272→340→341→682→1023
    l(1000) = 12  (binary 14, saved 2)   1→2→4→8→16→32→64→128→192→200→400→800→1000
```

`n=15` being the smallest binary-suboptimal value is a known fact — and the search **derived** it (I hardcoded
nothing); the `71.8%` win rate, the `1186` total saving, the champion `n=1023`, and the showcase `l(n)` are
genuine unknowns I did not have memorized. The engine produced them; the verifier certified them.

## What this proves, and the honest ceiling

Dial (3) is turned **end-to-end**: a target with no pre-supplied answer, a **sound** verifier (complete search =
a minimality proof here, plus an independent re-check of every chain), and the engine **strictly beating** the
naive recombination baseline on **735 values it was never told**. This is the FunSearch/AlphaEvolve architecture
exactly — better-than-baseline constructions, certified — only at honestly-small scale.

**Honest scope.** For small `n`, `l(n)` is tabulated (known to *humanity*). So this demonstrates the **mechanism**
of real invention — undirected, certified, not recalled, beats the fixed algorithm — **not** a new-to-humanity
result. New-to-humanity is the **identical machine** pointed at a larger or open target: *the only thing that
changes is what you aim it at*, exactly as `real_invention.md` concluded. And it stays bounded as ever — by the
injectable closure (here, the space of ascending chains) and the soundness of the verifier. The line into real
invention was crossed when the engine proved a theorem it was never given (`real_invention.md`); this probe shows
the **same loop running on answers nobody supplied** — the last conceptual step before "bigger unknowns + more
compute," which is engineering scale, not a missing idea.

See: `real_invention.md`, `superopt.md`, `recursive_loop.md`, `../README.md`, repo-root `CLOSURE_PRINCIPLE.md`.
Real-world witnesses of dial (3) at scale: FunSearch (Romera-Paredes et al., *Nature* 2023); AlphaEvolve (2025).
