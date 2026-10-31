# T8-AG-21f — Proposer-path remix alert

**Agent:** T8-AG-21f  
**Phase:** 5 fork  
**Verdict:** **PASS**

## Reproduce

```bash
zig build tier8-remix-monitor-f --release=fast
```

Log: `/tmp/tier8-swarm/T8-AG-21f.log`

## Measured

Parses T8-AG-07/08 tax logs; sustained alert fires on proposer paths (<20% novel).