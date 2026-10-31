# Foundry-1 iteration 5.2

The fourth-control route is no longer blocked by an unknown repository shape.
At pinned ISAMORE revision `5f51b1d...`, the top-level runtime source is local,
all four recursive gitlinks are authenticated, the immediately preceding
lockfile recovers the exact Egg revision, both estimator binaries reproduce
their upstream Git blobs from the published textproto models, and an exact
point-product RVSDG/profile pair is present.

That is acquisition, not a result. A metered offline `cargo metadata --locked`
resolves the local workspace. The unchanged offline build then stops before
compilation at the first absent locked registry package (`colored`). The pinned
nightly toolchain and native Coin-OR CBC library are also absent. Removing SMT
validation, LP extraction, or hardware-aware selection would change the
defining control, so no reduced substitute is promoted.

Readiness therefore remains `FOUNDRY_V6_NOT_READY`: `P1` is still `3/4`,
prerequisites remain `5/6`, production integration remains `6/10`, and
validation-v6 remains sealed and unexecuted.
