# Round AG / AG3 — Physics-shift loop transfer

**Verdict: VALID NEGATIVE.** A mutable tape is rebuilt after evaluator-private
interaction dynamics change and address, value, and boundary identities are
recoded. It holds more externally measured material than its old tape and the
ordinary random, replay, static, shuffled-lineage, and false-lineage controls.
Removing the rebuilt loop returns the old level. This is bounded recovery, not
organism-owned operational semantics or a self-maintained causal constraint.

## Question

Can a raw persistent construction reconstruct or evolve under a private physics
shift with no exposed score, target, action API, candidate menu, or answer
carryover? A positive additionally needs to beat an equal-material, equally
expressive fixed-loop control and prove the loop and proposal process are
organism-owned.

## Fixture and controls

The source uses 24 finite cells in deterministic lower-level interaction
physics. Before evaluation the exterior privately changes the physics and
simultaneously relocates cells, inverts value identities, and disperses old
groups. The external evaluator totals retained material only after the fact.
All probing, tape construction, and testing consume charged raw interactions.
The CSV records fixed-equal-loop, random, replay, static, ablation, shuffled
lineage, false lineage, and combined physics-plus-identity-shift controls.
Repeated runs must emit byte-identical CSVs.

## Why it is negative

The constructed result recovers private-medium persistence, but the equal
material/time fixed-loop ties exactly. More fundamentally, the source supplies
the 24 cell atoms, circular scan that declares a tape a loop, signed
interaction interpretation, tape representation, candidate/rebuild method, and
rebuild timing. The raw interaction is a selected host consequence channel,
not a physics relation the organism discovered. Thus this cannot unlock AG4–6.

## Reproduce

```bash
mkdir -p /tmp/zig-ag3-cache /tmp/zig-ag3-global
zig build-exe sparse_poly_discovery/physics_shift_loop_round_ag.zig \
  -femit-bin=/tmp/physics-shift-ag3 \
  --cache-dir /tmp/zig-ag3-cache --global-cache-dir /tmp/zig-ag3-global
/tmp/physics-shift-ag3 selftest
/tmp/physics-shift-ag3 run results/physics_shift_loop_round_ag.csv
```

Expected:

```text
round_ag_ag3 selftest PASS verdict=VALID_NEGATIVE deterministic=true physics_shift_recovery=true organism_owned=false
```

## Artifacts

- `sparse_poly_discovery/physics_shift_loop_round_ag.zig`
- `results/physics_shift_loop_round_ag.csv`
- `docs/research/physics_shift_loop_round_ag.md`
