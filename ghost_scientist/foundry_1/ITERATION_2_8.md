# Foundry-2.8 Babble source control

The selected second-control route now executes, but the result is a
source-faithful core build rather than the full official artifact CLI.

The build verifies 62 upstream Git blobs before compilation:

- Babble at `09ff03fd485a3e24178c1d706a5944a230123ba1`;
- the lockfile-selected Egg fork at
  `caf623cad25cacba83193464dcf0d3dd4161ba7a`;
- Babble's local procedural-macro workspace;
- `symbolic-expressions` 5.0.3; and
- `instant` 0.1.12.

The selected Babble modules are staged byte-for-byte into their native module
layout. One generated-only compatibility edit qualifies `Self(node)` as
`Expr(node)` inside a nested helper for modern Rust; the pinned source remains
unchanged. Itertools 0.12 substitutes for 0.10 and Hashbrown 0.12 substitutes
for 0.11 because those are the compatible offline sources available. The CSV,
CLI, DreamCoder, and optional Gurobi surfaces are excluded.

On the README repeated-triple example, the core learned one exact normalized
library:

```text
λx1 -> x1 : x1 : x1 : []
```

It rewrote the four examples through that library and reduced source `AstSize`
from 29 to 22. The README says 29 to 23 even though its displayed result has
source cost 22. That numeric mismatch is recorded as false conformance rather
than hidden; structural conformance passes.

The complete offline build and execution passed process-tree accounting with
nine observed processes. The source-faithful independent-control count is now
`2/4`; official binary/artifact execution remains `0/4`.

**Verdict:** `FOUNDRY_V6_NOT_READY`
