# Tier-A: Affine-Closure Proof of the MUL-Free BRank Failure

**Date:** 2026-05-28
**Thread:** 07 — first thread that *proves* a property of the search output
rather than measuring it externally.
**Status:** AFFINE_CONFIRMED for all six committed constrained champions.
**Artifact:** `src/adapters/affine_closure.zig` · `zig build` target
`affine_closure` · logs under `results/affine_closure_tierA_20260528/`.

---

## What this thread changes about the headline claim

Thread 06 (`mul_free_challenge`) produced an **empirical** statement:

> At a matched 20M-evaluation budget, no MUL-free / no-carry 64-bit
> single-input mixer survived PractRand 1MiB. Empirical support, *not
> proof*, that multiplication-equivalent ops are needed.

This thread converts the **dominant observed failure mode** from empirical
to **theorem**, and in doing so corrects the mechanism:

> Every committed constrained champion (3 roots × {mul_free, no_carry}) is
> composed *exclusively* of GF(2)-linear operations, so each is an exact
> affine map `P(x) = M·x + c`. An affine recurrence `x_{n+1} = M·x_n + c`
> satisfies a GF(2) linear recurrence of order ≤ 64 (Cayley–Hamilton), so
> its output stream has binary rank bounded by ~64. That is precisely what
> PractRand's BRank test detected (`BRank(12):score:256(10)`). The proximate,
> *provable* cause of failure is **"the search never left the GF(2)-affine
> subspace,"** not "the absence of multiplication."

### The sharper, more falsifiable claim

- **Bijectivity is irrelevant.** Every constrained champion is a *perfect
  affine bijection* (`rank(M) = 64/64`, i.e. M invertible over GF(2)). It has
  zero collisions, unlike the unrestricted MUL champions that `verify_cli`
  rejected as non-bijective. A flawless invertible map still fails BRank
  because it is affine. The failure is about the **algebraic class** of the
  map, not its injectivity.
- The search was *offered* nonlinear ops it never used. In `no_carry` mode the
  generator had `AND_NOT` (degree 2) and `OR_SHIFT` (degree 2) available; in
  `mul_free` it additionally had the whole `ADD`/`ADD_CONST`/`ADD_ROT` carry
  family. **None of the nine committed champions used any of them.** The
  composite-fitness landscape (avalanche≈32, balance≈32, low-byte χ², period,
  length penalty) is locally maximized by pure xorshift cascades, which live in
  the affine basin.

This isolates the genuinely-open question cleanly (see **Tier B** below).

---

## Method: witnesses

`affine_closure.zig` loads a champion CSV and runs:

1. **W1 — GF(2) matrix tracker (constructive).** Symbolically executes P
   carrying, per register, an affine form `(coeff[64], konst)` over the 64
   input bits. Transfer functions for the linear opset
   `L_lin = {XOR, ROTL, ROTR, SHL_XOR, SHR_XOR, BSWAP}` are exact. If *any*
   nonlinear op (`ADD*`, `AND_NOT`, `OR_SHIFT`, `MUL`, `MUM`, `SPLITMIX_STEP`,
   `CALL_LIB`) appears, the tool refuses the affine claim and reports
   `NON-AFFINE … Tier A inapplicable`. Output: explicit `(M, c)` and
   `rank(M)` over GF(2).

2. **W2 — numerical, vs the real runtime.** Checks `M·x + c ==
   domain.Program.execute(x)` over 1,000,000 random inputs plus 7 structural
   edge cases (`0, 1, ~0, 2^63, K1, K2, K3`), using the canonical runtime
   `execute()`. Independent statistical check.

3. **W2b — affine-basis, DETERMINISTIC all-inputs proof.** Given W1 (P affine),
   P is *completely determined by its values on the 65-point affine basis*
   `{0, e_0 … e_63}`: for any `x = ⊕_{i∈S} e_i`,
   `P(x) = P(0) ⊕ ⊕_{i∈S}[P(e_i) ⊕ P(0)]`. The tool checks `M·x + c ==
   execute(x)` on exactly those 65 points; agreement there ⇒ agreement on **all
   2^64 inputs**, with no sampling and no solver. **This is the load-bearing
   all-inputs proof.**

4. **W3 — Z3, redundant bonus oracle.** Emits runtime-faithful SMT-LIB2 for
   `P(X)` and `M·X + c`, asserts `(distinct P MODEL)`, runs real `libz3`.
   UNSAT ⇒ exact. Enable/disable with `--z3=1|0`. **Not load-bearing** — see
   the cost note below.

### Why W1+W2b is a complete deterministic proof

W1 establishes P is affine *by construction* — every op in `L_lin` is
GF(2)-linear, and a composition of affine maps is affine. An affine map is
uniquely fixed by its action on the affine basis `{0, e_0 … e_63}`, so W2b's
65-point agreement with the runtime is exhaustive over all 2^64 inputs. (W2's
1,000,000-sample match is a redundant statistical guarantee: two distinct affine
maps over GF(2)^64 differ on ≥ 2^63 inputs, so a wrong `(M, c)` would be caught
with probability `1 − 2^-1000000`.)

### Cost note on W3 (why it is not load-bearing)

Proving two 64-bit XOR/shift circuits equivalent by bit-blasting is
near-worst-case for CDCL SAT — XOR-heavy formulas defeat clause learning, and
Z3's default tactics do not apply Gaussian elimination. In practice Z3 solved
the equivalence for **2 of 6** champions (341 s, 773 s) and **exceeded a 1800 s
cap on the other 4**. This is a property of the solver, not a gap in the proof:
W1+W2b already settles all six deterministically and instantly. W3 is retained
as an independent third engine where it is tractable.

---

## Results

All six committed full-run constrained champions
(`results/phaseF_mul_free_challenge_full_run_20260523/root_<root>/champion_full_<mode>_seed1.csv`):

| Root | Mode | len | ops used | rank(M) | const c | W1+W2+W2b (all-inputs proof) | W3 (Z3, redundant) |
|---|---|---:|---|---:|---|---|---|
| `0xF00DCAFE…` | mul_free | 7 | XOR, SHL_XOR, SHR_XOR | 64/64 | `0x0AD4F70C498E06EB` | **PROVEN** | UNSAT (340,842 ms) |
| `0xF00DCAFE…` | no_carry | 6 | SHL_XOR, SHR_XOR | 64/64 | `0x0` | **PROVEN** | Z3 > 1800 s (intractable) |
| `0x11112222…` | mul_free | 6 | SHL_XOR, SHR_XOR | 64/64 | `0x0` | **PROVEN** | Z3 > 1800 s (intractable) |
| `0x11112222…` | no_carry | 6 | SHL_XOR, SHR_XOR | 64/64 | `0x0` | **PROVEN** | Z3 > 1800 s (intractable) |
| `0xABCDEF01…` | mul_free | 6 | SHL_XOR, SHR_XOR | 64/64 | `0x0` | **PROVEN** | Z3 > 1800 s (intractable) |
| `0xABCDEF01…` | no_carry | 6 | SHL_XOR, SHR_XOR | 64/64 | `0x0` | **PROVEN** | UNSAT (772,518 ms) |

**Verdict: AFFINE_CONFIRMED, 6/6** — proven exact over all 2^64 inputs by
W1+W2b (deterministic), 6/6. Every constrained champion is a full-rank affine
bijection over GF(2)^64. The BRank failures logged in thread 06 are the
predicted consequence. Z3 (W3) independently re-confirmed 2/6 before becoming
intractable on the rest — a redundant cross-check, not the proof.

Logs: `results/affine_closure_tierA_20260528/<root>_<mode>.log` (W1+W2+W2b,
deterministic). The two completed Z3 confirmations are preserved at
`f00d_mul_free_z3.log` and `abcd_no_carry_z3.log`.

Note the constant column: **5 of 6 are purely *linear* (`c = 0`, i.e.
`y = M·x` with no offset); only F00D mul_free is affine-with-offset** (its
`XOR r6 = r6 ^ r3` injects the seed constant `K3 = 0x94D049BB133111EB`). Both
classes fail BRank identically, since linear ⊂ affine and the rank bound is the
same.

Z3 (W3) is expensive: proving two 64-bit XOR/shift circuits equivalent is a
known-hard case for CDCL SAT (XOR reasoning). Single-instance solves ran
~300–800 s; an initial six-way parallel run exceeded a 900 s wall-clock cap on
the four harder instances, so a completion pass re-ran those four with more
cores per solve (≤ 1800 s cap). The affine verdict does **not** depend on W3 —
see "Why W1+W2 alone is already a proof."

## Reproduction

```bash
cd ghost_sovereign
zig build -Doptimize=ReleaseFast            # builds the affine_closure target

# Single champion (W1+W2 in <1s; W3/Z3 takes minutes):
./zig-out/bin/affine_closure \
  --csv=results/phaseF_mul_free_challenge_full_run_20260523/root_f00d/champion_full_mul_free_seed1.csv \
  --samples=1000000

# Inspect the runtime-faithful SMT handed to Z3:
./zig-out/bin/affine_closure --csv=<champion.csv> --dump-smt --samples=0
```

`--samples=N` sets the W2 random-input count (default 2^18). `--timeout-ms`
caps the Z3 call (note: `Z3_eval_smtlib2_string` does not always honor the soft
timeout for the parsed `check-sat`; use a shell `timeout` for a hard cap). The
tool prints `NON-AFFINE … Tier A inapplicable` and exits without an affine
claim if it encounters any op outside `L_lin`.

---

## Audit finding (separate from the proof)

`smt_verify.zig:222` computes SMT shift amounts as `imm & 63` (range 0–63),
but the runtime (`domain_u64_mixer_mulfree.execute`, via `shift63`) uses
`imm % 63 + 1` (range 1–63). For any shift-heavy program these model *different
programs*. The committed constrained champions failed before the 64M PractRand
tier, so `verify_cli` was never invoked on them and the discrepancy did not
corrupt a published result — but it is a latent verifier/runtime divergence for
any future shift-dominated mixer sent through `verify_cli`. `affine_closure.zig`
deliberately does **not** reuse `smt_verify`'s shift emitter; it re-emits with
runtime-faithful `imm % 63 + 1` semantics. Recommend fixing `smt_verify.zig`'s
shift model before the next `verify_cli` run on shift-heavy candidates.

---

## Tier B — the part that is still empirical, now cleanly isolated

Tier A only covers programs that stay in `L_lin`. The open conjecture:

> Do the degree-2 ops (`AND_NOT`, `OR_SHIFT`) or the carry ops (`ADD*`) —
> which raise algebraic degree, but slowly — ever let the search escape the
> affine subspace *and* pass BRank within `MaxProgLen = 24`?

Two sub-questions:

1. **Generation, not penalty.** Thread 06/Exp9 showed penalty-based opset
   restriction is too noisy (search just avoids the penalized ops, which is
   exactly what happened here — it avoided every nonlinear op). Tier B needs
   *constrained generation* that forces ≥ k nonlinear ops into every candidate,
   so the affine basin is not reachable.

2. **Degree vs diffusion.** Each degree-2 op at most doubles input degree
   (`deg(a·b) ≤ deg(a)+deg(b)`); with ≤ 24 instructions the achievable
   algebraic degree is bounded. The question is whether bounded degree is
   *sufficient* to defeat BRank, which specifically measures GF(2)-linear rank
   — a low-degree-but-mostly-linear function can still be rank-deficient. The
   natural Tier-B analyzer is a **degree-tracking abstract interpreter** that
   bounds ANF degree per program, gated by the same three-witness discipline.

**Falsification of the whole program:** any MUL-free program (any length within
budget) that passes PractRand BRank/linearity at ≥ 16 MiB would crack both the
Tier-A subspace argument's relevance *and* the degree conjecture. None has been
found.
