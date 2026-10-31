# Foundry readiness iteration 5.14

Phase 124 authenticates `array-init 2.1.0`, `ordered-float 5.1.0`, and
`cmov 0.4.6` across thirteen upstream Git blobs. `ordered-float` and `cmov`
use exact release tags; `array-init` uses its exact official publish commit.

The exact published `kiddo 5.2.4` root remains absent, so the identical
offline resolver still stops at `kiddo`. The available upstream history
surface retains a `5.2.1` manifest and was not rewritten.

P1 remains `3/4`, readiness remains `5/6`, production integration remains
`6/10`, and validation-v6 remains sealed. The next phase must obtain the exact
published `kiddo 5.2.4` source surface or produce stronger evidence that it is
not recoverable through the available authenticated channels.
