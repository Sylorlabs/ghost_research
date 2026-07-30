# RESEARCH Q6 — E8 scale: 200-command terminal grind + 50 held-out phrasings

**Status:** built, measured (2026-06-29). Reproduce:
```bash
cd boundary_crossing && zig build open-invention-rq6 --release=fast
```
Simulated (no shell): `zig build open-invention-rq6 --release=fast -- --sim`

## Thesis

E8 proved terminal grounding works on a **20-command slice** (7/8 certified predict). **RQ6 scales it**
to `terminal_grind_big` corpus size: **200 grounded training commands**, **50 held-out novel phrasings**,
expanded safe whitelist, invented execution predicates, forged uni+bigram features, perceptron+logistic
readout — and compares **uniform** vs **surprise-weighted** perceptron updates.

Pass bar: **≥80% certified predict** on held-out novel phrasings (live shell verification).

---

## Architecture

```
Expanded safe whitelist (26 read-only prefixes)
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│  Phase 1 GROUND — 200 training commands, 5 outcome classes    │
│    FAIL / EMPTY / NUMBER / LISTING / TEXT (real Child.run)    │
├───────────────────────────────────────────────────────────────┤
│  Phase 2 INVENT — Atom / (Atom∧Atom) predicates (E8 pattern) │
│    dedup by behavior bitset over 200 training runs            │
├───────────────────────────────────────────────────────────────┤
│  Phase 3 FORGE+LOGISTIC — uni+bigram features, dual trainers  │
│    uniform (w=1.0) vs surprise-weighted (sigil EMA + RLVR)    │
├───────────────────────────────────────────────────────────────┤
│  Phase 4 PREDICT→VERIFY — 50 held-out novel phrasing banks    │
│    phrasings never in train vocabulary → RUN → CERTIFIED      │
└───────────────────────────────────────────────────────────────┘
```

### Expanded safe whitelist

Commands must start with one of:
`test`, `ls`, `echo`, `false`, `true`, `pwd`, `wc`, `head`, `grep`, `cat`, `find`,
`date`, `whoami`, `sort`, `uniq`, `tr`, `cut`, `dirname`, `basename`, `readlink`,
`stat`, `expr`, `seq`, `printf`, `id`, `uname`.

Read-only probes only — no writes, network, or user input.

### Surprise-weighted updates

On misclassification, update magnitude scales by:
1. **Sigil EMA** on true-class logit margin (learn harder when below recent band).
2. **RLVR boost** — extra weight when softmax probability on true class is low.

Uniform baseline uses fixed `w = 1.0` (E8 / `terminal_grind_big` pattern).

### Held-out phrasing banks (novel vocabulary)

Training uses banks like `"count the"`, `"open the"`, `"check the"`.
Held-out uses disjoint banks like `"quantify the"`, `"attempt the"`, `"validate the"`,
`"catalog the"`, `"utter a"` — **50 compositional paraphrases** paired with safe commands.

---

## Measured numbers (ReleaseFast, live shell, 2026-06-29)

| Metric | Result |
|--------|--------|
| Training commands grounded | **200** |
| Training outcome distribution | FAIL=40 EMPTY=30 NUMBER=47 LISTING=41 TEXT=42 |
| Invented predicates | **6** (same sensor family as E8) |
| Forged NL features | **187** |
| Held-out novel phrasings | **50** |
| Training epochs | 900 |

### Predict → verify (held-out)

| Trainer | Predict accuracy | **Certified predict rate** |
|---------|------------------|----------------------------|
| **Uniform** | **50/50 = 100.0%** | **50/50 = 100.0%** |
| Surprise-weighted | 14/50 = 28.0% | 14/50 = 28.0% |
| **Surprise − uniform delta** | −72.0 pp | **−72.0 pp** |

### Surprise-weighted failure mode

Surprise weighting **hurt** generalization on this slice. Held-out FAIL phrasings with novel
prefixes (`"attempt the"`, `"reach for the"`) were often mispredicted as EMPTY or LISTING —
training words like `"check"` / `"list"` were over-amplified by hard-example weighting.
Uniform perceptron updates remain the stable choice at grind scale for this grounded readout.

---

## Verdict: **PASS**

**50/50 = 100%** certified predict on **50 held-out novel phrasings** (uniform trainer) — exceeds
the **≥80%** pass bar. Surprise-weighted training **regressed** (−72 pp); reported as a quantified
negative result, not a failure of terminal grounding.

---

## Comparison to references

| Source | What RQ6 steals |
|--------|-----------------|
| `open_invention_e8.zig` | invented predicates, forge+logistic, predict→verify, safe whitelist |
| `terminal_grind_big.zig` | 200-command combinatorial corpus, 5 outcome classes, uni+bigram |
| `sigil_organ.zig` | surprise-weighted LR via EMA margin band |
| `verify_learn_invent.zig` | RLVR-style stronger updates on violations |

| Experiment | Train | Held-out | Certified predict |
|------------|-------|----------|-------------------|
| E8 | 20 | 8 | 7/8 = 88% |
| terminal_grind_big | 184 (75/25 split) | 46 | ~stable % (shuffle split) |
| **RQ6** | **200** | **50 novel banks** | **50/50 = 100%** (uniform) |

---

## Honest limits

1. **Commands still paired** — NL predicts outcome class, not argv synthesis.
2. **Whitelist-bounded** — 26 safe prefixes, not arbitrary shell.
3. **Surprise weighting regressed** — quantified negative result; not a free win at this scale.
4. **Invented predicates not in readout** — same E8 gap; sensors invent but logistic uses forged words only.
5. **AGI not claimed** — grounded actionable language under a sound execution verifier.

---

## Code map

| File | Role |
|------|------|
| `boundary_crossing/open_invention_rq6.zig` | RQ6 harness: grind, invent, dual-train, verify |
| `boundary_crossing/build.zig` | `open-invention-rq6` step |
| `boundary_crossing/docs/research/open_invention_rq6.md` | This doc |

See also: `open_invention_e8.md`, `terminal_grind_big.zig`, `open_invention_experiments.md` (fork #3: E8 scale).