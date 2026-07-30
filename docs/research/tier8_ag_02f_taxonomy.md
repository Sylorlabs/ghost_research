# T8-AG-02f — Per-promote remix taxonomy

**Agent:** T8-AG-02f (fork of T8-AG-02)  
**Phase:** 1  
**Seeds:** grid `0xF0235A11CE0FF1CE`, battery `0xE1B10D20A11CE01`  
**Verdict:** **PASS**

## Deliverable

`tier8_tax_taxonomy.zig` — strict-tax invention engine run with per-promote JSON taxonomy from `equivalence_tax.witnessRemix()`.

## Reproduce

```bash
cd sparse_poly_discovery
zig build tier8-tax-taxonomy --release=fast
```

Log: `/tmp/tier8-swarm/T8-AG-02f.log`

## Remix class histogram (v3 basis, 2026-07-06)

| Primary family | Remix blocks |
|----------------|--------------|
| monomial | 10 |
| walsh | 6 |
| pipeline | 1 |
| **novel** | **1** |

18 promotions checked, 17 remix-blocked (5.6% novel rate). Solve 11/11 unchanged.

Dominant remix path: **monomial** static pool reproduces Walsh/pair promotions at budget 8; one inversion-parity escape blocked by **pipeline** half_p.