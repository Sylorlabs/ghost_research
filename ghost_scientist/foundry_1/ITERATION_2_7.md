# Foundry-2.7 control-two route selection

The next public-control route is now selected by measured acquisition cost.
This is not yet a second control result.

Babble's `popl23` branch resolves to commit
`09ff03fd485a3e24178c1d706a5944a230123ba1`. Its exact manifest and lockfile are
local, and the lockfile pins Babble's required Egg fork to
`caf623cad25cacba83193464dcf0d3dd4161ba7a`.

After excluding the optional Gurobi dependency, Babble has 21 required direct
dependencies. Thirteen compatible series are locally cached. Eight are absent:

- the local `babble-macros` workspace;
- the pinned Egg fork;
- CSV;
- Clap 3.2;
- Itertools 0.10;
- ordered-float 2;
- env_logger 0.9; and
- RON 0.7.

This is smaller than Enumo's eleven-package direct gap. ISAMORE is larger still:
it requires four path workspaces, a Git Egg fork, nightly Rust
`2024-12-25`, and JLM with LLVM/Clang.

Babble is therefore the evidence-backed recovery route for control two. Its
complete source, macro workspace, Egg fork, and eight missing packages must be
recovered before a conformance protocol is frozen. Selection does not change
the control count, which remains `1/4`.

**Verdict:** `FOUNDRY_V6_NOT_READY`
