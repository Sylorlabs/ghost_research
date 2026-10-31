# Ghost Scientist Terra evaluator — sealed real-artifact vertical slice

**Verdict: BOUNDED POSITIVE for answer-free program construction, causal
promotion, heldout reuse, and an equal-charged comparison. This is not a
general autonomous scientist, unrestricted grammar invention, semantic code
understanding, or hostile-process isolation result.**

Terra integrates Luna's exported generic `PROGRAM_V1` constructor directly.
The candidate-side constructor receives only an opaque ID, `develop` or
`holdout`, the exact payload hash, remaining build/action/probe counters, and
read-only payload bytes. It does not receive an original path, task/family/kind,
expected witness, answer, score, progress, evaluator state, or compatibility
map.

## Real battery

The evaluator privately owns nine exact Git-tracked payloads: three development
and six heldout. Four pre-existing AX properties use declaration positions,
CSV record widths, a sleep-in-loop span, and a `MissingArg` line span. The new
property is the byte motif `try` outside `//` line comments, developed on
`boundary_crossing/verified_generation.zig` and reused on four distinct
heldout `boundary_crossing` files.

The new property is deliberately named **active_try_bytes**, not a Zig `try`
token. The generic byte scanner has no lexer word-boundary primitive, so any
non-comment `try` byte substring is evidence. The evaluator and constructor
agree on that narrow byte-level property; no semantic code claim follows.

The evaluator-private artifact map is:

| Phase | Hidden evaluator property | Tracked payload |
|---|---|---|
| develop | declaration positions | `07_agent_loop/src/perception.zig` |
| develop | CSV record-width deviations | `04_verified_synthesis/results/program_synthesis_inventor.csv` |
| develop | active `try` bytes | `boundary_crossing/verified_generation.zig` |
| holdout | sleep-in-loop spans | `12_adversarial_loop/src/immune_loop.zig` |
| holdout | `MissingArg` line spans | `04_verified_synthesis/src/verify_cli.zig` |
| holdout | active `try` bytes | `boundary_crossing/parametric_guide.zig` |
| holdout | active `try` bytes | `boundary_crossing/code_semantics.zig` |
| holdout | active `try` bytes | `boundary_crossing/grounded_language.zig` |
| holdout | active `try` bytes | `boundary_crossing/recursive_loop.zig` |

This map belongs to the evaluator report and must not be mounted into a
candidate process.

## Protocol and evidence

Candidate input is:

```text
GHOST_CANDIDATE_V1 <opaque_id> <develop|holdout> <payload_hash>
                   <actions_left> <builds_left> <probes_left>
```

Candidate claims are:

```text
GHOST_WITNESS_V1 <opaque_id> <tool_hash> <program_hash> <payload_hash>
                 <schema_hash> <builds> <actions> <probes>
                 <summary> <canonical_evidence>
```

The only schemas are generic result shapes: `positions_v1`,
`record_width_v1`, and `offset_spans_v1`. The evaluator reconstructs the
task-specific canonical witness from sealed bytes. It rejects wrong schema,
tool, program, payload, summary, budget, or witness bindings.

The result ledger has a row for every charged constructor reduction. Accepted
typed witnesses include canonical evidence as hex, so commas and spans remain
machine-readable without corrupting the CSV columns. All nine tasks also pass
a relevant mutation, an irrelevant mutation, and stale-payload-hash rejection.
Ten answer/task/score/path/network-shaped requests reject.

## Causal construction

The complete 2,331-program Luna sequence is derived only from exact development
payload bytes and precommitted at hash `fe0339d4c46780e9` before reduction.
The evaluator's opaque development receipts first accept program 101:

```text
PROGRAM_V1 scan_not_after_in_line 747279 2f2f
program_hash=1bee4f5954df10e4
tool_hash=d09e1e124efc1a7d
```

The program is then promoted only after evaluator-owned relevant and irrelevant
mutation checks. It is reused on four distinct heldout files with no new
build. Heldout proposals are complete before scoring; no incremental heldout
accept/reject receipt reaches the candidate.

This is bounded construction from a human-supplied low-level operation
alphabet. It closes AX's fixed-three-form limitation only for this measured new
composition; it does not establish unrestricted tool-grammar invention.

## Scores and budgets

Every arm is charged exactly 2,048 builds, 2,048 actions, and 2,048 probes per
item, including explicit padding. Active work is reported separately.

| Arm | Total | Develop | Heldout | Active builds/actions/probes | Interpretation |
|---|---:|---:|---:|---:|---|
| complete AX fixed portfolio | 4/9 | 2/3 | 2/6 | 27 / 36 / 36 | four canonical programs, three supplied tool forms |
| broad fixed AX | 4/9 | 2/3 | 2/6 | 27 / 36 / 36 | same complete supplied coverage, alternate order |
| random AX member | 2/9 | 1/3 | 1/6 | 9 / 9 / 9 | weak fixed-choice control |
| matched random constructor | 4/9 | 2/3 | 2/6 | 128 / 137 / 137 | frozen shuffled Luna sequence, 101 reductions, no promotion |
| replay | 1/9 | 1/3 | 0/6 | 9 / 9 / 9 | supplied-program replay control |
| no memory | 5/9 | 3/3 | 2/6 | 128 / 139 / 139 | performs identical development construction, then discards it |
| no probe | 4/9 | 2/3 | 2/6 | 27 / 36 / 36 | precommits the same candidates but receives no development promotion receipt |
| adaptive portfolio expansion | **9/9** | **3/3** | **6/6** | 128 / 145 / 145 | inherits AX and adds the causally earned program |

The adaptive arm therefore beats the complete fixed AX portfolio on heldout
acceptance, **6/6 versus 2/6**, under identical charged budgets. The exact
interpretation is portfolio expansion plus bounded program construction and
reuse. It is not evidence that the candidate autonomously routes one exclusive
tool per arbitrary artifact: the inherited AX portfolio remains available.

## Reproduction

```sh
zig build-exe sparse_poly_discovery/ghost_scientist_evaluator_terra.zig \
  -O ReleaseSafe -femit-bin=/tmp/ghost-scientist-terra \
  --cache-dir /tmp/zig-gs-terra-cache \
  --global-cache-dir /tmp/zig-gs-terra-global
/tmp/ghost-scientist-terra selftest
/tmp/ghost-scientist-terra run results/ghost_scientist_evaluator_terra.csv
```

Five fresh selftest processes passed. Two full ledgers generated inside every
selftest were byte-identical. The published result ledger SHA-256 was
`71d39545dea0d789f5f2f4a520a6b69d7b333c21e19db1f8cd052fee37e6dbc0`
at verification time.

## Remaining production boundary

This is a same-process typed protocol integration. It imports only Luna's
exported candidate API, but Zig module privacy is not a hostile OS boundary.
AP demonstrated a bounded Bubblewrap/seccomp/process wall separately; that wall
has not yet wrapped this exact constructor/evaluator pair. Timing, compiler,
kernel, hardware, same-address-space inspection, and the human-supplied generic
operation alphabet remain trusted or residual surfaces.
