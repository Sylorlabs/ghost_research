# Round AV — real local-code analyzer repair trial

**Verdict: OPERATIONAL BUT NOT A LEARNED-ADVANTAGE POSITIVE.**

This is the first post-AU test using actual tracked repository source files,
not generated numeric fixtures. The candidate writes **native Zag** analyzers
into scratch and a Bubblewrap worker runs them against read-only copies of two
real Zig sources. The evaluator keeps the expected public-function count outside
the worker mount. The candidate starts with a raw-token counter, receives only a
mismatch outcome on a training artifact, records the comment hypothesis, writes
a repaired comment-stripping analyzer, then transfers it to a held-out source.

The repaired candidate succeeds operationally. But an equal-capability fixed
comment-stripping scanner also succeeds. Therefore this test demonstrates actual
source-reading, sandboxed program execution, failure/repair, and held-out
transfer **only**; it does not demonstrate that the candidate learned or
outperformed a strong fixed approach.

## Concrete boundaries

- Real inputs are frozen copies of `core/src/adapters/invention_engine.zig` and
  `core/src/adapters/domain_agi_subsystem_synthesis.zig`, recorded by SHA-256.
- The worker receives only its candidate script and `/work/corpus`; it has no
  network, evaluator mount, score channel, hidden expected count, or writable
  source artifact.
- The evaluator checks candidate source for the expected numeric answer literal.
- Bubblewrap is a runtime boundary for this test, not a proof against every
  hostile native-code escape. Candidate source is native Zag and the analyzer
  family remains supplied, so this is not open-ended program invention.

## Reproduce

```bash
scripts/run_round_av_zag.sh results/real_local_inventor_trial_round_av_zag.csv
scripts/run_round_av_zag.sh /tmp/round-av-zag-replay.csv
cmp results/real_local_inventor_trial_round_av_zag.csv /tmp/round-av-zag-replay.csv
```

## What this changes

The plumbing now touches actual repository source and executes a candidate-made
scratch program in a restricted worker. The honest next gate is not another
one-file trick: it needs multiple unrelated real tasks whose repaired tools beat
strong fixed/broad/replay baselines under the same budget and then survive an
independent source/receipt audit.
