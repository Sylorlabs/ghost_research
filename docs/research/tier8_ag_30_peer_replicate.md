# T8-AG-30 — Peer replication protocol

**Agent:** T8-AG-30  
**Phase:** 6  
**Verdict:** **PASS**

## Reproduce

```bash
zig build tier8-peer-replicate --release=fast
```

## Measured

Tax survivor `world_sum_mod=7` replicates on **3/3** independent seeds (E11, RQ7, battery B).