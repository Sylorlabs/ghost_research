# Round AU / AU2 — bounded candidate analyzer loop

**Verdict: mechanics ready, not invention evidence.** This integrates three
small deterministic mechanics: opaque observation frames, competing hypothesis
forks, and an AT2-class in-memory scratch-program receipt/repair path. It is a
synthetic fixture. It does **not** demonstrate real-artifact discovery,
semantic understanding, arbitrary code execution, a hidden evaluator, process
isolation, learning, or an advantage over the controls.

## What runs

The candidate receives only the hash of a structural frame
`frame:v1|shape:2|delta:5|receipt:8ac1`; that frame contains no artifact text,
task label, answer, score, or evaluator feedback. It writes three forks:

1. `delta_is_reproducible`, falsified by a probe that does not reach 12.
2. `delta_is_noise`, falsified by a probe that reaches 12.
3. `alternate_structure`, explicitly unreached because it needs another
   observation.

Before execution it commits to `EXPECT 12`. Its initial tiny-DSL program has
`ADD five`, so the worker returns only `compile_bad_integer`. It then repairs
the source to `ADD 5`, reruns the same precommitted plan, and produces a sealed
claim token based on the receipt. The token is merely a deterministic record;
it is **not** a hidden evaluator verdict.

The program language is just `SET`, `ADD`, `ASSERT`, and `PRINT`, all in
memory. It has no file, network, process, environment, import, clock, score,
or answer interface.

## Required controls and guards

- no repair: retains the compile failure;
- fixed analyzer: succeeds too, so this fixture makes **no capability or
  superiority claim**;
- random analyzer: fails the test;
- replay: is byte-identical to the repaired route;
- post-hoc plan alteration (`EXPECT 13`) is rejected by the precommit hash.

## Reproduce

```bash
mkdir -p /tmp/zig-au2-cache /tmp/zig-au2-global
zig build-exe sparse_poly_discovery/candidate_analyzer_loop_round_au.zig \
  -femit-bin=/tmp/candidate-analyzer-au2 \
  --cache-dir /tmp/zig-au2-cache --global-cache-dir /tmp/zig-au2-global
/tmp/candidate-analyzer-au2 selftest
/tmp/candidate-analyzer-au2 run results/candidate_analyzer_loop_round_au.csv
cmp /tmp/au2-a.csv /tmp/au2-b.csv
```

Expected line:

```text
round_au2 selftest PASS opaque_observation=true competing_forks=3 precommitted_plan=true repair_after_compile_receipt=true controls=4 post_hoc_rejected=true deterministic_replay=true verdict=MECHANICS_ONLY
```
