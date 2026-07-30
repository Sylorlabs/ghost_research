# Conjunction wall — crossing it (round 2026-07-10c headline)
> **Belongs to: Round 2026-07-10c · experiment 1 of 6 (conjunction wall)** — [round index](../../../docs/research/research_round_2026_07_10c.md).

**Status:** built, measured. Reproduce:
```
cd wcore && zig build-exe -O ReleaseFast src/inv_wall.zig -femit-bin=bin/inv_wall
./bin/inv_wall selftest
./bin/inv_wall probe ../results/conj_wall_2026_07_10.csv
./bin/inv_wall forge ctrl ../results/conj_wall_2026_07_10.csv
./bin/inv_wall forge curr ../results/conj_wall_2026_07_10.csv
./bin/inv_wall forge mech ../results/conj_wall_2026_07_10.csv
```
Single-threaded, deterministic per seed (0xA70F, 0x5EED2), each phase well under
the 15-min cap.

## The wall (from round b)

Round 2026-07-10b (`aimed_forge.md`) measured that the distinct-count family
(7 of the 9 aimed frontier targets F) sits behind a **conjunction wall**: its
depth-1 behavioural-agreement residual has no climbable gradient — pure greedy
residual climb plateaus at **0.862** vs the **0.95** certification bar
(random-clean max 0.723). Behavioural-proximity pressure, at fitness or at the
promotion gate, cannot cross it. Round b named two escape levers; this
experiment builds and measures both, apples-to-apples with the round-b battery
(ported verbatim: 13 hidden programs, F = 9 frontier targets, E = 9
never-aimed transfer targets, seeds 0xA70F/0x5EED2, pop 90 × gens 45 × 10
rounds, the settled +1-depth promotion gate + full A5/A6 retro-audit).

## Instrument fidelity (selftest, all PASS)

- S1 `membership` and S2 `noveltyflag` stone oracles equal their brute
  references on 200×64 symbol streams.
- **The designed payoff identity holds:** the chain `[noveltyflag, g_add]`
  equals the distinct-count target exactly — so once an S2-equivalent atom is
  promoted, distinct becomes a depth-2 composition.
- **The trap the ladder is designed around is real:** agreement(S1 program, S2
  oracle) = 0.000 at mechanism edit-distance 1 — the two stones are behavioural
  complements, so you cannot climb from one to the other.
- Mechanism-descriptor table: distinct-count uniquely scores M = 1.000 on all
  three factors (m_rel·m_perm·m_dup); membership/noveltyflag score only 0.111
  on m_dup (no accumulator); g_xor 0.354, g_add 0.260, hashtbl 0.023.

## Result

### Probe phase — the wall is not climbable under ANY lens
Greedy climb, equal budget (8 restarts × 90k evals), best agreement to distinct:

| arm | 0xA70F | 0x5EED2 | vs 0.95 bar |
|-----|--------|---------|-------------|
| behavioural-agreement (control) | 0.875 | 0.839 | plateau — reproduces round-b 0.862 |
| curriculum final stone (S3 distinct, climbed directly) | 0.875 | 0.835 | same plateau |
| mechanism-pure (M as fitness) | 0.446 | 0.732 | worse (M ≠ agreement) |
| mechanism-blend (0.5 M + 0.5 agree) | 0.772 | 0.750 | below control |

No lens climbs distinct past ~0.88. The wall is a genuine gradient absence,
not a weak-lens artifact — confirmed against three new lenses.

### Forge phase — the curriculum crosses it; nothing else does
Frontier reachability `f_reach` (of the 9 F targets) after 10 promotion rounds:

| arm | 0xA70F f_reach | 0x5EED2 f_reach | mechanism |
|-----|----------------|-----------------|-----------|
| **ctrl** (aimed_promote on the wall family, hashtbl/union excluded) | **0** | **0** | wall holds — reproduces round b |
| **curr** (lever A: stone ladder + incumbent injection) | **6** | **6** | stones promoted → target composable |
| **mech** (lever B: M at the promotion gate) | **0** | **0** | structural credit does not cross it |

**The curriculum crosses the wall on both seeds, 0 → 6/9.** The jump is not a
climb: `f_reach` rises to 6 at the exact round the `noveltyflag` stone is
solved and promoted (`stone_solved` then `compose_advance` in the CSV), because
`distinct = noveltyflag → g_add` is then a depth-≤2 composition and 4 of its 6
hidden compositions follow at depth ≤3. Since F contains only 2 already-
climbable members (hashtbl, union), **at least 4 of the 6 reached targets are
genuine wall-family compositions** — the family the control reaches 0 of.

Both stepping stones behave exactly as designed: S1 `membership` (a
2-instruction sub-conjunction, structurally the hashtbl family whose landscape
the probe measured as climbable) and S2 `noveltyflag` (one instruction beyond
S1) each certify and promote with best-gate agreement 1.000. The curriculum
arm's promotions are clean: **0 depth-4 retro-audit rejects** across all rounds
on both seeds (the control had 2 and 1).

## Verdict

**Lever A (stepping-stone curriculum) crosses the conjunction wall; lever B
(mechanism-level descriptors) does not.** The measured mechanism is precise and
matches round b's theory: the wall is a *gradient* absence, not a *reachability*
absence. You cannot climb to distinct-count directly — but you can climb to a
sub-conjunction that *does* have gradient (`membership`/`noveltyflag`), promote
it as a reusable atom, and then reach the target by composition. The wall is
bypassed at the promotion boundary, exactly where round b said aim belongs, not
inside the fitness landscape (mechanism-pure/blend both fail, and M-at-gate
fails too — structural credit alone doesn't identify a promotable stone).

This is a controlled instance of the Closure Principle's escape corollary at
the *curriculum* level: the target is outside the depth-≤3 closure of the base
library, and the escape generator is not a new primitive but a **discovered
intermediate abstraction** (the novelty flag) that, once promoted, relocates
the target inside the closure. The honest bound: the curriculum's stones were
hand-designed from the known distinct-count mechanism. Auto-discovering the
right decomposition — which sub-conjunction has gradient AND composes to the
target — for a mechanism whose structure is unknown in advance is the next
frontier, the same "discover the family itself" line the sparse_poly work
reaches from the other side.

## Files
- `wcore/src/inv_wall.zig` — the experiment (selftest / probe / forge arms)
- `results/conj_wall_2026_07_10.csv` — probe + forge rows, both seeds
