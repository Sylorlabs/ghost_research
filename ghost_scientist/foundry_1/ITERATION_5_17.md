# Foundry readiness iteration 5.17

Phase 127 authenticates the locked identities and official release channels
for `az 1.3.0`, `fixed 1.30.0`, and `sorted-vec 0.8.10`. No exact archive or
source bytes are locally available. A GitHub `sorted-vec2` fork was inspected
and rejected because it declares a different package and version and its source
diverges from the published crate.

The direct Kiddo family therefore remains `4/8` packages and 20 authenticated
source records. The resolver remains stopped at the absent `kiddo 5.2.4` root.
No compilation, control execution, P1 advance, or validation-v6 access is
claimed.
