# asi_attempt — a VSA predictive-coding agent (honest description)

A small hyperdimensional-computing (VSA) agent that learns a forward model of a
toy "battery cell" environment and — after the work in this directory — uses that
model to **control** the cell. Despite the directory name and the "ACTIVE
INFERENCE ENGINE" banner, this is **not** AGI/ASI: it is a predictive-coding
controller on a 16-cell toy MDP, and the trivial policy `always rest` already
solves the task. See `docs/research/control_emergence.md` for the full,
reproducible study.

## What's here

| File | Role |
|------|------|
| `hypervector.zig` | 8192-bit VSA primitives (XOR-bind, majority-bundle, SIMD popcount). |
| `environment.zig` | The 16-cell ion-grid "battery". Cell ≥ 5 = failure. Objective: avoid failure. |
| `agent.zig` | **The agent.** One synchronous, deterministic `Agent.step` = one control cycle (perceive → predict → act → observe → learn). Forward-model learning + model-based action selection + (optional) macros/meta. |
| `connectome.zig` | Macro/meta machinery, role-binding (`bindRule`/`traceInference`), associative memory. |
| `vm.zig` | Tiny ISA the homeostatic controller compiles to (tunes learning rate / tolerance). |
| `eval.zig` | **Evaluation harness** — baselines vs agent vs ablations, the number the project lacked. |
| `tests.zig` | Unit tests over the VSA algebra and the agent's readout channel. |
| `ghost_daemon.zig` / `main.zig` | Real-time wrapper + REPL that drive `Agent` live and stream telemetry to `dashboard.html`. |

## Build & run (Zig 0.14.1)

```sh
zig build eval         # reproducible control benchmark (baselines, ablations, E1/E2)
zig build eval -- 30000 8   # optional: n_steps, seeds
zig build unit-test    # VSA / readout-channel assertions
zig build engine       # live agent + dashboard telemetry on ws://127.0.0.1:8080
```

## Headline findings (all from `zig build eval`)

- The **as-built** design (perceptual learning + *random* actions) barely beats
  random and loses to a one-line fixed policy: it learns to *predict*, not *act*.
- Adding **model-based action selection** and acting greedily reaches **2.97
  failures / 1000 steps** vs **56.3** for random — real, reproducible competence.
- The headline **macros / "executive control" metacognition hurt or do nothing.**
- The competence is **fragile**: it works by recognising a recurring safe
  attractor, so a little exploration disrupts it and failures cascade.
