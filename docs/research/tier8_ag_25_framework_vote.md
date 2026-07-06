# T8-AG-25 — Framework vote harness

**Agent:** T8-AG-25  
**Phase:** 5  
**Verdict:** **PASS**

## Deliverable

`framework_vote.zig` — blocks auto-retire without witness; records approved revisions.

## Reproduce

```bash
zig build tier8-framework-vote --release=fast
```