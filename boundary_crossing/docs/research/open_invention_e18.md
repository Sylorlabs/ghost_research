# EXPERIMENT E18 — terminal NL→command synthesis (E8++)

**Status:** built, measured (2026-06-29). Reproduce:
```bash
cd boundary_crossing && zig build open-invention-e18 --release=fast
```
Simulated (no shell): `zig build open-invention-e18 --release=fast -- --sim`

## Thesis

E8/RQ6 proved the terminal can **verify** invented predicates and predict **outcome class** on novel
phrasings. **E18 closes the gap E8 honestly flagged:** NL phrases now **synthesize whitelisted argv**
(phrase→command), ground each run (command→outcome), and certify on held-out novel phrasings by
**exact command match** after live execution.

No LLM, no corpus labels — the shell is the verifier.

---

## Architecture

```
Canonical whitelisted argv table (21 commands)
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│  Phase 1 GROUND — phrase→command→outcome triples             │
│    std.process.Child.run on every training command            │
├───────────────────────────────────────────────────────────────┤
│  Phase 2 INVENT — Atom / (Atom∧Atom) predicates (E8)       │
│    dedup by behavior bitset over training runs                │
├───────────────────────────────────────────────────────────────┤
│  Phase 3 FORGE+COMMAND READOUT — uni+bigram+trigram features  │
│    perceptron over command-index (not outcome class)            │
├───────────────────────────────────────────────────────────────┤
│  Phase 4 SYNTHESIZE→RUN→VERIFY — 100 held-out novel phrasings │
│    predict argv → run synth + truth → CERTIFIED if cmd match  │
└───────────────────────────────────────────────────────────────┘
```

### Safe whitelist

Same expanded family as RQ6: `test`, `ls`, `echo`, `false`, `pwd`, `wc`, `head`, `grep`, `cat`,
`stat`, `readlink`, etc. Read-only probes only.

### Canonical argv slots

Train and held-out share the **same 21 argv strings** per semantic slot. Novelty is in **prefix +
object phrasing**, not different shell paths. Object anchors disambiguate:

| Anchor words | Example argv |
|--------------|--------------|
| `missing` / `phantom` + `documentation` | `test -f zzz_missing_e18.xyz` |
| `script` / `sentinel` | `false` |
| `count` (not `listing`) | `ls *.zig \| wc -l` |
| `listing` (not `count`) | `ls -1 *.zig` |
| `present on disk` | `test -f README.md` |
| `byte size` / `footprint` | `stat -c %s README.md` |

### Held-out phrasing banks

Training prefixes: `"open the"`, `"count the"`, `"check the"`, …  
Held-out prefixes: `"attempt the"`, `"reckon the"`, `"doublecheck the"`, … (disjoint vocabulary)

---

## Measured numbers (ReleaseFast, live shell, 2026-06-29)

| Metric | Result |
|--------|--------|
| Training phrase→command→outcome | **184** |
| Unique whitelisted commands | **21** |
| Invented predicates | **6** |
| Forged NL features (uni+bi+tri) | **442** |
| Held-out novel phrasings | **100** |
| Training epochs | 1600 |

### Phase 4 — synthesize → run → verify

| Metric | Result |
|--------|--------|
| Command match (held-out) | **73/100 = 73.0%** |
| **CERTIFIED command match (live)** | **73/100 = 73.0%** |
| Outcome agree (synth vs truth run) | **90/100 = 90.0%** |

### Miss analysis (27 command mismatches)

Typical failure mode: **near-synonym slots within a family** — e.g. `"determine the zig module
count"` synthesized `ls docs/research/*.md | wc -l` instead of `ls *.zig | wc -l` (both NUMBER
family; `zig` vs `markdown` anchor competed). Similarly some `stat` vs `readlink` readme-metadata
confusion when object phrases share `readme` tokens.

Outcome agreement (90%) exceeds command match (73%) because wrong argv in the same outcome family
still produces compatible execution labels.

---

## Verdict: **PASS**

**73/100 = 73%** certified command match on **100 held-out novel phrasings** with **live shell
verification** — exceeds the **≥60%** pass bar.

E8++ is real: forged NL features synthesize argv from unseen prefix banks; the terminal certifies by
running. Bounded safe-command menu; object-word anchors carry argv selection.

---

## Comparison to references

| Source | What E18 steals |
|--------|-----------------|
| `open_invention_e8.zig` | invented predicates, forge+logistic, live verify |
| `open_invention_rq6.zig` | 200-scale grind, expanded whitelist, combinatorial banks |
| `terminal_grind_big.zig` | uni+bigram forge, outcome grounding |
| `terminal_ground.zig` | predict→verify loop, Child.run labels |

| Experiment | Predicts | Held-out | Key metric |
|------------|----------|----------|------------|
| E8 | outcome class (2-way) | 8 | 7/8 certified predict |
| RQ6 | outcome class (5-way) | 50 | 50/50 certified predict |
| **E18** | **argv string (21-way)** | **100** | **73/100 certified cmd match** |

---

## Honest limits

1. **Whitelist-bounded** — 21 argv strings, not arbitrary shell synthesis.
2. **Slot anchors required** — `count` vs `listing`, `present` vs `missing`; shared `readme` tokens still confuse nearby slots.
3. **Shared canonical argv** — held-out uses same paths as training per slot; tests phrasing generalization, not path invention.
4. **Invented predicates not in readout** — same E8 gap; sensors invent but command readout uses forged words only.
5. **AGI not claimed** — grounded actionable language under a sound execution verifier.

---

## Code map

| File | Role |
|------|------|
| `boundary_crossing/open_invention_e18.zig` | E18 harness: phrase→command→outcome, synthesize, verify |
| `boundary_crossing/open_invention_e8.zig` | E8 base; cross-ref to E18 |
| `boundary_crossing/open_invention_rq6.zig` | RQ6 scale; cross-ref to E18 |
| `boundary_crossing/build.zig` | `open-invention-e18` step |
| `boundary_crossing/docs/research/open_invention_e18.md` | This doc |

See also: `open_invention_e8.md`, `open_invention_rq6.md`, `open_invention_experiments.md`.