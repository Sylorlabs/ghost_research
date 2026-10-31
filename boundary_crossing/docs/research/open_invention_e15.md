# EXPERIMENT E15 — verify_learn_invent production loop

**Status:** built, measured (2026-06-29). Reproduce:
```
cd boundary_crossing && zig build open-invention-e15 --release=fast
```
Simulated terminal (no shell): `zig build open-invention-e15 --release=fast -- --sim`

## Thesis

`verify_learn_invent.zig` integrates routing, invention, discovery, and terminal grounding in one binary.
**E15 asks:** does the full **production loop** — English → route → invent → **certify** → **promote** → **reuse**
on a **second target** — work on **novel held-out phrasings**, with **persistent libraries**?

No LLM. Labels from gzip round-trip, chain minimality proof, unified held-out certifier, and exit codes.

---

## Architecture

```
Bootstrap routing (84-phrase corpus, perceptron)
        │
        ▼
┌──────────────────────────────────────────────────────────────────┐
│  Phase 2 — 20 held-out phrases (compress / discover / terminal) │
├──────────────────────────────────────────────────────────────────┤
│  Phase 3 — production REPL (scripted), libraries persist:         │
│    1. invent_compress  — macro lib grows; 2nd dataset reuses     │
│    2. invent_chain     — certify n=255, reuse certifier n=511   │
│    3. discover_feature — unified sequential targets + feature lib │
│    4. terminal_teach   — observation memory grows                │
│    5. terminal_predict — novel phrasings recall verified mem     │
└──────────────────────────────────────────────────────────────────┘
```

### Pass bars

| Metric | Bar | Measured |
|--------|-----|----------|
| Held-out routing (20 phrases) | ≥70% | **19/20 = 95%** |
| Invent intents certified+reused (5 slots, 2nd target) | ≥3/5 | **5/5** |

---

## Measured numbers (ReleaseFast, live shell, 2026-06-29)

### Phase 2 — routing (20 held-out)

| Family | Phrases | Correct |
|--------|---------|---------|
| compress | 7 | **7/7** |
| discover | 7 | **6/7** |
| terminal (teach/predict/recall) | 6 | **6/6** |
| **Total** | **20** | **19/20 = 95%** |

**Miss:** `"probe the mystery signal"` → ABSTAIN (no content token above stopword filter; honest OOS).

### Phase 3 — production loop (5 × 2 targets)

| Slot | T1 | T2 | Reused | Pass |
|------|----|----|--------|------|
| invent_compress | gzip 321→80 CERTIFIED | gzip 180→68 CERTIFIED | macro lib (1 promoted) | ✓ |
| invent_chain | l(255)=10 CERTIFIED | l(511)=12 CERTIFIED | certifier | ✓ |
| discover_feature | parity cov=1.000 lib 8→9 | sum%7 cov=1.000 lib_before=9 | unified library | ✓ |
| terminal_teach | echo probe CERTIFIED | false→errors CERTIFIED | 2 obs in memory | ✓ |
| terminal_predict | forecast echo probe CERTIFIED | anticipate false CERTIFIED | memory | ✓ |

**Library persistence at end:** compress_macros=1, discover_features=10, terminal_obs=2.

---

## Verdict: **PASS**

- Routing **95%** (bar 70%).
- **5/5** invent intents certified and reused on second target (bar 3/5).
- Persistent libraries demonstrably carry state across the scripted production session.

---

## Comparison to references

| Source | What E15 steals |
|--------|-----------------|
| `verify_learn_invent.zig` | intent perceptron, compress/chain/discover/terminal loops |
| `engine_repl.zig` | persistent compression macro library |
| `unified_invention.zig` | `runSequentialTargets` — promote features, reuse on next target |
| `open_invention_e8.zig` / RQ6 | terminal teach→predict with verified memory |

---

## Honest limits

1. **Scripted REPL** — not interactive stdin; production loop is measured, not human-driven multi-turn chat.
2. **Bounded intents** — 7-class router; open English outside compress/discover/terminal still abstains.
3. **Discover NL gap** — English routes to `discover_feature`; target specs are still structured (parity, sum%7).
4. **Compress reuse** — promotion is macro abstraction inside delta/stride closure (DreamCoder-style), not closure escape.
5. **AGI not claimed** — invention under sound verifiers on fixed domains.

---

## Code map

| File | Role |
|------|------|
| `boundary_crossing/open_invention_e15.zig` | E15 harness: routing battery + production loop |
| `sparse_poly_discovery/unified_invention.zig` | `runSequentialTargets` — persistent discover library |
| `boundary_crossing/build.zig` | `open-invention-e15` step |
| `boundary_crossing/docs/research/open_invention_e15.md` | This doc |

See also: `verify_learn_invent.md`, `open_invention_e8.md`, `open_invention_experiments.md`.