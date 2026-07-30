# Round AW integration attempt — invalid measurement caught

**Verdict: INVALID AS A MILESTONE MEASUREMENT. No inventor result.**

The AW1 history firewall, AW2 real-artifact corpus, and AW3 native-Zag
toolforge were connected and executed. Every policy appeared to receive 4/4
accepted claims. This is not a positive: an immediate reduction audit found
that AW2 accepts only a bare unsigned integer per task. The source scanner
emitted the coincident sequence `3, 0, 1, 1`, which happened to equal the four
task answers even though it did not perform CSV-width parsing, sleep-in-loop
analysis, or missing-argument branch analysis. Fixed, broad, random, replay,
no-memory, and no-repair policies all tied.

This is an evaluator-design failure, not candidate capability. A numeric scalar
does not identify the measured property. The apparent 4/4 cannot show learning,
tool use, transfer, or even causal task completion.

## Durable correction

The revised corpus must require a precommitted **typed claim plus witness**:

- source structure: declaration offsets or line witnesses;
- CSV integrity: malformed row indices and observed field counts;
- performance proxy: sleep offsets plus enclosing-loop witnesses;
- behavior property: `MissingArg` branch offsets.

The evaluator must verify the witness against the sealed payload, reject a
wrong task kind even when its number matches, and retain the same equal-budget
and answer-free boundaries. The candidate must generate tools that produce that
typed witness; the current single source-scanner family should fail those other
tasks honestly.
