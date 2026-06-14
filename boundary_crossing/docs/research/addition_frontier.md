# Scaling dial 3 — the certified addition-chain frontier, past the toy range

**Status:** built, measured. Reproduce: `cd boundary_crossing && zig build addition-frontier --release=fast` (~95 s — it does real exhaustive minimality proofs).

## Why this probe exists

`dial_three.md` turned the third dial on a genuine unknown (shortest addition chains `l(n)`) but only over the
**toy** range `n ∈ [2, 1024]`, with iterative deepening started at the bulletproof bound `⌈log₂ n⌉`. The next
step Micah picked was **scale** — push the *certified* frontier much further, without giving up the soundness
that makes "certified minimum" mean something.

## The lever: a tighter — but still sound — lower bound

The toy search wastes most of its time *falsifying* impossibly-short lengths. Knuth's **small-step bound**
(TAOCP 4.6.3) removes that waste: a chain for `n` has exactly `⌊log₂ n⌋` doubling ("big") steps, and the number
of non-doubling ("small") steps is at least `⌈log₂ ν(n)⌉` where `ν` = popcount. Hence

```
l(n) ≥ ⌊log₂ n⌋ + ⌈log₂ popcount(n)⌉            (a theorem — sound for all n; often TIGHT)
```

Starting iterative deepening at this bound skips the provably-empty depths. The run shows it is **exact on
65.1%** of the certified range — the search confirms minimality in essentially one depth probe for most `n`.

## Soundness is the whole point (an unsound "certified minimum" is worse than none)

Three guards, all green in the run:

1. **Cross-check (the key one).** For *every* `n ∈ [2, 2048]` we run BOTH the fast (small-step-bound-started)
   and the conservative (`⌈log₂ n⌉`-started) complete search and compare. The conservative search starts at an
   unquestionable bound, so its result is the true `l(n)`; if the small-step bound ever *exceeded* `l(n)` the
   fast search would skip the answer and disagree. **Disagreements: 0** over 2047 values — the fast method is
   certified-equivalent to the bulletproof one on that whole range (and the bound is a theorem beyond it).
2. **Independent verifier.** Every reported chain is re-checked from scratch (each step a sum of two priors,
   strictly ascending, ends at `n`) — the search is never trusted on its own word.
3. **Honest non-answer.** A node-budget cap maps an inconclusive search to *uncertified* (null); the code never
   silently escalates to a longer length (which would over-report `l(n)`). Budget exhaustion is reported as a
   sound bracket `LB ≤ l ≤ binary`, not a guess.

## Results

```
[guard 1] small-step bound vs conservative search on [2,2048]:  0 disagreements  (sound ✓)

[frontier] CERTIFIED l(n) for every n in [2, 2187]  — 2186 contiguous values, independently verified,
           a genuine minimality proof each (sweep stopped by a 22 s time budget, not by failure)
           small-step bound already TIGHT (l(n)=LB) on 1424/2186 = 65.1%
           engine STRICTLY beat the naive binary method on 1685/2186 = 77.1%

[showcase] large n whose l(n) I (the operator) cannot recite — engine certifies each:
    l(1023)  = 13   (LB 13, binary 18, saved 5)   ✓ 0.01s
    l(2731)  = 15   (LB 14, binary 17, saved 2)   ✓ 0.09s
    l(4095)  = 15   (LB 15, binary 22, saved 7)   ✓ 0.03s
    l(8191)  = 17   (LB 16, binary 24, saved 7)   ✓ 4.2s     (2^13−1, Mersenne)
    l(16383) = 18   (LB 17, binary 26, saved 8)   ✓ 6.9s     (2^14−1)
    l(32767) = 19   (LB 18, binary 28, saved 9)   ✓ 22.7s    (2^15−1; a real proof no 18-step chain exists)
    l(65535) = 19   (LB 19, binary 30, saved 11)  ✓ 1.7s     (2^16−1)
    l(65537) = 17   (LB 17, binary 17, saved 0)   ✓ 0.00s    (Fermat prime F4 — binary is already optimal)

[guard 3] l(99999) under a deliberately small 4M-node budget: UNCERTIFIED in 0.57s
          (sound bracket 20 ≤ l ≤ 25) — an honest non-answer, not a guess.
```

`l(65537)=17` is a nice check the run *derived*: `65537 = 2^16+1` needs 16 doublings + 1 add and the small-step
bound proves you can't do better, so the naive binary method is already optimal there (saved 0). `l(32767)=19`
is the headline: the search **exhausted depth 18** (proving no 18-step chain exists) before succeeding at 19 —
a certified minimum I did not have memorized.

## What this establishes, and the honest scope

Dial 3 **scales while staying sound**: a tighter lower bound (cross-validated to 0 disagreements) pushed the
certified frontier from the 1024 toy to ~2187 contiguous, plus individual certified `l(n)` out to 65537 — each
a genuine minimality proof, each independently verified, with budget exhaustion reported honestly rather than
faked. The small-step bound being exact on most `n` is a real structural fact the run **measured**, not one fed in.

**Scope, stated plainly:** humanity's tables (OEIS **A003313**; Flammenkamp's records) reach far past this with
specialized solvers — so **nothing here is new-to-humanity**. This is *our* self-contained engine's sound
certified reach. The contribution is the **mechanism at scale**: the same `inject → certify` loop, a sound
verifier, a genuine-unknown target — the only things separating this from a new-to-humanity result are compute
and a genuinely-open target, exactly as `real_invention.md` and `dial_three.md` concluded. Bounded, as ever, by
what can be verified.

See: `dial_three.md`, `real_invention.md`, `superopt.md`, `../README.md`, repo-root `CLOSURE_PRINCIPLE.md`.
Real-world witnesses of dial 3 at full scale: FunSearch (*Nature* 2023); AlphaEvolve (2025).
