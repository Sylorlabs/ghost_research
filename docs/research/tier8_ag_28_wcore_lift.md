# T8-AG-28 — wcore/E4-G00 promote lift

**Agent:** T8-AG-28  
**Phase:** 6  
**Verdict:** **PASS**

## Reproduce

```bash
zig build tier8-wcore-lift --release=fast
```

## Measured

| Metric | Value |
|--------|-------|
| Tax pass | true |
| sum_mod coverage base | 0.859 |
| sum_mod coverage seeded | 1.000 |

Fixes "novel but 0 lift" — survivor improves downstream sum_mod task.

## Fork

- **T8-AG-28f** — minimal promote set