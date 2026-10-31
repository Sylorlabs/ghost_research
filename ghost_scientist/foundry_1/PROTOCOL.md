# Foundry-1 autonomous tool-forge readiness protocol

**Status:** development and readiness protocol  
**Scientific v6 authority:** none unless every prerequisite passes

## Question

Can an answer-blind LLM-free forge construct typed parameterized tools from a
minimal byte/text substrate, retain their exact identities, and reuse them on
post-freeze real local artifacts under independent verification?

This is a necessary mechanism test. It is not the Foundry-0 total-cost tensor
compiler experiment.

## Candidate-visible surface

The proposal generator receives:

- calibration payload bytes;
- one typed output schema;
- a frozen primitive instruction set; and
- bounded proposal resources.

It does not receive:

- evaluator task-family labels;
- expected witnesses or numeric answers;
- source paths or provenance;
- phase-1 or phase-2 scores while proposing;
- strong fixed tools;
- post-freeze payload bytes before library freeze; or
- authorization thresholds.

The machine enumerates literal and syntax fragments from calibration bytes,
composes instruction sequences, emits their complete typed contracts, and
binds each program by SHA-256. Evaluator-owned feedback selects by mean witness
F1, then minimum program description length, then digest.

## Frozen substrate

The substrate includes immutable bytes, literal search, line-comment masking,
line spans, balanced enclosing braces, line splitting, delimiter width, and
typed witness emission. These are supplied semantics. A selected composition
is a derived tool, not a new primitive.

## Independent verifier

`independent_evaluator.py` does not import candidate code. It:

- requires an exact schema and instruction allowlist;
- reconstructs typed constraints from the body;
- reconstructs and checks the tool digest;
- executes the body from raw bytes;
- independently computes canonical task witnesses; and
- rejects body, digest, contract, answer-literal, and extra-field mutations.

## Corpus chronology

Phase 1 uses two training artifacts per structural contract plus one distinct
pre-freeze transfer artifact. Every payload has a unique digest.

The freeze authenticates code, protocol, manifest, phase-1 receipts, and
learned tools. Phase 2 must verify that freeze before mounting its four
reserved payloads. The same tool digests are reused without retraining.

All artifacts are real tracked local research files. They are not an external
production corpus, and their invocation counts are not independently sourced.

## Controls and accounting

The strong fixed portfolio contains a known correct tool for each structural
contract. The candidate must not receive credit for tying it. Discovery
receipts charge every proposal execution, rejected proposal, scanned byte,
process CPU time, wall time, and observed peak RSS.

The post-transfer remediation phase tests a direct-child resource meter on
success, failure, and timeout. That component is not a complete research meter
until it surrounds all candidate, control, verifier, compiler, and descendant
processes.

Foundry-0's Stitch, Babble/ISAMORE, Ruler/Enumo, EggMind, no-library, replay,
per-instance, and bounded-oracle arms remain mandatory for v6. Foundry-1 does
not relabel local approximations as those upstream systems.

## Mechanism gates

| ID | Gate |
|---|---|
| G01 | Four machine-selected typed tools exist. |
| G02 | All four phase-1 transfer witnesses match independently. |
| G03 | All four post-freeze phase-2 witnesses match independently. |
| G04 | Phase 2 names the exact frozen tool digest on every success. |
| G05 | Removing selected tools loses at least three non-empty witnesses. |
| G06 | Candidate beats, rather than ties, the strong fixed portfolio. |
| G07 | Independent hostile tool mutations are all rejected. |
| G08 | Every frozen digest remains unchanged through phase 2. |
| G09 | A remediation phase executes after the transfer verdict. |

Mechanism success cannot authorize v6 by itself.

## Authorization prerequisites

The final recomputation must fail closed on the Foundry-0 prerequisites:

- `P1`: faithful, conformance-tested external controls;
- `P2`: independently sourced heterogeneous compiler corpus and invocation
  trace;
- `P3`: complete process-tree resource accounting around every arm;
- `P4`: independent typed-tool parser, interpreter, and verifier;
- `P5`: native compiler IR deduplication;
- `P6`: unchanged prospective freeze and post-freeze runner.

Only six true prerequisites yield `FOUNDRY_V6_AUTHORIZED`. Any false value
yields `FOUNDRY_V6_NOT_READY`, followed by a preserved remediation record.

## Claim boundary

A successful local run may claim bounded autonomous construction and
post-freeze reuse of typed structural tools. It cannot claim:

- a v6 scientific result;
- a net total-cost advantage;
- external compiler transfer;
- faithful reproduction of prior-art controls;
- primitive invention;
- OS containment;
- general autonomous science; or
- superiority over the strong fixed portfolio unless G06 passes.

