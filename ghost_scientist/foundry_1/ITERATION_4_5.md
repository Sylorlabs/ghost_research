# Foundry-4.5 framework-runtime mount

The evaluator-side framework runtime mount is now real on calibration.

Both A3 and A9 mounted all 23 available calibration graphs, spanning all 41
observed operator targets and 337 call-function sites. Each graph ran three
times per arm through both eager and exported framework execution. Two
independent output checks accepted shape, dtype, layout, values, and output
alias relationships with zero maximum error.

The search paths remain behaviorally distinct: A3 selected 76 tools and
covered 126 nodes; A9 selected 83 tools and covered 226 nodes. Independent
semantic matching checked every selected motif. Both arms began and ended
every artifact with empty state.

Each complete 23-graph arm process tree also passed identical wall, CPU, and
RSS ceilings. This does not close P3. One process mounts 23 artifacts, while
the frozen contract has no shared resource-receipt identity. Copying that
single receipt into 23 artifact outputs would overcount resources, so
per-artifact contract assembly remains fail-closed.

No validation-v6 source, runtime, graph, or outcome was accessed.

**Verdict:** `FOUNDRY_V6_NOT_READY`  
**Framework mount:** calibration component pass  
**Required arms integrated:** `2/10`
