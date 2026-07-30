# Ghost Scientist / Luna — generic analyzer construction and reuse

**Verdict: bounded constructor positive, not a general-scientist result and
not a campaign-cost win over random.**

This standalone Zig experiment closes one narrow mechanical gap left by Round
AX: a candidate can enumerate and construct a new byte analyzer without
receiving a task kind, family label, natural-language contract, expected
witness, score, or an AX grammar-compatibility map. The earned analyzer
transfers to a distinct tracked source file with no new build.

The experiment does **not** establish primitive invention, semantic
understanding, hostile-process isolation, a win over random construction, or a
production research protocol. Those stronger claims remain integration gates.

## Why this design

The implementation was derived after inspecting the actual Round F/G/H and
AT–AX artifacts, especially:

- F2–F5: a structural prior could transfer and reduce search only after the
  needed behavior was representable;
- G3/H1: static behavioural descriptors did not learn held-out family routing;
- G4/H3/H4: directed-partition proposal worked inside a supplied grammar, but
  the admission probe encoded a singleton-shaped prior;
- AT2/AU2: scratch construction and opaque repair receipts were mechanics
  only;
- AV: a repaired real-source scanner tied the fixed scanner;
- AW: a scalar claim accidentally matched unrelated task answers;
- AX1/AX4: typed witnesses repaired that bug, but AX still supplied three tool
  forms and their compatibility.

The resulting constructor therefore starts below those supplied forms. Its
`PROGRAM_V1` grammar contains generic operations only:

- scan observed byte phrases;
- exclude matches after another byte phrase on the same line;
- split records and compare delimiter widths;
- emit containing line spans; and
- emit containing brace-region spans.

There is no `source`, `csv`, `control_flow`, declaration, sleep, missing-arg,
or catch-unreachable alternative in the candidate grammar.

## Candidate boundary

The public candidate input is:

```text
opaque_id
develop | holdout
payload_hash
remaining actions/builds/probes
read-only payload bytes
optional prior opaque accept/reject receipt
```

`enumeratePrograms` mines lexical atoms and adjacent phrases from the payload
itself. The complete program order is determined before evaluator reduction.
Every evaluator call is charged as one action and one probe, every new program
as one build, and all three caps are enforced. A naturally occurring commented
occurrence in the exact tracked development artifact makes comment filtering
load-bearing; no generated target-shaped mutation is used in the scored path.

The candidate's repaired program was:

```text
PROGRAM_V1 scan_not_after_in_line 747279 2f2f
```

The hex operands decode to a byte motif mined from a lexical atom and the
line-comment delimiter. Execution uses raw substring matching, not word
boundaries. The candidate never receives the motif from the evaluator.

The shared typed output is:

```text
GHOST_WITNESS_V1 <opaque_id> <tool_hash> <program_hash> <payload_hash>
                 <schema_hash> <builds> <actions> <probes>
                 <summary> <canonical_evidence>
```

Schema hashes describe only generic result shapes: `positions_v1`,
`record_width_v1`, and `offset_spans_v1`.

## Fresh result

Development artifact:
`boundary_crossing/verified_generation.zig`.

Held-out artifact:
`boundary_crossing/parametric_guide.zig`.

Both are distinct tracked files. The evaluator privately checks non-comment
`try` byte-motif offsets. It does not claim lexical or semantic classification.

| Arm / audit | Accepted | Builds | Actions | Probes | Interpretation |
|---|---:|---:|---:|---:|---|
| Exact tracked constructor | yes | 101 | 101 | 101 | Natural commented and active uses make the comment-safe program load-bearing |
| Earned-program held-out replay | yes | **0** | **1** | **1** | Distinct tracked bytes, no rebuild |
| Fresh/no-memory first-reaching reduction | yes | 884 | 884 | 884 | Evaluator-side cost of a precommitted deterministic sequence |
| Random precommitted sequence, same 101 cap | no | 101 | 101 | 101 | Frozen random order does not reach the program |
| Fixed AX source analyzer | no | 1 | 1 | 1 | Supplied declaration scanner does not cover the new property |
| Complete four-program AX portfolio | no | 4 | 4 | 4 | The inherited three-form portfolio lacks this analyzer |

The durable positive is **new held-out coverage relative to the supplied AX
portfolio and zero-build reuse relative to fresh reconstruction**. On this
pair the candidate's full develop-plus-transfer path costs 101 builds and 102
actions/probes, versus 884 of each for fresh held-out construction; the matched
101-attempt random sequence does not reach the program. This is still a
single-property pair, not a population estimate.

Development accept/reject receipts still provide one bit of evaluator
feedback. The constructor is therefore bounded verifier-guided synthesis, not
zero-feedback invention. Heldout receives no receipt stream.

The no-memory and random rows are evaluator-side first-reaching reductions over
fully deterministic program orders. They are not interactive held-out
candidates receiving a stream of correctness receipts. The actual held-out
candidate submits the already-earned program once.

## Reproduce

From the repository root with Zig 0.14.1:

```bash
zig build-exe sparse_poly_discovery/ghost_scientist_constructor_luna.zig \
  -O ReleaseSafe -femit-bin=/tmp/ghost_scientist_constructor_luna
/tmp/ghost_scientist_constructor_luna selftest
/tmp/ghost_scientist_constructor_luna run \
  results/ghost_scientist_constructor_luna.csv
```

Fresh self-test receipt:

```text
ghost_scientist_luna selftest PASS generic_program_grammar=true candidate_input_answer_free=true opaque_failure_receipts=true distinct_tracked_holdout=true earned_program_reuse=true full_ax_broad_control=true deterministic_replay=true
```

## Integration API

`ghost_scientist_constructor_luna.zig` exports `CandidateInput`, `Program`,
`Proposal`, `enumeratePrograms`, `executeProgram`, `makeProposal`,
`writeProgram`, `programHash`, `programSequenceHash`, `schemaHash`, and
`writeEnvelope`. A separate evaluator can import those symbols and reduce the
complete precommitted program sequence without importing a precomputed answer
or tool hash.

## Companion integrated result

The production-style coordinator in `scripts/run_ghost_scientist_protocol.sh`
fresh-builds this constructor and the separate Terra evaluator, runs both
self-tests, executes two byte-identical ledger replays, and publishes the
receipts. Its current nine-artifact result is:

| Policy | All | Develop | Heldout |
|---|---:|---:|---:|
| Complete fixed AX portfolio | 4/9 | 2/3 | 2/6 |
| Broad fixed AX order | 4/9 | 2/3 | 2/6 |
| Matched random constructor | 4/9 | 2/3 | 2/6 |
| No earned memory | 5/9 | 3/3 | 2/6 |
| No development probes | 4/9 | 2/3 | 2/6 |
| Adaptive inherited-plus-earned portfolio | **9/9** | **3/3** | **6/6** |

All arms receive identical charged caps. The audit reports four inherited
canonical programs backed by three supplied AX tool forms, plus exactly one
earned canonical program (`1bee4f5954df10e4`). It therefore reports four
candidate tool forms—not 27 inventions.

The integrated result connects receipt-guided construction to tracked
artifacts, beats the complete supplied portfolio on sealed heldout artifacts,
and reuses the earned program without heldout feedback. It still demonstrates
portfolio expansion, not autonomous selection of exactly one tool.

## Claim boundary

This is construction inside a human-supplied low-level interpreter. The
candidate did not invent byte scanning, tokenization, record splitting, brace
matching, typed witness schemas, or the evaluator. The private evaluator is in
the same standalone executable below an explicit source boundary; that is
inspectable protocol separation, not OS containment. The companion integrated
gate adds equal-budget recount, held-out no-feedback execution, mutation
attacks, and fresh replay, but it likewise does not prove hostile OS
containment.

The standalone pair also has only one earned program, so it does not prove
autonomous selection among several learned grammars. The integrated policy may
append this earned program to the inherited AX portfolio, but portfolio
expansion must not be renamed single-tool routing.
