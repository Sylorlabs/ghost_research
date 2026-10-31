# Foundry-2.3 faithful external-control attempt

The external-control requirement now has an executable, fail-closed protocol.
It does not yet have a reproduced control.

The protocol pins:

- `mlb2251/stitch` at
  `0ef5ec7f17091d22b8fa959fb5705e359d735a47`;
- the authors' `mlb2251/stitch_bindings` package at
  `8ba2c1c041ab384ccaa11e68226d5654474d161a`;
- the binding's declared dependency on Stitch revision `0ef5ec7`;
- the official CPython 3.12 manylinux wheel name, URL, and SHA-256;
- the official two-program `x x x` quickstart fixture;
- the exact expected arity-one abstraction and rewritten programs; and
- wall, CPU, RSS, natural-termination, and process-tree gates.

The protocol was hash-frozen before its runner executed. It refuses an
unverified installed package and refuses to treat a local reimplementation as
Stitch.

## Execution result

The pinned wheel was not present. The runner therefore stopped before import:

- artifact present: false;
- artifact hash verified: false;
- official backend executed: false;
- conformance executed: false;
- conformance passed: false; and
- controls reproduced: `0/4`.

This is an infrastructure failure, not a negative result for Stitch. The
process-tree arm terminated naturally and was fully charged, showing that the
harness and its failure classification work.

Shell access to PyPI, crates.io, and GitHub remains unavailable. The matching
official GitHub Actions Linux wheel existed, but its artifact expired on
January 6, 2026. Metadata and published expected output do not count as
reproduction.

## Next falsifiable step

Retain this frozen harness so the exact pinned wheel can be verified and run
without protocol edits if it becomes locally available. Meanwhile, seek a
required control whose official executable material is obtainable through the
connected source channel. Do not spend another iteration retrying the same
closed transport and do not replace a public control with a Ghost-authored
emulator.

**Verdict:** `FOUNDRY_V6_NOT_READY`
