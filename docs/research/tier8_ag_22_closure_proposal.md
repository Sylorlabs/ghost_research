# T8-AG-22 — Closure revision proposal schema

**Agent:** T8-AG-22  
**Phase:** 5  
**Verdict:** **PASS**

## Deliverable

`closure_revision.zig` — typed `ClosureRevisionProposal` emitted from tax taxonomy.

Output: `/tmp/tier8-swarm/closure_revision_proposal.json`

## Reproduce

```bash
zig build tier8-closure-proposal --release=fast
```

## Proposal

`CRP-world-sum-v4` — expand `world_sum_mod` basis (v3→v4) when mono/walsh remix dominates.