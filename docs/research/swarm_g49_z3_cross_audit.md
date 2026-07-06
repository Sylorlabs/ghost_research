# G49 — Cross-audit: native SAT prover vs libz3

**Research question 49:** Does the native SAT prover agree with **libz3** on a
battery of equivalence checks?

**Status:** measured — **PASS** (99/99 agreement, 100%)

**Reproduce:**
```bash
cd 04_verified_synthesis
# standalone build (thread build currently blocked on missing absolute_final.zig)
zig build-exe -OReleaseFast \
  -isystem /usr/include -L/usr/lib/x86_64-linux-gnu -lz3 -lc \
  --dep native_prover --dep smt_verify \
  -Mroot=src/z3_cross_audit.zig \
  -Mnative_prover=../core/src/adapters/native_prover.zig \
  -Msmt_verify=../core/src/adapters/smt_verify.zig \
  -femit-bin=zig-out/bin/z3_cross_audit
./zig-out/bin/z3_cross_audit --timeout-ms=1000
```

## Setup

| Component | Location | Role |
|-----------|----------|------|
| Native prover | `core/src/adapters/native_prover.zig` | AIG lowering + miter + DPLL SAT |
| Z3 runner | `core/src/adapters/smt_verify.zig` (`runSmtLib`) | Real `libz3` at `/usr/lib/x86_64-linux-gnu/libz3.so` |
| `verify_cli` | `04_verified_synthesis/src/verify_cli.zig` | Production Z3 path for mixer/sort champions |
| Harness | `04_verified_synthesis/src/z3_cross_audit.zig` | G49 battery + comparison |

**libz3:** available on this machine (`libz3.so.4`). Full cross-audit ran; no
native-only fallback required.

## Method

Both verifiers answer the same question for each case:

> ∃ assignment to Boolean inputs such that `left ≠ right`?

- **UNSAT** → formulas are equivalent
- **SAT** → not equivalent (witness exists)

### Battery (99 cases)

1. **24** standard Boolean identities (De Morgan, absorption, distributivity, XOR laws, …)
2. **7** deliberately non-equivalent pairs (regression guards)
3. **1** invalid “consensus” identity (known false equivalence — both should reject)
4. **9** variable-slot sweeps (v0/v1/v2)
5. **60** seeded template replicates (commutativity, nested De Morgan, absorption, …)

All cases use ≤3 Boolean variables (QF_UF for Z3). Timeout per Z3 call: 1000 ms.

## Results (2026-07-05)

```
cases_run:              99
agreement:              99/99 (100.00%)
disagreements:          0
native_errors:          0
z3_unknown:             0
expect_match_native:    99/99
expect_match_z3:        99/99
VERDICT:                PASS
```

No disagreements. Both verifiers matched ground-truth `expect_equiv` on every case.

## Bugs found and fixed during audit

The first audit runs **failed**; fixes were applied before the passing run:

1. **`native_prover.toSat`** — primary inputs (`{0,0}` AIG nodes) were incorrectly
   encoded as `AND(false,false)`, pinning all inputs to false. Fixed: skip
   structural clauses for input nodes.

2. **Miter literal polarity** — asserting “miter true” used `(id>>1)+1` without
   inversion bit; constant-TRUE miters were over-constrained. Fixed:
   `litAssertTrue()` in the harness (and mirrored in `superoptimizer_search` pattern).

3. **Harness UB** — expression trees stored pointers into `buildBattery` stack
   frames; crashed after ~40 cases. Fixed: arena-allocated expression DAG (`Eb` builder).

4. **Z3 SMT emission** — malformed parenthesis in hand-expanded `xor` for QF_UF.
   Fixed before passing run.

## Verdict

**PASS** — on 99 Boolean equivalence checks spanning identities and
anti-identities, the native SAT prover and libz3 are in **100% agreement**.

### Caveats

- Native solver is a **naive DPLL backtracker** (not industrial CDCL); this audit
  covers **small** circuits only (≤3 inputs). Do not extrapolate to 64-bit mixer
  `verify_cli` paths without separate benchmarking.
- `verify_cli` exercises different SMT (mixer bijection / sort nets), not this
  exact battery; G49 validates the **equivalence-checking kernel**, not the full
  champion CSV pipeline.
- Thread `04_verified_synthesis` `zig build` is currently blocked by missing
  `core/src/absolute_final.zig`; the harness builds standalone as shown above.

## Files changed

| File | Change |
|------|--------|
| `04_verified_synthesis/src/z3_cross_audit.zig` | **new** — G49 harness |
| `04_verified_synthesis/build.zig` | register `z3_cross_audit`, import `native_prover` |
| `core/src/adapters/native_prover.zig` | fix `toSat` input-node handling |
| `docs/research/swarm_g49_z3_cross_audit.md` | **this report** |