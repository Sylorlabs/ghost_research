# G48: `toAig` faithfulness audit

**Status:** built, measured — exhaustive truth-table comparison of
`domain_superoptimizer.GraphProgram.toAig` lowering vs `execute`.

**Reproduce:**
```bash
cd ghost_research
zig build-exe -OReleaseFast \
  --dep native_prover --dep domain_superoptimizer \
  -Mroot=05_meta_synthesis/src/toaig_audit.zig \
  -Mnative_prover=core/src/adapters/native_prover.zig \
  -Mdomain_superoptimizer=core/src/adapters/domain_superoptimizer.zig \
  -femit-bin=/tmp/toaig_audit
/tmp/toaig_audit
```

Or via `05_meta_synthesis` after a full `zig build -Doptimize=ReleaseFast` (requires
all core modules present).

## Method

For each ISA op (`XOR`, `SHR`, `AND`, `ROTL`, `SHL`):

1. Build a single-node `GraphProgram` with `src1 = 0` (input `x`) and `imm ∈ 0..63`.
2. Exhaustively enumerate all `x` at **width 4** (16 cases) and **width 8** (256 cases).
3. Compare `execute(x)` (masked to width) against the AIG word obtained by mirroring
   the exact `toAig` switch in `core/src/adapters/domain_superoptimizer.zig`, evaluated
   via native prover simulation (`Aig.setInputSimValue` / `getSimValue`).

Upper bits above the test width are held at constant zero in the input `BitVector`.

## Results (after fix)

| Op   | Width 4 | Width 8 | Status |
|------|---------|---------|--------|
| XOR  | 0       | 0       | **PASS** |
| SHR  | 0       | 0       | **PASS** |
| AND  | 0       | 0       | **PASS** |
| ROTL | 0       | 0       | **PASS** |
| SHL  | 0       | 0       | **PASS** |

```
VERDICT: PASS
total mismatches: 0
failed op/width pairs: 0
```

## Results (before fix)

| Op   | Width 4 | Width 8 | Status |
|------|---------|---------|--------|
| XOR  | 0       | 0       | **PASS** |
| SHR  | 0       | 0       | **PASS** |
| AND  | 964     | 16328   | **FAIL** |
| ROTL | 0       | 0       | **PASS** |
| SHL  | 945     | 16065   | **FAIL** |

```
VERDICT: FAIL
total mismatches: 34302
failed op/width pairs: 4  (AND@w4, SHL@w4, AND@w8, SHL@w8)
```

### First mismatch witnesses (before fix)

| Op  | Width | imm | x | execute | aig   |
|-----|-------|-----|---|---------|-------|
| AND | 4     | 0   | 0 | 0x0     | 0x1   |
| SHL | 4     | 1   | 1 | 0x2     | 0x1   |
| AND | 8     | 0   | 0 | 0x0     | 0x1   |
| SHL | 8     | 1   | 1 | 0x2     | 0x1   |

## Root causes (confirmed in source)

In `core/src/adapters/domain_superoptimizer.zig` **before** the fix:

```zig
.AND => try v1.xorBv(aig, prover.BitVector.initConstant(aig, @as(u64, 1) << n.imm)),
//      ^^^ should be bitwise AND with mask constant, not XOR

.SHL => v1.shrBv(aig, 0), // Dummy
//      ^^^ identity (shift-right by 0), not left shift
```

- **AND:** `execute` does `v1 & (1 << imm)`; `toAig` XORed with the mask — wrong opcode.
- **SHL:** `execute` does `v1 << imm`; `toAig` was a no-op placeholder (`shrBv(..., 0)`).
  `native_prover.BitVector` had `shrBv` and `rotlBv` but no `shlBv` or `andBv`.

## Fix applied

1. Added `andBv` and `shlBv` to `native_prover.BitVector` (mirroring `xorBv` / `shrBv`).
2. Updated `domain_superoptimizer.GraphProgram.toAig`:

```zig
.AND => try v1.andBv(aig, prover.BitVector.initConstant(aig, @as(u64, 1) << n.imm)),
.SHL => v1.shlBv(aig, n.imm),
```

3. Updated `05_meta_synthesis/src/toaig_audit.zig` mirror to match.

### Additional API note

`toAig` returns only `bvs[self.used].bits[0]` (LSB), not the full lowered
`BitVector`. Even with AND/SHL fixed, multi-bit programs still lose
bits 1..W−1 at the API boundary. This audit compared the full lowering semantics,
not the truncated return value.

## Verdict

**PASS** — `toAig` is now **faithful** for all 5/5 ISA ops at widths 4 and 8.
XOR, SHR, AND, ROTL, and SHL all match `execute` exactly after the fix.

## Files changed

- `core/src/adapters/native_prover.zig` — add `BitVector.andBv`, `BitVector.shlBv`
- `core/src/adapters/domain_superoptimizer.zig` — fix AND/SHL in `toAig`
- `05_meta_synthesis/src/toaig_audit.zig` — mirror fix + exhaustive audit harness
- `05_meta_synthesis/build.zig` — register `toaig_audit` executable
- `docs/research/swarm_g48_toaig_audit.md` — this report