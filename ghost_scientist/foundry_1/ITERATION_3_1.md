# Foundry-3.1 pre-frozen Enumo metamorphic failure

Enumo failed its precommitted exact learned-rule-set invariance test.

Before execution, the protocol froze new literal variable names, reordered
values, variables, and operators, and required equality of the entire sorted
directed rule set. The Boolean domain and exact upstream algorithm source were
unchanged.

Workload counts remained `93`, `348`, and `4599`, but stage rule counts changed
from `[26, 7, 27]` to `[26, 9, 32]`. The total learned set changed from `60` to
`67`; 30 baseline-only and 37 transformed-only rules made the exact-set
relation false. Execution ended naturally with a complete 12-process receipt.

This is a genuine negative, not an infrastructure failure. It shows that
Enumo's selected syntactic basis is sensitive to enumeration order under this
test. It does not erase the official Boolean conformance pass, and the same
implementation/domain cannot count as another independent control.

Source-faithful independent-control conformance remains `3/4`.

**Verdict:** `FOUNDRY_V6_NOT_READY`
