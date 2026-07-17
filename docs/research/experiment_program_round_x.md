# Round X / X1 — Self-Mutating Experiment Program

**Verdict: VALID NEGATIVE.** The complete 24-byte experiment program is
mutation-reachable and its four experiment-mutator bytes change descendant
procedure distributions, but development did not increase downstream
viability: the selected program stayed at 96/192 development episodes, exactly
the birth program's score. After freezing, it achieved 672/1,344 viable
episodes across evaluator-private bodies. A fixed raw-byte random procedure
achieved 1,288/1,344 at the same accounting cost. The grown program therefore
fails the Round X promotion gate. This is an experimental negative, not an
agent failure.

The result is also a warning about the substrate. The VM supplies a finite menu
of arithmetic effects for centering, scaling, folding and comparison. A random
byte string can land on a very effective composition of those installed
effects. That is fixed decoder/protocol bias, not representation birth.

## Construction

`sparse_poly_discovery/experiment_program_round_x.zig` represents the entire
procedure as 24 organism-owned bytes. The bytes control:

- probe waveform, amplitude and repeat count;
- port sequence, stride, start phase and stop budget;
- temporal window origin and span;
- response centering, scaling, rotation and compression;
- response comparison, polarity, tie handling and accumulation;
- four sequence salts;
- mutation target, step, rate and descendant salt.

The procedure receives anonymous integer histories. It never receives organ
meaning, body maps, causal classes, per-port correctness, hidden seeds, task
labels, prose, tokens, embeddings or a grounding score. During development,
selection sees only body-level downstream resource viability aggregated across
episodes. Rune memory begins empty. No transcript, address, answer or evaluator
state is inherited.

Development evaluates 1,536 child proposals over 64 generations in matched,
noisy and delayed birth bodies. Neutral tie-breaking permits lineage movement,
so the final byte digest differs from the birth genome, but its viability does
not improve. The exact program then freezes before 24 unseen body identities
per condition are constructed.

## Installed VM effects and bias

No executable substrate is prior-free. This harness fixes:

- 24 bytes, eight anonymous slots, eight raw history steps and bounded integer
  arithmetic;
- byte addressing, buffers, scheduling and raw transport;
- four waveform effects and finite amplitude/repetition effects;
- four centering effects, four scaling effects, rotation and folding effects;
- four comparison effects, polarity and deterministic tie handling;
- byte mutation, bounded resource accounting and evaluator-private world
  dynamics;
- selection by aggregate downstream resource persistence.

These are low-level executable effects rather than named senses or tasks, but
some are already useful experiment ingredients. In particular, installed
centering/scaling/comparison opcodes can compose into a strong response decoder.
Consequently a win inside this VM would still require a decoder-bias audit. The
actual grown arm does not reach that question because it loses to random.

## Frozen results

| Equal-cost arm | Viable | Episodes |
|---|---:|---:|
| raw-byte random procedure | **1,288** | 1,344 |
| grown experiment program | **672** | 1,344 |
| fixed birth procedure | 672 | 1,344 |
| W1-like human protocol control | 672 | 1,344 |
| transcript/address replay | 360 | 1,344 |
| equal-size independent static procedure | 0 | 1,344 |

The grown program records 96/192 viability in every held-out condition:
matched, port permutation, affine raw recoding, temporal delay, noise,
missing/new organs and actuator remapping. Uniform half-success is not a robust
grounding signature; it is a plateau. The fixed random program records 192/192
in five conditions, 160/192 under noise and 168/192 with missing/new organs.

All arms receive the same 1,536-proposal development accounting envelope and
the same 24-byte extent. Giving controls equal accounting does not claim that
each control uses the proposals intelligently; it prevents the grown arm from
winning through uncharged search or bloat.

## Mutation and hostile checks

The canonical run passes ten checks:

1. all 24 encoded byte effects are independently mutation-reachable;
2. mutation-index changes alter descendant distributions;
3. mutation-step changes alter descendant distributions;
4. mutation-rate changes alter descendant distributions;
5. descendant-salt changes alter descendant distributions;
6. the procedure freezes by value before private bodies exist;
7. a post-freeze edit changes the mutable copy but not the frozen digest;
8. every arm has an invariant 24-byte extent and equal proposal charge;
9. post-freeze recoding/permutation replay is deterministic;
10. hidden maps, per-port grounding scores and evaluator state have no policy
    interface and transcript memory is absent from the genome.

The source also includes explicit random, replay, equal-size static and W1
human-protocol controls. Passing these checks validates the measurement and the
negative verdict; it does not establish intelligence.

## Meaning

Round W asked the organism to invent its experiment machinery. X1 made that
machinery mutable, including the machinery that mutates future procedures. That
was necessary but insufficient. Development wandered neutrally and did not
discover the byte composition that a nonselected random control happened to
occupy.

The strongest local conclusion is:

> Mutation-complete experiment bytes do not by themselves create an effective
> experiment-selection process. The current aggregate viability landscape has
> a plateau, while the VM's installed decoder effects contain high-performing
> accidental compositions.

X1 therefore cannot release X4. A future angle must change the developmental
credit path or the substrate's compositional locality without revealing body
maps or grounding accuracy.

## Reproduction

```sh
zig build-exe sparse_poly_discovery/experiment_program_round_x.zig \
  --cache-dir /tmp/zig-x1-cache --global-cache-dir /tmp/zig-x1-global \
  -femit-bin=/tmp/experiment_program_x1
/tmp/experiment_program_x1 selftest
/tmp/experiment_program_x1 results/experiment_program_round_x.csv
```

Fresh output:

```text
SELFTEST PASS: 24/24 byte effects reachable; 4/4 mutator bytes alter descendant
distributions; development 96/192 vs birth 96/192; frozen grown 672/1344,
random 1288/1344, equal-static 0/1344, W1 control 672/1344; attacks 10/10;
valid-negative verdict locked
```

Canonical CSV SHA-256:

```text
ad963f2db5690dfb2a160907f8d1d021211a7a175b0714f5e8095fac293638fc
```
