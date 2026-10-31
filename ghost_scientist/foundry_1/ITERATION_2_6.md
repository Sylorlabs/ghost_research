# Foundry-2.6 Enumo source-closure audit

The second-control path now has a complete pinned source checkout, but not an
executable result.

All 18 files in Enumo's library closure match upstream Git blobs at
`uwplse/ruler@7ed456de94df26fdddc0c15417a987d101dc57b5`, including the exact
manifest, MIT license, core DSL, workload generator, rule representation,
ruleset minimization, scheduler, language interface, and bit-vector domain.

The exact manifest declares 21 direct dependency series. The offline crate
cache contains compatible versions for 10. Eleven are missing:

- Clap 3.0;
- env_logger 0.7;
- num 0.3;
- num-bigint 0.3;
- ordered-float 2;
- float-cmp 0.8;
- Itertools 0.9;
- Z3 0.12;
- symbolic_expressions 5;
- smallstr 0.3; and
- Egg 0.9.

The machine has system `libz3`, but not the required Rust Z3 crate. The first
offline Cargo resolution failure is the missing Clap package; resolving that
alone would only reveal the rest of the missing closure.

No Enumo algorithm ran, no conformance output was observed, and the external
control count remains `1/4`. Replacing Egg or Z3 with Ghost-authored behavior
would invalidate the control.

The next action is a comparable Babble/ISAMORE source-closure audit, then choose
the smaller legitimate upstream recovery path for control two.

**Verdict:** `FOUNDRY_V6_NOT_READY`
