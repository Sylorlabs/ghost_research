# Round V / V2 — Evolvable Senses and Actions

**Verdict: VALID NEGATIVE.** The evolved anonymous port boundary reached zero
errors on 1,536 fresh events with the birth encoding, but accumulated 3,777
errors / 9,216 events across six post-freeze boundary changes. It failed the
required transfer gate. This is evidence of a well-fitted port assignment, not
an organism inventing encoding-invariant senses or actions.

## Question and construction

Can a frozen organism recruit raw event channels and compose raw actuator slots
without receiving their meanings, then retain capability when those boundaries
are changed?

`sparse_poly_discovery/evolvable_ports_round_v.zig` constructs deterministic
byte-event worlds behind an evaluator boundary. Policy-visible state contains
only eight anonymous byte channels, four actuator indices, bounded mutable
state, and aggregate development error. It contains no channel names, semantic
type table, world recurrence, hidden seed, per-event held-out answer, prose,
embedding, or imported model.

Each organism boundary encodes two recruited channel indices, a grouping rule,
optional temporal integration, and a two-slot action composition. Exhaustive
development over 8,192 equal-cost candidates changes recruitment, grouping,
integration/ignoring, port replacement, and action composition. Eight
development worlds select one exact boundary. Its bytes freeze before twelve
disjoint-index worlds are exposed under seven conditions.

This is original local Zig harness code using only the standard library. Runes
ground the evidence-lineage concept and Sigil grounds scratch/commit/snapshot
discipline; neither Ghost solution shards nor a named invention menu are used.

## Results

| Post-freeze condition | Evolved errors | Events | Error rate |
|---|---:|---:|---:|
| matched birth encoding | **0** | 1,536 | **0.0%** |
| channel permutation | 786 | 1,536 | 51.2% |
| affine raw recoding | 127 | 1,536 | 8.3% |
| distractor insertion / channel shift | 781 | 1,536 | 50.8% |
| delayed effect | 740 | 1,536 | 48.2% |
| missing channel | **0** | 1,536 | **0.0%** |
| actuator remapping | 1,343 | 1,536 | 87.4% |

The zero missing-channel result is informative rather than contradictory: the
selected boundary recruited the two primitive raw inputs, not the evaluator's
redundant derived channel. Removing that derived channel therefore did not
matter. Permuting or shifting the recruited inputs did matter, showing that the
boundary attached to addresses rather than discovering a stable relation.

Affine recoding was a partial robustness result, but it was insufficient and
was not uniform across the other transformations. Actuator remapping was the
strongest failure. Once its two output slots were reassigned, the frozen action
composition had no grounded way to discover their new effects.

## Controls

Fixed ports, random ports, replay, an equal-size static boundary, and a
deliberately task-aligned supplied mapping all receive the same 8,192-proposal
accounting envelope and the same held-out events. The supplied arm is a private
evaluator ceiling and scores zero; its world access is never policy-visible.
Replay has no matching post-freeze trajectories. The evolved arm decisively
beats ordinary controls on the matched encoding but does not earn promotion,
because matched-only success is explicitly a negative under the Round V gate.

The equal-size static sample is intentionally poor in this deterministic run;
it is not used as the sole baseline. Fixed, random, replay, supplied, and six
boundary transformations together prevent that sample from inflating the
claim.

## Freeze and hostile checks

The harness freezes recruited ports, grouping, temporal flag, and composed
action slots before any held-out world. Six checks pass:

1. no semantic channel table is present in policy-visible data;
2. hidden answers are unavailable;
3. duplicate evidence earns no credit;
4. boundary size earns no score by itself;
5. post-freeze port edits are denied by construction;
6. two complete ledgers replay byte-identically.

The CSV records only aggregate event counts, errors, proposal costs, structural
sizes, freeze state, verdict, and attack outcomes. It does not retain held-out
event sequences or answers.

## Reproduction

```sh
zig build-exe sparse_poly_discovery/evolvable_ports_round_v.zig \
  --cache-dir /tmp/zig-v2-cache --global-cache-dir /tmp/zig-v2-global \
  -femit-bin=/tmp/evolvable_ports_v2
/tmp/evolvable_ports_v2 selftest
/tmp/evolvable_ports_v2 results/evolvable_ports_round_v.csv
```

Fresh-build output:

```text
SELFTEST PASS: anonymous port evolution, seven post-freeze conditions,
equal-cost controls, hostile checks, deterministic replay, and conservative
matched-only verdict hold
```

## Exact limitation and learned edge

This experiment mutates addresses and small ways of combining their values. It
does **not** allow an organism to create a new physical sensor, actuator, raw
transport effect, or arbitrary port interpreter. Its finite grouping grammar
is human-installed. Its fitness signal is also a human-chosen action-correctness
contract. Consequently, it neither proves intelligence nor proves that fully
evolvable boundaries are impossible.

The result isolates the next missing mechanism: address mutation is not sense
birth. A transferable sense needs an active grounding process that identifies
a port by the consequences of probing it, then reconstructs that identity after
permutation or replacement. Likewise, an action must be grounded by observed
effects rather than inherited actuator position. That process must itself be
encoded inside the mutable organism and frozen as an executable procedure—not
installed as a semantic lookup table.

V2 therefore does not release V4. It is an experimental negative, not an agent
failure or infrastructure block.
