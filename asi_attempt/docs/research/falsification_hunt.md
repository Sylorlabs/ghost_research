# RQ I53 — Falsification hunt: can the XOR closure ceiling be broken?

**Status:** built, measured. Reproduce: `cd asi_attempt && zig build falsify`

## The hunt

The Closure Principle's control-domain witness says total mass is *outside the closure* of
the XOR/bundle substrate (a linear perceptron over all 8192 bits scores 0.51). The highest-
value outcome in the whole program is **breaking our own principle**, so this experiment
attacks that ceiling two ways: a nonlinear readout (does the sum hide *nonlinearly* in the
bits?), and a training-free information-theoretic test (is the sum even *present* in the
encoding?).

If a nonlinear readout recovered the sum, "outside the closure" would have to be downgraded
to the weaker "outside the *linear*-readout closure." That would be a real (partial)
falsification.

## Method

- **Primary (training-free).** Encode many grids with the stock `EnvEncoder` (XOR), hash
  each 8192-bit encoding, and count distinct encodings; for each encoding bucket track the
  range of grid sums that map into it. No learner involved — pure information theory.
- **Secondary (corroboration).** Attack with a nonlinear MLP (8192→24→1) over the XOR bits.
  Honesty controls so a failure is the *substrate*, not a weak learner: the **same MLP** on
  raw 16 cells must learn the sum, and a real Hadamard bind must expose it to a linear
  readout. Features standardized first (the conditioning fix from `clifford_binding.md`).

## Result

```
=== PRIMARY (training-free): information-theoretic collapse of the XOR encoder ===
  distinct grids encoded         : 4000
  distinct XOR encodings (s)      : 64     (theory: <= 2^7 = 128 parity signatures)
  largest single-encoding bucket  : 81 grids, with sums spanning [29, 67]
  widest sum spread inside ONE s  : 54     (>0 means sum is NOT a function of s)

=== SECONDARY: trained readouts ===
  linear over XOR bits (8192)     |  0.481   the established ceiling
  MLP over XOR bits (8192->24->1) |  0.505   THE ATTACK (nonlinear readout)
  MLP over RAW cells (16->24->1)  |  0.998   control: the MLP CAN learn sum
  linear over Hadamard enc (8192) |  0.976   control: a real bind exposes sum
```

## Verdict: the principle survives, and is strengthened

The attack **failed**, and the failure is decisive rather than weak:

**Why the sum is gone (the theory, now measured).** The stock encoder is
`s = (⊕ᵢ P[i]) ⊕ (⊕ᵢ V[gridᵢ])`. The filler `V` is indexed by *value*, so
`⊕ᵢ V[gridᵢ] = ⊕_v (n_v mod 2)·V[v]`, where `n_v` is the number of cells holding value `v`.
The encoding therefore depends **only on the 7 per-value count parities** — at most 2⁷ = 128
distinct encodings no matter how many distinct sums exist. Measured: 4000 grids collapse to
**64** encodings. (It is 64, not 128, because `Σ_v n_v = 16` is fixed, forcing an *even*
number of odd counts — exactly half the signatures are unreachable.)

**Why no readout can recover it.** Inside the largest single encoding, grid sums span
**[29, 67]** — a spread of 54. The sum is **not a function of the encoding**, so no readout,
linear or nonlinear, weak or strong, can recover it. This is **information destruction**, not
nonlinear hiding.

**The corroboration confirms the attacker was strong enough.** The MLP over XOR bits sits at
chance (0.505), but the *same* MLP cracks the raw cells (0.998) and a real Hadamard bind
exposes the sum to even a linear readout (0.976). So the XOR failure is the **substrate**,
not an undertrained net.

## Significance

This is the strongest possible outcome short of an actual refutation: a serious attempt to
break the closure principle not only failed but revealed the ceiling is **more** fundamental
than the original linear-perceptron evidence implied. "Outside the closure" was, if anything,
an *understatement* for this substrate — the relevant quantity is erased at encode time. It
also re-confirms the Clifford finding from the other direction: XOR is uniquely
destructive because it keeps only parities, while any magnitude-carrying real bind preserves
the sum.

## Honest caveats

- This refutes one specific reading ("maybe it's only outside the *linear* closure") for
  *this* encoder and *this* predicate. It is not a universal proof that no XOR-style scheme
  can ever carry a sum — a different filler scheme (e.g., position-dependent value fillers)
  would have different collapse structure. The result is exact for the stock encoder.
- An earlier run of this experiment returned INCONCLUSIVE because the MLP controls were
  unstandardized and undertrained (raw-cell control at 0.725). That was a learner artifact,
  caught and fixed by standardization; it is why the training-free collapse test is the
  primary evidence and the MLP only corroboration.

See: repo-root `CLOSURE_PRINCIPLE.md`, `closure_escape_control.md` (the ceiling), and
`clifford_binding.md` (the complementary "real bind preserves the sum" result).
