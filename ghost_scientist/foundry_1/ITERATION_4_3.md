# Foundry-4.3 bounded A3/A9 adapters

A3 and A9 now execute behind the frozen evaluator-owned arm contract on an
executable typed-DAG artifact. This is bounded interface readiness, not
validation-v6 integration.

The pre-frozen artifact contains eight typed vector nodes over `add`, `mul`,
and `relu`, including repeated motifs and three distinct numerical
invocations. A primary and independently implemented parser reject malformed
graphs, cycles, type mismatches, and unsupported operations. Their separate
interpreters produce the exact declared result on all three invocations.

Both motif implementations enumerate 13 typed paths and eight exact body
groups. A3 selects three repeated positive-MDL motifs covering six nodes. A9
greedily selects two motifs covering all eight nodes. Both start and finish
with the empty-state digest and retain no library across artifacts.

Nine hostile artifacts are rejected by both implementations. The two complete
adapter paths and the conformance path terminate naturally under identical
process-tree ceilings, charge CPU, sample group RSS, and reap their process
groups.

The result does not increase the integrated-arm count. The typed artifact
surface contains only three primitive operations and has no real
validation-runtime mount. Calling that production integration would repeat
the hand-built-proxy error Foundry-0 was designed to prevent.

**Verdict:** `FOUNDRY_V6_NOT_READY`  
**Prerequisites:** `4/6`  
**Required arms integrated:** `2/10`  
**A3/A9:** bounded adapter interface ready; production integration incomplete
