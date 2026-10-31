# Foundry readiness iteration 5.15

Phase 125 freezes the exact `kiddo` root acquisition mismatch. The historical
lock authenticates `kiddo 5.2.4` and checksum
`07ab03cc75e18eb1eec59f4037e2e17ce9d13920f0013b0719dea613d9414e4e`.
The byte-pinned official release-adjacent commit authenticates its manifest,
but that manifest still declares `5.2.1`.

No exact `kiddo 5.2.4` archive or source exists in the local Cargo cache or
vendor tree. Bounded canonical-registry and direct-IP diagnostic probes both
failed from the shell environment. The `5.2.1` manifest was not rewritten,
and nearby repository history is not counted as published archive identity.

P1 remains `3/4`, readiness remains `5/6`, production integration remains
`6/10`, and validation-v6 remains sealed. Phase 126 continues exact
direct-dependency closure without disguising the unresolved root.
