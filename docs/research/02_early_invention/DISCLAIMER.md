# Disclaimer — Thread 02: Early Geometry/Alien Invention Engines

**These documents describe an approach that was abandoned.** The geometry-based
invention engines (engine_genesis, alien_breakthrough, phase_lattice) did not
produce verifiable programs and were superseded by DomainSpec (Thread 04).

## What was true when written

- `engine_genesis.zig` and the derived engines are real, buildable Zig programs
- They produce real numeric output (marks, deltas, chamber states)
- The novelty-pressure probe correctly identified a failure mode in closure-only invention loops

## What was later revised or abandoned

- **Geometry marks are not programs.** The "alien breakthrough" output is a hex mark / delta pair.
  It is not a discovered algorithm and cannot be compiled to a working function.
- **"Outside-envelope geometry" framing** was narrative invented by an earlier agent.
  The actual output was chamber pressure changes and integer marks.
- **The approach cannot produce verifiable results.** DomainSpec (Thread 04) replaced it with
  a comptime-generic engine whose output is actual Zig-evaluable programs, Z3-checkable
  for bijectivity and PractRand-testable for statistical quality.
- **`alien_invention_experiments_2026_05_22.md`** (2026-05-22) revisited this approach
  after Thread 05 was already underway — those experiments confirmed the approach
  still does not produce verifiable programs.

## Safe to use these docs for

Understanding why the geometry approach was abandoned and what the novelty-pressure
insight contributed to later work.

## Do not use these docs for

Any quantitative comparison with meta-engine results. The fitness metrics are
incommensurable (chamber pressure vs composite mixer quality).
