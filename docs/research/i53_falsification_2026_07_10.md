# I53 falsification round + G49 instrument cross-audit — 2026-07-10
> **Belongs to: Round 2026-07-10 · experiment 8 of 8 (I53 falsification + G49)** — [round index](research_round_2026_07_10.md).

**Task:** adversarially attack the Closure Principle (`CLOSURE_PRINCIPLE.md`) on
three fronts, and cross-audit the native prover instrument against a fully
independent checker. A crack found is the best outcome; every survived attack
states exactly what was and was not attacked.

**Headline: one crack found.** The Closure Principle's *core theorem* (affine
grinding never reaches a nonlinear target) survived every attack, including an
exact infinite-depth closure proof at u2. But the **"emergent pair" refinement
block in `CLOSURE_PRINCIPLE.md` is false as stated**: both pair-necessity
claims ("`x&(x-1)` needs {AND,SUB}", "`x|(x*x)` needs {OR,MUL}") are refuted by
machine-verified counterexamples — one of them found by search **on the repo's
own substrate** (u8, 2 registers), just two depth levels past the repo's
`MAXL=3` budget. The principle also needs two explicit qualifiers it currently
lacks (domain width; register/memory bound ≠ op closure), and the Tier-A affine
doc has an off-by-one in its Cayley–Hamilton bound. G49: the native prover
agrees with an independent truth-table checker on 5016/5016 cases.

New files (nothing existing was edited):

| file | role |
|---|---|
| `sparse_poly_discovery/falsify_closure_i53.zig` | attacks (a), (b), (b'): width boundary, BFS depth push, register-count probe, explicit witnesses |
| `05_meta_synthesis/src/falsify_affine_edges_i53.zig` | attack (c): Tier-A affine theorem edge cases |
| `04_verified_synthesis/src/g49_tt_cross_audit.zig` | G49: native prover vs from-scratch truth table |
| `docs/research/i53_falsification_2026_07_10.md` | this report |

Build/run (zig 0.14.1, single thread each, ≤41 s / ≤20 s / ≤2 s):

```bash
cd sparse_poly_discovery && zig build-exe -O ReleaseFast falsify_closure_i53.zig && ./falsify_closure_i53
cd 05_meta_synthesis   && zig build-exe -O ReleaseFast src/falsify_affine_edges_i53.zig && ./falsify_affine_edges_i53
cd 04_verified_synthesis && zig build-exe -O ReleaseFast --dep native_prover \
  -Mroot=src/g49_tt_cross_audit.zig -Mnative_prover=../core/src/adapters/native_prover.zig \
  -femit-bin=g49_tt_cross_audit && ./g49_tt_cross_audit
```

---

## Attack (a) — boundary abuse: finite domains — **SURVIVED-WITH-QUALIFIER**

The principle's statement ("cannot produce a function outside the algebraic
closure") is silent about domain size. On small domains the closure can be
*everything*, making the statement vacuous, and the repo's five "provably
nonlinear" witness targets stop being nonlinear:

| width | `x&(x>>1)` | `x&(x-1)` | `x*x` | `x|(x<<1)` | `x|(x*x)` |
|---|---|---|---|---|---|
| u1 | AFFINE | AFFINE | AFFINE | AFFINE | AFFINE |
| u2 | nonlin | nonlin | **AFFINE** (`= x&1`) | nonlin | **AFFINE** (`= x`, the identity!) |
| u4/u8 | nonlin | nonlin | nonlin | nonlin | nonlin |

Concrete witnesses (all machine-verified):
- At u1 **all 5** witnesses are affine (every unary function on one bit is),
  and the affine base reaches all 5 at depth ≤ 1. There is no "outside" to
  escape to — the principle is unfalsifiable at u1.
- At u2, `x|(x*x)` — the flagship pair-emergence witness — **is the identity
  map** (x*x mod 4 = x&1, OR-ed into x changes nothing). The affine base
  reaches it at depth 0.
- The positive side also confirmed exactly: at u2 the affine base **reaches a
  fixpoint** (64 reachable r0-functions of 256 possible) and the three targets
  that are genuinely nonlinear at u2 are **unreachable at any depth** — an
  exact, not sampled, infinite-depth closure proof.

**Qualifier the principle needs:** "T is outside the closure of S" is a
*per-width* fact; the witness formulas do not transport across domain sizes.
Any instantiation must state the domain and re-verify nonlinearity there. For
functionally-complete primitive sets on small finite domains the principle is
vacuously true (closure = everything), so ceiling claims require the closure to
be a *proper* subset — worth one sentence in `CLOSURE_PRINCIPLE.md`.

## Attack (b) — depth push on the pair-necessity claims — **BROKEN as stated**

`CLOSURE_PRINCIPLE.md` ("Refinement: the generator can be irreducibly a
*pair*") states without qualifiers: "`x&(x-1)` needs {AND,SUB}, `x|(x*x)` needs
{OR,MUL}". The underlying experiment (`synergy.zig` / `emergent_escape.md`)
only searched length ≤ 3 on 2 registers, and *its* text is properly
depth-qualified. The summary's unqualified claims fail:

**Counterexample 1 (found by search, on the repo's exact substrate — u8, K=2
registers).** BFS with exact state-dedup to depth 6:

```
x&(x-1)  =  [ r1=SHR(r0); r0=SUB(r1,r0); r1=XOR(r0,r1); r1=SHR(r1); r0=XOR(r0,r1); r0=SHL(r0) ]
```

Six instructions, ops {SHR, SUB, XOR, SHL} — **SUB alone escapes; no AND
anywhere** — verified exhaustively on all 256 inputs. The same program works on
u4. So "reachable by base+{AND,SUB} but neither base+{AND} nor base+{SUB}" is
an artifact of the depth-3 budget: at depth 6 the pair is not a pair.
Additionally at u4, base+{OR} alone reaches `x&(x-1)` at depth 8
(search-found, verified), and at u2 base+{AND} alone at depth 2.

**Counterexample 2 (constructed, exhaustively verified).** `x|(x*x)` on u4 in
19 instructions over 5 registers using ops {SHR, SHL, XOR, NOT, AND} only —
**no OR, no MUL** (square via its GF(2) bit-polynomial, OR via De Morgan). And
`x&(x-1)` on u8 in 18 instructions over 3 registers using {OR, SHL, XOR} only —
**neither AND nor SUB nor any arithmetic** (prefix-OR by doubling, then
`x&q = (x|q)^(x^q)`).

**What did NOT break:** the core ceiling. The affine base reached 0/5 nonlinear
targets everywhere — u2 exhausted exactly (fixpoint ⇒ unreachable at ANY
depth), u4 to depth 9 / 8M dedup states, u8 to depth 8 / 1.2M states. Every
escape still required at least one nonlinear generator, as the principle
predicts.

**Verdict:** the *principle* survives; the *pair-refinement claims* as printed
in `CLOSURE_PRINCIPLE.md` are false and need the qualifier "at length ≤ 3 in
2-register programs". The right correction: emergent pairs are a
budget-relative phenomenon, not an algebraic one — the honest statement is
"neither single op reaches the target *within the searched depth*".

## Attack (b′) — register bound vs op closure — **qualifier found**

The synergy substrate has K=2 registers. Its "unreachable" facts therefore mix
two different walls: the algebraic closure of the op set (what the Closure
Principle is about) and a *memory* constraint (2-register straight-line
dataflow — e.g. `a&b` = `(a|b)^(a^b)` needs three live values, impossible with
2 registers when the operands aren't recomputable). Both explicit witnesses
above use 3 and 5 registers; with K=2 the u4 `x|(x*x)` target was not found to
depth 5–8. Since {XOR, AND, NOT, shifts} is functionally complete over GF(2)
bit-polynomials given enough registers, the *op-algebraic* closure of
base+{AND} contains essentially everything — what keeps targets out at K=2 is
the register file. `CLOSURE_PRINCIPLE.md` should say its invention-domain
witnesses certify **resource-bounded reachability** (depth, registers), not
pure algebraic closure; only the affine/GF(2) row is a true closure theorem.

## Attack (c) — Tier-A affine/GF(2) theorem edge cases — **2 qualifiers, core sound**

(`05_meta_synthesis/docs/07/affine_closure_tierA_2026_05_28.md`)

- **T1** "two distinct affine maps over GF(2)^n differ on ≥ 2^(n−1) inputs":
  **SURVIVED** — exhaustive over all 8,386,560 distinct-map pairs at n=3
  (min disagreement exactly 4 = 2^(n−1), 0 violations); 2M sampled pairs at
  n=4 (min 8, 0 violations).
- **T2** W2b ("determined by the 65-point affine basis"): **SURVIVED-WITH-
  QUALIFIER, now quantified.** Among all 16,777,216 functions
  GF(2)^3→GF(2)^3, 4096 pass the basis check against the identity and **4095
  of them are non-affine impostors** (only the identity itself is affine).
  Explicit width-64 impostor `f(x) = x ^ (K·[x&3==3])` passes all 65 basis
  points yet differs from the identity on ~25% of inputs. The Tier-A doc
  *does* state W2b is conditioned on W1; this measures how load-bearing that
  condition is: W2b alone certifies nothing — any bug in W1's linear-op
  transfer functions silently voids the "all-inputs proof".
- **T3** "affine recurrence satisfies a GF(2) linear recurrence of order ≤ 64
  (Cayley–Hamilton)": **SURVIVED-WITH-QUALIFIER — off by one.** Exhaustive at
  n=1..3 (all M, c, x0, all output bits): for c=0 the max order is exactly n,
  but for c≠0 it is **n+1** (minimal counterexample n=1, M=[1], c=1: stream
  0,1,0,1,… has linear complexity 2 > 1). Sampled n=4,6,8 attain n+1 as well.
  Correct bound for affine-with-offset: **≤ 65**. This applies to exactly one
  champion (F00D mul_free, the only one with c≠0). BRank verdict unaffected
  (65 ≪ 256); the doc's own "~64" hedge was right, the "(Cayley–Hamilton)
  order ≤ 64" parenthetical is what's imprecise.

## G49 — instrument cross-audit — **PASS, 100% agreement**

Instrument under test: the exact production equivalence path
(`lowerExpr → Aig strash/miter → toSat → litAssertTrue → DPLL solve`) from
`core/src/adapters/native_prover.zig`, as used by `z3_cross_audit.zig` and the
superoptimizer. Independent checker: from-scratch recursive expression
evaluation over every assignment — zero shared code, no AIG, no SAT.

```
cases audited (full path)   : 5016          agreement: 5016/5016 = 100.0000%
  equivalent / different    : 1527 / 3489   sim-layer mismatches: 0
  decided structurally      : 780           decided by DPLL: 4236
  classes: 2034 random | 1415 template-equivalent | 1551 single-minterm-flip | 16 handcrafted
```

- The 1551 **minterm-flip** cases differ on exactly one assignment — the
  adversarial case for any sampling shortcut; the DPLL caught every one.
- The 1415 template-equivalent cases (distributivity, absorption, xor-assoc,
  mux, xnor forms) force real UNSAT proofs where structural hashing cannot
  collapse the miter (4236 cases went through the DPLL).
- The AIG **simulation layer** (`getSimValue`) was independently audited on
  every case including 148 oversize ones: 0 mismatches vs direct evaluation.
- **Disagreement count: 0.** Combined with G48 (toAig per-op, after its AND/SHL
  fixes) and the 99-case z3 audit, the equivalence kernel is now triangulated
  by three independent instruments.

Bound honored: the native solver is a full-enumeration backtracker (2^nodes),
so cases were capped at ≤18 AIG nodes / ≤4 variables; 148 oversize cases were
sim-audited only. This matches the original G49 caveat: the kernel is validated
**small**; nothing here certifies 64-bit-scale behavior.

---

## Verdict table

| attack | claim attacked | verdict |
|---|---|---|
| (a) width boundary | "targets provably outside the affine closure" | **SURVIVED-WITH-QUALIFIER** — witnesses are width-relative; 5/5 affine at u1, 2/5 at u2 (`x\|(x*x)` = identity); principle vacuous for complete sets on tiny domains |
| (b) depth push | "`x&(x-1)` needs {AND,SUB}" | **BROKEN** — SUB alone at depth 6 on the repo's own u8/K=2 substrate (search-found, exhaustively verified); OR alone at depth 8 (u4) |
| (b) depth push | "`x|(x*x)` needs {OR,MUL}" | **BROKEN** — 19-instr witness with {SHR,SHL,XOR,NOT,AND} only (u4, K=5, exhaustively verified) |
| (b) depth push | core ceiling: affine base reaches no nonlinear target | **SURVIVED** — exact fixpoint proof at u2; depth 9/8M states (u4), depth 8/1.2M (u8): 0/5 everywhere |
| (b′) register probe | "closure" = op algebra | **QUALIFIER** — synergy-substrate walls are (depth, K=2-register) resource bounds, not algebraic closure |
| (c) T1 min-distance | distinct affine maps differ on ≥ 2^(n−1) | **SURVIVED** (exhaustive n=3) |
| (c) T2 W2b basis | 65-point check = all-inputs proof | **SURVIVED-WITH-QUALIFIER** — 4095/4096 basis-passers are impostors; sound only conditioned on W1 (doc says so; now quantified) |
| (c) T3 recurrence order | "order ≤ 64 (Cayley–Hamilton)" | **SURVIVED-WITH-QUALIFIER** — correct bound is n+1 = 65 for c≠0 (exhaustive n≤3); affects the F00D mul_free champion only; BRank conclusion intact |
| G49 | native prover trustworthy? | **PASS** — 5016/5016 agreement, 0 sim mismatches |

## Qualifiers the Closure Principle now needs (proposed wording)

1. **Domain qualifier:** "outside the closure" is a per-domain-width fact and
   must be re-established at the width used; the statement is vacuous when the
   primitive set is functionally complete on the (finite) domain.
2. **Resource qualifier:** for program-search witnesses, replace "outside the
   algebraic closure of the set" with "not reachable at depth ≤ D with K
   registers"; only the affine/GF(2) row is a depth- and resource-independent
   closure theorem.
3. **Pair-refinement correction:** delete or re-qualify "needs {AND,SUB}" /
   "needs {OR,MUL}" — both are false at depth 6–8 or with 3–5 registers;
   emergent pairs are budget-relative.
4. (Tier-A doc) "order ≤ 64" → "order ≤ 65 for affine-with-offset (≤ 64 when
   c = 0)".

## Remaining untested attack surface (honest list)

- **wcore Claim C instruments** (`behaviorMatches`, the depth-4/5 reduction of
  85/86 solvers, the irreducibility certifier) were not re-attacked this round
  (G46/#46 covered `behaviorMatches` threshold; the depth-budget of the
  *reducer* has the same depth-artifact risk exposed here in (b) — worth its
  own round).
- The other closure witnesses (mixer SAC=0.5 theorem, k-sparse parity, the
  XOR-encoder information destruction) were not attacked here; the last already
  survived `falsification_hunt.md`.
- u4/u8 non-affine BFS runs hit state caps (8M/1.2M dedup states), so their
  "not found ≤ depth D" lines are bounded statements, not unreachability
  proofs (only u1/u2 reached fixpoints). State dedup uses 128-bit hashes: a
  collision could only *hide* a state (false "not found"), never fake a
  witness — every reported witness is re-verified by direct execution over all
  inputs.
- No u8 witness for `x|(x*x)` without {OR,MUL} was constructed (the u4 one
  refutes the general claim; the u8-specific instance is very likely also
  breakable via the same bit-polynomial route but the mod-256 squarer was not
  hand-built).
- G49 covers ≤4 vars / ≤18 AIG nodes and does not exercise `Aig.sweep`,
  `createBvMiter`, or 64-bit `BitVector` chains (G48 covered per-op lowering;
  the `toAig` returns-only-LSB API hazard noted there still stands).
