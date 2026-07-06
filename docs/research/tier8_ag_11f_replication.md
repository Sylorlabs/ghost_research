# T8-AG-11f — Battery C held-out replication ×2

**Agent:** T8-AG-11f (fork of T8-AG-11)  
**Phase:** 3  
**Verdict:** **PASS**

## Reproduce

```bash
cd sparse_poly_discovery
zig build tier8-battery-c-replicate --release=fast
```

Log: `/tmp/tier8-swarm/T8-AG-11f.log`

## Results (2026-07-06)

| Grid seed | mean mono cov | hard targets | Verdict |
|-----------|---------------|--------------|---------|
| `0xC1B10D20260706` | 0.500 | 11/11 | PASS |
| `0xC2B10D20260707` | 0.497 | 11/11 | PASS |
| baseline `0xF0235A11CE0FF1CE` | 0.498 | 11/11 | PASS |

All three seeds: mean mono < 0.55, all 11 targets individually hard. Battery C hardness is seed-stable.