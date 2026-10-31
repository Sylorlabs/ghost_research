# Foundry readiness iteration 5.10

Phase 120 mounts five locked graphviz-family packages from two pinned official
repository commits. The second is required because the root `0.8.0` revision
still carries `dot-structures 0.1.1`, while the lock naturally resolves
`0.1.2`. Sixteen build-source records match their declared revisions, and
every manifest has the locked package name and version.

No release tag was resolvable, so this is classified as pinned official
repository source—not a release-tag or crates.io archive reproduction. The
identical metered resolver advances from `graphviz-rust` to `indicatif` without
reaching compilation.

P1 remains `3/4`, readiness remains `5/6`, production integration remains
`6/10`, and validation-v6 remains sealed.
