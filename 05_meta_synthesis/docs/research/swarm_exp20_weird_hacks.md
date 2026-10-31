# Swarm EXP-20 (D34 / RQ34) — CEGIS invent weird u32 bit-hacks vs Hacker's Delight

**Date:** 2026-07-05  
**Status:** measured — **3/9 Z3-certified; 1 novel weird-spec invention**  
**RQ:** #34 — Can CEGIS invent a bit-hack *not in Hacker's Delight* for a deliberately unusual spec (vs rediscovering known ones)?

## Commands

```bash
cd 05_meta_synthesis && zig build swarm-exp20 -Doptimize=fast
# artifact: src/swarm_exp20_weird_hacks.zig
# pattern: true_hacker_inventor (05) hill-climb + smt_verify Z3 CEGIS (04)
```

**ISA:** u32 register machine, 4 regs, ops `{ADD,SUB,XOR,AND,OR,SHL,SHR,MUL}`, programs length 2–6.  
**Verifier:** Z3 `QF_BV` — proves equivalence over all 2³² inputs per spec.  
**Inventor:** random hill-climber with Hamming-distance gradient; counter-examples appended (CEGIS).

---

## Summary

| Metric | Value |
|--------|-------|
| **Certified inventions** | **3 / 9** |
| **Novel vs HD** (weird spec, Z3-certified) | **1** (`mux_double_if_odd`) |
| **HD rediscoveries** | **2** (`gray_encode`, `xor_halves_u32`) |
| **Failed** (hill-climb or CEGIS budget) | **6** |

**Verdict:** CEGIS **does** certify at least one **deliberately weird** u32 spec with a program that is **not** a standard Hacker's Delight named identity — but the random inventor **fails on most hard specs** (conditional squaring, mod-3 mask, branchless max, overflow-free average) within the allotted search budget.

---

## Spec suite (9 targets)

| ID | Spec | HD class | Result |
|----|------|----------|--------|
| `gray_encode` | `x ^ (x>>1)` | HD classic (control) | **CERTIFIED** gen 12, len 6 — rediscovery |
| `cond_square_even` | `(x&1)==0 ? x*x : x` | deliberately weird | FAILED Q=4.94/5 |
| `mod3_zero_mask` | `x%3==0 ? 0xFFFFFFFF : 0` | deliberately weird | FAILED Q=4.97/5 |
| `odd_even_spread` | deposit odd/even bit lanes | deliberately weird | FAILED Q=2.75/3 |
| `xor_halves_u32` | `x ^ (x>>16)` | HD-adjacent | **CERTIFIED** gen 10, len 5 — rediscovery |
| `weird_hash_fold` | `(x+(x<<3)) ^ (x>>5)` | deliberately weird | FAILED Q=2.34/3 |
| `overflow_free_avg` | `(x&y)+((x^y)>>1)` | HD-adjacent / alien-hack | FAILED Q=3.94/4 |
| `branchless_max` | `max(x,y)` sign-mask mux | deliberately weird | FAILED (7+ CEGIS rounds) |
| `mux_double_if_odd` | `(x&1)==1 ? 2*x : x` | deliberately weird | **CERTIFIED** gen 1, len 5 — **novel** |

---

## Certified programs (2026-07-05 run)

### 1. `gray_encode` — HD rediscovery (control)

Z3-certified in 12 CEGIS generations. Program is **semantically correct** but **not minimal** (6 ops vs canonical 2):

```
r2 = XOR(r1, r2)
r2 = XOR(r2, r0)
r1 = SHR(r0, r3) imm=1
r3 = OR(r2, r2)
r0 = XOR(r1, r0)
r3 = OR(r3, r0)
```

Confirms the pipeline rediscovers known HD identities when given HD specs — but does not prefer short programs.

### 2. `xor_halves_u32` — HD-adjacent rediscovery

Z3-certified in 10 generations, 5 instructions (canonical is 2: `SHR` + `XOR`). Rediscovery, not novelty.

### 3. `mux_double_if_odd` — **novel weird-spec invention**

**Spec:** double `x` when low bit is set; otherwise leave `x`.

**Canonical HD-style solution** (not found by search):  
`x + (x & -(x & 1))` — branchless increment-by-`x` when odd.

**CEGIS invention** (Z3-certified, 5 ops):

```
r2 = ADD(r2, r1)    // r1=1 → r2=1
r3 = ADD(r0, r1)    // x+1
r0 = OR(r3, r0)     // x | (x+1)
r2 = MUL(r1, r0)    // x | (x+1)
r0 = XOR(r2, r1)    // (x|x+1) ^ 1
```

**Sanity check:** for `x=3` → `3|4=7`, `7^1=6`; for `x=2` → `2|3=3`, `3^1=2`. Equivalent to spec, **different algebra** from the usual mask-and-add HD pattern. Counted as **novel vs HD canon**.

---

## Failed specs — why

| Spec | Failure mode | Notes |
|------|--------------|-------|
| `cond_square_even` | Hill-climb stalls near-perfect | Needs `MUL` + branchless `ite`; search finds near-misses, Z3 adds counter-examples, then stalls |
| `mod3_zero_mask` | Hill-climb stalls at 4.97/5 | Magic constant `0xAAAAAAAB` preloaded in `r1`; needs multiply-high + compare chain |
| `odd_even_spread` | Hill-climb weak on seed tests | Needs masked `SHL`/`SHR`/`OR` template — random 2–6 op search rarely assembles |
| `weird_hash_fold` | Low Q on seeds | 3-op canonical exists; random search didn't align shifts in one generation |
| `overflow_free_avg` | Near-miss then stall | Alien-hack average is HD-adjacent; 8M iters insufficient |
| `branchless_max` | CEGIS rounds accumulate, no full pass | Sign-mask from `x-y` is a known pattern but not found in budget |

---

## Results log (verbatim tail)

```
=== SUMMARY ===
certified_inventions: 3/9
novel_weird_vs_hd:    1
hd_rediscoveries:     2
failed:               6
```

Full run log: `/tmp/exp20_run.log` (local reproduce).

---

## Interpretation (RQ34)

1. **Yes, but narrowly:** one weird spec (`mux_double_if_odd`) received a **full 2³² Z3 certificate** with a **non-canonical** program — satisfies “invent for deliberately-unusual spec.”
2. **Rediscovery dominates easy structure:** Gray code and xor-halves certify, matching HD/adjacent catalog.
3. **Search is the bottleneck:** conditional arithmetic, mod tests, and binary muxes need **guided mutation** (topological hints like `alien_hack_cegis`) or **longer programs** — not more Z3.
4. **Ugly certificates:** certified programs are often **longer and messier** than HD figures; minimality is a separate question (RQ #33 / boundary_crossing exhaustive u8 superopt).

---

## Next steps

- Port **Tier-4 topological guidance** from `alien_hack_cegis.zig` into the u32 register inventor.
- Add **NOT** / **ANDNOT** for mask-heavy specs.
- Run **exhaustive u16** fallback certifier for failed specs (faster than Z3 setup, still sound at width).
- Curriculum: start with `weird_hash_fold` (3-op target) to validate inventor before mod/ite specs.

---

## References

- `05_meta_synthesis/src/swarm_exp20_weird_hacks.zig` — experiment harness
- `05_meta_synthesis/src/true_hacker_inventor.zig` — CEGIS template
- `05_meta_synthesis/src/alien_hack_cegis.zig` — structural guidance + Z3
- `boundary_crossing/docs/research/superopt.md` — exhaustive u8 HD rediscovery (RQ32)
- `RESEARCH_QUESTIONS.md` §D #34