# Foundry readiness iteration 5.18

Phase 128 authenticates the official `KardinalAI/coin_cbc` release commit
`0edcbcea3a238909f296c9d78dbb3fae0190c0e9` across seven source files. The
workspace manifests exactly declare the locked `coin_cbc 0.1.8` and
`coin_cbc_sys 0.1.2` packages.

Six records are byte-identical locally. The seventh is restored exactly in a
temporary build stage by removing one transport-added terminal line feed, then
verified against its upstream Git blob before compilation. With exact cached
`lazy_static 1.5.0` and `pkg-config 0.3.32` archives, the two Rust binding
packages pass a metered offline `cargo check`.

This is not a native CBC link or solver run. `libCbc`, the `cbc` executable,
and `nightly-2024-12-25` remain absent. The top-level resolver still stops at
missing `kiddo 5.2.4`; ISAMORE has not compiled or executed. Readiness remains
`5/6`, P1 remains `3/4`, integration remains `6/10`, and validation-v6 remains
sealed.
