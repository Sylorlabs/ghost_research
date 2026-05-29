# Disclaimer — Thread 07: Affine-Closure Tier-A Proof (2026-05-28)

**This thread proves a property of the search output instead of measuring
it externally.** It is a follow-on to thread 06's `mul_free_challenge`, not a
new search. Read `affine_closure_tierA_2026_05_28.md` first.

## What is actually proven (and what is not)

| Statement | Status |
|---|---|
| Each of the 6 committed constrained champions uses only GF(2)-linear ops | PROVEN (read from committed CSVs; ops ∈ {XOR, SHL_XOR, SHR_XOR}) |
| Each is an exact affine map `P(x) = M·x + c`, `rank(M)=64/64` | PROVEN, all 2^64 inputs (W1 affine + W2b 65-point affine-basis = deterministic; W2 1M-sample + W3 Z3 are redundant) |
| Affinity ⇒ bounded GF(2) stream rank ⇒ BRank failure | THEOREM (Cayley–Hamilton; matches the logged `BRank(12):score:256(10)`) |
| "MUL is necessary" in general | NOT proven. Tier A only covers programs that stay in the linear opset `L_lin`. |
| Nonlinear MUL-free programs (AND_NOT/OR_SHIFT/ADD*) cannot pass BRank | NOT proven — this is Tier B, still empirical/open. |

## Verification status of the affine claim

Three independent witnesses, gated like thread 05/06's Dual-Proof Rule:

- **W1** — GF(2) matrix tracker (`affine_closure.zig`), pure linear algebra,
  exact transfer functions for `L_lin`. Refuses to emit an affine claim if any
  nonlinear op is present.
- **W2** — `M·x + c == domain.Program.execute(x)` over 1,000,000 random + 7
  structural-edge inputs, using the **real runtime** `execute()`.
- **W2b** — affine-basis: `M·x + c == execute(x)` on the 65 points
  `{0, e_0 … e_63}`. Given W1 (P affine), this is exhaustive over all 2^64
  inputs. **Load-bearing.**
- **W3** — real `libz3` (via `smt_verify.runSmtLib`): UNSAT on
  `∃X: P(X) ≠ M·X + c`. Redundant bonus oracle (`--z3=0` to skip).

**W1+W2b alone is a complete deterministic proof.** An affine map is uniquely
fixed by its values on the affine basis, so W2b's 65-point agreement with the
runtime is exhaustive over all 2^64 inputs — no sampling, no solver. (W2's
1,000,000-sample match is a redundant statistical guarantee, since distinct
affine maps over GF(2)^64 differ on ≥ 2^63 inputs.) **W3 is not load-bearing:**
64-bit XOR/shift-circuit equivalence is near-worst-case for CDCL SAT, so Z3
solved only 2/6 (341 s, 773 s) and exceeded a 1800 s cap on the other 4. That
is a solver limitation, not a gap — W1+W2b settles all six. No witness
disagreed on any champion.

## Honesty notes

- **The verdict does not hinge on W3.** Do not let a future agent report
  "incomplete because 4/6 Z3 runs timed out." Z3 exceeding 1800 s on those four
  is a CDCL-on-XOR limitation (bit-blasted XOR/shift-circuit equivalence is
  near-worst-case for clause learning), **not** a missing proof: W1+W2b prove
  all six deterministically over all 2^64 inputs in milliseconds. W3 is a
  redundant third engine, recorded for transparency where it was tractable
  (2/6).
- **Bijectivity is not the point.** Every champion here is a perfect affine
  bijection (`rank 64/64`) and still fails BRank. Thread 06/Exp7's
  bijective-but-PractRand-failing finding is consistent: bijectivity and
  PractRand quality are independent axes; affinity kills BRank regardless.
- **The search dodged the nonlinearity it was offered.** `no_carry` exposed
  `AND_NOT`/`OR_SHIFT`; `mul_free` additionally exposed the `ADD*` carry
  family. Zero champions used any of them. This is *why* penalty-based opset
  restriction (Exp9) produced a null result — the search just avoids the
  penalized region. Tier B therefore requires **constrained generation**, not
  penalties.

## Separate audit finding (not part of the proof)

`smt_verify.zig:222` models shift amounts as `imm & 63`; the runtime
(`domain_u64_mixer_mulfree.execute` via `shift63`) uses `imm % 63 + 1`. These
are different programs for any shift-heavy mixer. It did not corrupt a
published result (constrained champions never reached the 64M tier that
triggers `verify_cli`), but it should be fixed before the next `verify_cli`
run on shift-dominated candidates. `affine_closure.zig` deliberately re-emits
shifts with runtime-faithful semantics and does not reuse that emitter.

## Open questions (→ Tier B)

1. Force ≥ k nonlinear ops via constrained generation; does the search escape
   the affine basin?
2. Build a degree-tracking abstract interpreter (ANF degree bound per program)
   under the same three-witness gate; is bounded degree sufficient to defeat
   BRank within `MaxProgLen = 24`?
3. Falsifier for the whole program: any MUL-free program (any length within
   budget) that passes PractRand BRank/linearity at ≥ 16 MiB.
