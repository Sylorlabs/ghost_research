# T8-AG-26 — Reality anchor trait

**Agent:** T8-AG-26  
**Phase:** 6 (Tier 8c reality anchoring)  
**Verdict:** **PASS**

## Deliverable

`reality_anchor.zig` — pluggable `FileAnchor` + `PeerReplayAnchor`.

## Reproduce

```bash
zig build tier8-reality-anchor --release=fast
```

## Measured

| Anchor | Result |
|--------|--------|
| File oracle | PASS |
| Peer replay (0xA7C0DE…) | PASS |