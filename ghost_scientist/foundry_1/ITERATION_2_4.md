# Foundry-2.4 source-faithful Stitch control

The first required public control now has a real execution result.

This phase recovered and verified:

- all 12 Stitch algorithm files at
  `0ef5ec7f17091d22b8fa959fb5705e359d735a47`;
- all 15 Lambdas source files plus its manifest at
  `2c9bfd0317974ce82908eaf6d9af530eb4a9019d`; and
- the exact crates.io `rustc-hash` 1.1.0 source used by upstream.

Every Stitch and Lambdas file matches its upstream Git blob. No upstream
algorithm file was edited.

Unavailable build-only dependencies were replaced transparently:

- Clap is a defaults-only compatibility shim because this control calls the
  Rust API rather than parsing a CLI;
- Colorful is a display-only no-color shim; and
- cached Itertools 0.12.1 replaces upstream 0.10.x.

Those substitutions keep this from being called an official binary
reproduction. It is a source-faithful control with disclosed build shims.

## Result

The already-frozen official fixture passed every exact check:

- abstraction: `fn_0`;
- body: `(#0 #0 #0)`;
- arity: `1`;
- rewrites: exact for both programs;
- cost: `806 -> 604`;
- utility: `200`; and
- uses: `2`.

The build and execution ran inside the process-tree meter. It observed three
processes, natural termination, complete reaping, and no resource-limit
violation.

This counts as one source-faithful external control, not an official wheel
execution and not four controls.

**Verdict:** `FOUNDRY_V6_NOT_READY`
