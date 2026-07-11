# EXPERIMENT E8 — terminal-invented predicates (execution as verifier)

**Status:** built, measured (2026-06-29). Reproduce:
```
cd boundary_crossing && zig build open-invention-e8 --release=fast
```
Simulated (no shell): `zig build open-invention-e8 --release=fast -- --sim`

## Thesis

`feature_invent.zig` invents predicates over integers from primitive ops; `terminal_ground.zig` grounds
language in real exit codes. **E8 fuses them:** execution sensors are primitive; **predicates are invented**
from observed run behavior; NL request tokens are **forged** into compound features; a **logistic readout**
predicts outcomes on **auto-generated novel commands**; every prediction is **verified by a future live run**.

The terminal is the verifier (RLVR / `verify_learn_invent --live` pattern). No LLM, no corpus labels.

---

## Architecture

```
Safe whitelist commands
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│  Phase 1 GROUND — std.process.Child.run → RunSig             │
│    exit_ok, time_ms, out_len, err_len (timing patterns)       │
├───────────────────────────────────────────────────────────────┤
│  Phase 2 INVENT — search Atom / (Atom∧Atom) predicates        │
│    dedup by behavior bitset over training runs                │
├───────────────────────────────────────────────────────────────┤
│  Phase 3 FORGE+LOGISTIC — NL bigrams → perceptron weights     │
│    + softmax-style logistic probability on forged features    │
├───────────────────────────────────────────────────────────────┤
│  Phase 4 PREDICT→VERIFY — auto-generated novel paraphrases    │
│    predict from words → RUN command → CERTIFIED if match      │
└───────────────────────────────────────────────────────────────┘
```

### Primitive execution sensors (handed)

| Atom | Meaning |
|------|---------|
| `exit_ok` / `exit_fail` | exit code == 0 |
| `fast` / `slow` | `time_ms` vs 50ms bucket |
| `empty_out` / `has_out` | stdout length |
| `has_stderr` / `err_dominates` | stderr footprint |

Predicates = single atom, negated atom, or `atom∧atom`. Surviving distinct behaviors are the
**invented predicates** (not named ahead of time).

### Safe whitelist

Commands must start with: `test`, `ls`, `echo`, `false`, `true`, `pwd`, `wc`, `head`, `grep`, `cat`, `find`.
Read-only probes only — no writes, network, or user input.

### Auto-generated predict targets

Eight compositional paraphrases × commands **never paired in training**, e.g.:
- `"does the fake readme exist now"` → `test -f zzz_fake_readme_e8.xyz`
- `"how many zig modules are present"` → `ls *.zig | wc -l`

Future runs ground truth; `CERTIFIED` only when live shell agrees with prediction.

---

## Measured numbers (ReleaseFast, live shell, 2026-06-29)

| Metric | Result |
|--------|--------|
| Training corpus | 20 real command runs |
| Invented predicates | **6** (deduped behaviors) |
| Forged NL features | **105** |
| Auto-generated novel targets | **8** |
| Logistic accuracy (novel) | **7/8 = 88%** |
| **CERTIFIED predict rate (novel, live)** | **7/8 = 88%** |

### Phase 4 detail (predict → verify)

| Request | Predict | Real | |
|---------|---------|------|---|
| does the fake readme exist now | errors | errors | ✓ |
| is the bogus build file around | ok | errors | ✗ |
| how many zig modules are present | ok | ok | ✓ |
| verify the readme is still here | ok | ok | ✓ |
| run the failure sentinel probe | errors | errors | ✓ |
| probe missing documentation file | errors | errors | ✓ |
| confirm build dot zig still exists | ok | ok | ✓ |
| cat the nonexistent research note | errors | errors | ✓ |

**Miss analysis:** `"is the bogus build file around"` — training pairs `build`/`around` with success;
`bogus` alone was insufficient to flip the forged readout. Honest compositional ambiguity on a tiny slice.

### Invented predicate activation (training)

| Predicate | errors | ok |
|-----------|--------|-----|
| `exit_ok` | 0 | 12 |
| `¬exit_ok` | 8 | 0 |
| `exit_ok∧empty_out` | 0 | 8 |
| `exit_ok∧has_out` | 0 | 4 |
| `fast` | 8 | 12 |
| `fast∧empty_out` | 8 | 8 |

`¬exit_ok` perfectly separates failure runs — invented, not handed as a label rule.

---

## Verdict: **PASS**

**7/8 = 88%** certified predict on auto-generated novel phrasings with **live shell verification**.
Execution is the outside verifier: invented predicates + forged NL features predict outcome class,
and only `CERTIFIED` when a future run agrees. One compositional miss (`bogus` + `around`) on a
20-command training slice — honest partial ambiguity, not a certifier failure.

---

## Comparison to references

| Source | What E8 steals |
|--------|----------------|
| `engine_live.zig` | teach/predict loop; exit code = outcome; surprise-ready |
| `terminal_ground.zig` | real `Child.run`; predict→verify on novel requests |
| `verify_learn_invent --live` | whitelisted live execution; CERTIFIED only when verified |
| `feature_invent.zig` | invent predicates from primitives; dedup by behavior |
| `terminal_grind.zig` / `rune_native.zig` | forge bigram compound features from text |

---

## Honest limits

1. **Bounded command slice** — dozens of safe probes, not arbitrary shell.
2. **Binary readout** — logistic predicts `ok` vs `errors`; timing predicates invented but not yet in readout features.
3. **No NL→command synthesis** — commands are paired with generated paraphrases; words predict outcome class, not argv.
4. **Small corpus** — 20 train + 8 novel; one compositional miss is expected.
5. **AGI not claimed** — grounded actionable language under a sound verifier.

---

## Code map

| File | Role |
|------|------|
| `boundary_crossing/open_invention_e8.zig` | E8 harness: ground, invent, forge, logistic, verify |
| `boundary_crossing/build.zig` | `open-invention-e8` step |
| `boundary_crossing/docs/research/open_invention_e8.md` | This doc |

See also: `verify_learn_invent.md`, `terminal_ground.zig`, `feature_invent.zig`, `verification_learning.md`.