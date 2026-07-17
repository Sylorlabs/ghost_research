# Round U / U1 — Morphogenic Topology

**Verdict: VALID NEGATIVE.** A development-selected organism genuinely varied
its cell count, connectivity, local response bits, update timing, delayed state,
state width, output boundary, and mutation stride. On twelve fresh worlds it
scored 1,110 errors / 2,304 events across raw and permuted/re-encoded channels.
That beat random growth (1,154), fixed topology (1,192), and replay (1,192), but
lost to an equal-size static body (1,098) and to the deliberately human-supplied
world emulator (0). It also did not preserve its behavior across the two raw
encodings. This is not accepted as representation birth.

## Question and construction

Can a tiny executable organism grow its own useful body without inheriting
Round T's shared response surface?

`sparse_poly_discovery/morphogenic_topology_round_u.zig` separates the two
generative mechanisms:

- worlds are deterministic arithmetic byte recurrences using addition,
  multiplication, rotation, and XOR;
- learners are variable directed collections of delayed two-input Boolean
  cells with independently changing update phases and internal state;
- a second observation condition applies a bijective affine re-encoding and
  bit-channel permutation;
- eight development worlds choose the organism; twelve worlds created from
  disjoint indices are evaluated only after its body freezes.

The learner never receives the world recurrence, world seed, held-out outputs,
task-family label, English request, named feature, or post-freeze mutation.
This is local original harness code and imports only Zig's standard library.

## Installed biases — explicitly irreducible in this experiment

This experiment still installs machinery. It does not claim creation from
nothing. The supplied biases are:

1. binary cells and byte-valued observation/action boundaries;
2. two-input, four-bit local response tables;
3. directed wiring, sequential scheduling, four update phases, and one-step
   delayed state;
4. finite body bounds of 2–20 cells and one selected output cell;
5. deterministic candidate enumeration and development-error selection;
6. fixed proposal budget, equality comparison, error counting, hashing, file
   storage, and evaluator partitioning;
7. a human-chosen objective: predict the high bit of the next raw world state.

These are substrate and protocol biases. The key T1 bias is absent: the world
does not use learner cells, learner wiring, a learner LUT, or a shared response
surface. Nevertheless, the cell grammar remains human-installed and is a major
remaining limitation.

## Equal-cost controls and result

All reported arms are charged the same 768-proposal envelope and evaluated on
the same 1,152 events per encoding. The task-aligned arm is intentionally an
unfair *structural-ceiling control*: its world emulator was supplied by the
human. U1's stated acceptance gate requires growth to beat it, so its zero-error
result prevents an inflated claim.

| Arm | Raw errors | Re-encoded errors | Total |
|---|---:|---:|---:|
| grown six-cell body | 587 | 523 | **1,110** |
| random growth | 618 | 536 | 1,154 |
| fixed four-cell topology | 596 | 596 | 1,192 |
| equal-size static body | 542 | 556 | **1,098** |
| replay memory | 596 | 596 | 1,192 |
| task-aligned supplied emulator | 0 | 0 | **0** |

The grown body is not merely larger than the fixed control: capability and
evaluation cost are recorded separately from cell count. But growth failed the
more important comparison. Development selection did not create a body more
useful than an independently sampled body of the same size, and the encoding
change altered which arm looked better. The small advantage over fixed/random
controls is therefore insufficient evidence of a reusable causal
representation.

## Freeze, lineage, and anti-memorization discipline

Candidates exist only during development scratch search. The selected body's
exact cells, width, output, timing, and mutation stride freeze before fresh
world indices are evaluated. No candidate is edited from held-out results.
Replay has no matching world or trajectory after the partition and can emit
only its development majority behavior. The CSV stores aggregate errors,
structural dimensions, cost, and freeze state—not test sequences or answers.

The result earns no durable verified Rune. Under the Round U lifecycle it is a
scratch candidate followed by a rollback-quality negative: it did not pass
equal-size, supplied-topology, and encoding-transfer gates.

## Reproduction

```sh
zig build-exe sparse_poly_discovery/morphogenic_topology_round_u.zig \
  --cache-dir /tmp/zig-u1-cache --global-cache-dir /tmp/zig-u1-global \
  -femit-bin=/tmp/morphogenic_u1
/tmp/morphogenic_u1 selftest
/tmp/morphogenic_u1 results/morphogenic_topology_round_u.csv
```

Fresh-build output:

```text
SELFTEST PASS: morphogenic bodies replay deterministically; independent
arithmetic worlds, fresh freeze, raw re-encoding, equal-cost controls, and
conservative verdict hold
```

Two independent output writes are byte-identical. The self-test also scans the
released ledger for prohibited answer/model/feature markers and requires the
freeze record plus the negative verdict.

## What was learned

Removing the shared T1 topology was necessary but not sufficient. Unconstrained
structural variation plus selection found a somewhat useful body, yet the gain
was explained by ordinary finite candidate selection and did not survive the
equal-size static or task-aligned controls. The next architecture cannot equate
"topology changed" with "representation grew." A body must earn persistent
structure because that structure predicts interventions and transfers under
raw recodings—not because one development partition selected it.

U1 therefore does not release U4. This is an experimental negative, not an
infrastructure failure and not a claim that representation birth is impossible.
