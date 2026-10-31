# Foundry-3.3 fourth-control acquisition route

The fourth-control route is now evidence-backed and frozen, but it is not
locally executable.

ISAMORE is the only remaining pinned public implementation in the control
intake; no public EggMind repository has been located. Six top-level ISAMORE
records at revision `5f51b1d432a61d8be01eac0e29445881d80395e2`
match their Git blobs. They establish a genuinely different published task:
discovering reusable custom instructions from RVSDG programs and profile data,
then applying hardware-aware selection.

The closure audit found:

- `14/30` registry dependency series compatible in the local Cargo cache;
- all four declared submodules absent: Babble, Enumo, JLM, and profiler;
- all four required workspace paths absent;
- the pinned `nightly-2024-12-25` toolchain absent;
- `clang-18` present, but `jlm-opt` absent;
- the published template and preprocessing configuration present, but their
  referenced RVSDG and profile inputs absent;
- no published `Cargo.lock` at the pinned revision.

This phase selects an acquisition route; it is not conformance and does not
raise the control count. A legitimate reduced build must retain ISAMORE's
top-level reusable-instruction identification and hardware-aware selection. A
standalone rerun of its Babble or Enumo submodule would duplicate existing
controls.

Source-faithful independent-control conformance remains `3/4`.

**Verdict:** `FOUNDRY_V6_NOT_READY`
