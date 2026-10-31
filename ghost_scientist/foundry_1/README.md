# Ghost Scientist Foundry-1

Foundry-1 is the trial-readiness implementation following the Foundry-0
novelty decision. It tests whether an answer-blind, LLM-free forge can build
typed reusable tools from a frozen byte/text substrate, transfer the exact
tool digests after a protocol freeze, and survive an independent evaluator.

It deliberately does not call this the v6 scientific trial. Its current
corpus consists of real Git-tracked local artifacts and evaluator-authored
structural contracts. That is useful calibration evidence, not the
independently sourced tensor/compiler workload required by Foundry-0.

## Phases

1. `phase1`: enumerate and select tools using two calibration artifacts per
   contract, then run a separate pre-freeze transfer pilot.
2. Freeze candidate, evaluator, protocol, corpus manifest, learned library,
   and phase-1 receipts by SHA-256.
3. `phase2`: verify the freeze and reuse the exact library on reserved local
   artifacts without mutation.
4. `phase3`: execute a failed-prerequisite remediation audit and resource-meter
   hostile test.
5. Independently reconstruct the authorization decision from the receipts.

Run the full clean sequence:

```bash
python3 -B ghost_scientist/foundry_1/run_calibration.py phase1
python3 -B ghost_scientist/foundry_1/freeze_foundry_1.py create
python3 -B ghost_scientist/foundry_1/run_calibration.py phase2
python3 -B ghost_scientist/foundry_1/run_remediation.py
python3 -B ghost_scientist/foundry_1/recompute_readiness.py
```

`FOUNDRY_V6_AUTHORIZED` is possible only when all Foundry-0 prerequisites are
true. Otherwise the correct verdict is `FOUNDRY_V6_NOT_READY`; post-freeze
local transfer is never allowed to override a missing prerequisite.

## Boundary

The forge constructs programs and typed contracts by bounded enumeration. It
does not receive task answers, expected offsets, source paths, evaluator code,
or held-out results. The byte/text primitives and output schemas are supplied.
The evaluator is implemented independently but the local Python calibration
runner is not an OS-containment proof.

The fixed portfolio contains the four known-good structural tools. Beating or
tying weaker controls cannot compensate for failing to beat this portfolio.

