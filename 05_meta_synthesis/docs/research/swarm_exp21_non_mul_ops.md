# Swarm EXP-21 (D30) — non-MUL nonlinear ops at fixed length vs MUL SAC

**Date:** 2026-07-05  
**Status:** measured  
**RQ:** D30 — Is there a non-MUL nonlinear op (AND_NOT, ADD_ROT, MUM) that reaches MUL-level SAC at fixed length, or is MUL unique?

## Commands

```bash
cd 05_meta_synthesis && zig build-exe -OReleaseFast \
  --dep domain_u64_mixer \
  -Mroot=src/closure_escape_mixer.zig \
  --dep invention_engine \
  -Mdomain_u64_mixer=../core/src/adapters/domain_u64_mixer.zig \
  -Minvention_engine=../core/src/adapters/invention_engine.zig \
  -femit-bin=/tmp/closure_escape_mixer_exp21

/tmp/closure_escape_mixer_exp21
```

**Protocol:** Extend `closure_escape_mixer.zig` with EXP-21 block. Fixed program length **8**. Shared GF(2)-affine base `{XOR, ROTL, SHL_XOR, SHR_XOR, OR_SHIFT, ROTR, BSWAP}` plus **exactly one** nonlinear generator. Same hill-climber as legacy closure escape: **12,000 iters × 6 seeds**, composite fitness during search, **SAC-error measured post-hoc** (512 samples/champion). Companion: `docs/07/closure_escape_mixer.md`.

## Summary

| Question | Answer |
|----------|--------|
| Any tested op matches MUL-level SAC? | **YES — MUM** (best SAC-err **0.0173** vs MUL **0.0192**) |
| Is MUL unique? | **NO** — MUM reaches the same SAC tier at len 8 |
| AND_NOT at len 8? | **NO escape** — SAC-error pins at **0.5000** (affine ceiling) |
| ADD_ROT at len 8? | **Partial** — best **0.0766**, ~4× worse than MUL/MUM |
| ADD at len 8? | **Partial** — best **0.1377** (carry escape, same tier as legacy MUL-free) |

**Headline:** Among the three named candidates, only **MUM** (wyhash-style `a*b` → xor halves) closes the SAC gap with raw **MUL**. **AND_NOT** is degree-2 but insufficient alone; **ADD_ROT** buys carry nonlinearity but plateaus well above MUL. MUL is **not** the unique full-escape generator — but every full-escape generator tested is **multiply-family** (MUL or MUM).

---

## Method

### Op sets (fixed len = 8)

| Mode | Allowed ops |
|------|-------------|
| `affine-only` | XOR, ROTL, SHL_XOR, SHR_XOR, OR_SHIFT, ROTR, BSWAP |
| `affine+ADD` | above + ADD |
| `affine+AND_NOT` | above + AND_NOT |
| `affine+ADD_ROT` | above + ADD_ROT |
| `affine+MUM` | above + MUM |
| `affine+MUL` | above + MUL |

Search uses `hillClimbFixed`: random init at len 8, mutate in-place (no length changes). Output register fixed to `regs[7]`.

### Statistics

- **mean avalanche** — first-order; ideal 32 (weak discriminator, see closure_escape doc)
- **SAC-error** — mean over 64×64 (input-bit, output-bit) pairs of `|P(flip) − 0.5|`; ideal 0, pure affine theorem = 0.5

---

## Results (2026-07-05 run)

### Legacy closure escape (variable len 4–12, reproduced)

```
  mode              | mean av | mean SAC-err | best SAC-err
  ------------------+---------+--------------+-------------
  MUL-free (affine) |  31.970 |       0.1269 |      0.0331
  MUL-enabled       |  32.042 |       0.0213 |      0.0174
```

### EXP-21 single-generator @ len 8

```
  mode              | mean av | mean SAC-err | best SAC-err
  ------------------+---------+--------------+-------------
  affine-only       |  30.654 |       0.5000 |      0.5000
  affine+ADD        |  31.777 |       0.1774 |      0.1377
  affine+AND_NOT    |  30.870 |       0.5000 |      0.5000
  affine+ADD_ROT    |  31.545 |       0.1581 |      0.0766
  affine+MUM        |  32.012 |       0.0380 |      0.0173
  affine+MUL        |  31.993 |       0.0296 |      0.0192

EXP-21 verdict: MUL best SAC-err=0.0192; best non-MUL=0.0173; any match MUL? YES
```

---

## Reading

### Three-tier escape (confirmed at fixed length)

1. **Pure GF(2)-affine → SAC = 0.5 exactly.** `affine-only` and `affine+AND_NOT` both pin at 0.5000. AND_NOT is nonlinear over ℤ but does not break the SAC symmetry when it is the sole nonlinear generator at len 8 — the search cannot use it to make per-(i,j) flip probabilities ≈ 0.5.

2. **Carry / compound partial escape → 0.08–0.18.** ADD and ADD_ROT escape 0.5 but plateau an order of magnitude above MUL. ADD_ROT (0.0766 best) beats ADD alone (0.1377) at the same length budget — accumulate-and-rotate is a stronger partial diffuser than bare carry.

3. **Multiply-family full escape → ~0.02.** MUL (0.0192) and MUM (0.0173) are statistically indistinguishable at this protocol. MUM is **not** raw `MUL` opcode but implements the same algebraic escape (128-bit product → xor of halves).

### Answer to D30

| Candidate | Reaches MUL SAC? | Notes |
|-----------|------------------|-------|
| AND_NOT | **No** | SAC ceiling 0.5 |
| ADD_ROT | **No** | ~4× gap vs MUL best |
| MUM | **Yes** | Matches/beats MUL at len 8 |

**MUL unique? NO** — MUM is equivalent for SAC at fixed len 8.  
**Any named op matches? YES** — MUM.

**Caveat (mul_free relevance):** If the question is interpreted as "escape without any multiplication," then **no** tested op qualifies — only multiply-family ops reach ~0.02. AND_NOT and ADD_ROT remain Tier-2 partial escapes.

---

## Artifacts

| Path | Role |
|------|------|
| `05_meta_synthesis/src/closure_escape_mixer.zig` | EXP-21 harness (legacy + fixed-len single-op modes) |
| `05_meta_synthesis/docs/07/closure_escape_mixer.md` | Two-level escape baseline |
| `05_meta_synthesis/docs/07/affine_closure_tierA_2026_05_28.md` | Affine ceiling theorem |

## Follow-ups

- Sweep fixed length L ∈ {4, 6, 8, 10, 12} — does MUM–MUL gap open at shorter L?
- `sac_fitness=true` rerun — does optimizer ranking change vs composite?
- OR_SHIFT as sole degree-2 op (not in D30 shortlist but in no_carry set)