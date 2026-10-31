# Open invention experiments — master report (June 2026)

**Status:** 12 experiments built, run, documented. Each has its own report; this file is the consolidated verdict.

**Thesis tested:** Can the verifier-native stack invent **outside** a handed operator menu — not remix like LLMs, not select from a cheat sheet?

**Closure Principle prediction:** Most experiments **fail or partially pass**; escape requires an outside generator matched to predicate shape.

---

## Summary table

| ID | Experiment | Verdict | Key number | Doc |
|----|------------|---------|------------|-----|
| **E1** | Frozen-forge blind zoo | **PASS*** | 9/11 novel primitives on battery B | [`open_invention_e1.md`](../sparse_poly_discovery/docs/research/open_invention_e1.md) |
| **E2** | POET-lite adversarial | **PARTIAL** | 10/24 forge-solved; 14 oracle-only | [`open_invention_e2.md`](../sparse_poly_discovery/docs/research/open_invention_e2.md) |
| **E3** | No spectral ablation | **PASS** | Parity **1.000** via `mod(count,2)` synthesis | [`open_invention_e3.md`](../sparse_poly_discovery/docs/research/open_invention_e3.md) |
| **E4** | Certified menu minting | **POSITIVE** | 0%→**90%** solve; 2 minted ops; saturates round 2 | [`open_invention_e4.md`](../sparse_poly_discovery/docs/research/open_invention_e4.md) |
| **E5** | Composed pipelines | **PASS** | F-A/F-B **0.54/0.43 → 1.000** blind | [`open_invention_e5.md`](../sparse_poly_discovery/docs/research/open_invention_e5.md) |
| **E6** | k≥3 open forge | **FAIL** | **0/16** random aliens; no promotion | [`open_invention_e6.md`](../sparse_poly_discovery/docs/research/open_invention_e6.md) |
| **E7** | Corpus rune primitives | **FAIL** | **+0** lift vs frozen menu | [`open_invention_e7.md`](../sparse_poly_discovery/docs/research/open_invention_e7.md) |
| **E8** | Terminal predicates | **PASS** | **7/8** certified predict (live) | [`open_invention_e8.md`](../boundary_crossing/docs/research/open_invention_e8.md) |
| **E9** | Cross-corpus compress | **FAIL** | 0 macros; 5-byte search noise (re-run OK) | [`open_invention_e9.md`](../boundary_crossing/docs/research/open_invention_e9.md) |
| **E10** | Novelty-only forge | **QUANTIFIED** | 16 promoted; **10.9%** random hits vs **1.6%** useful forge | [`open_invention_e10.md`](../sparse_poly_discovery/docs/research/open_invention_e10.md) |
| **E11** | LLM proposer / engine judge | **PASS** | 8/20 certified; **1 novel** (`sum_mod7_indicator`) | [`open_invention_e11.md`](../sparse_poly_discovery/docs/research/open_invention_e11.md) |
| **E12** | Propose-solve-verify self-play | **PASS*** | 75 rounds; frontier depth **7/7**; curriculum empty | [`open_invention_e12.md`](../sparse_poly_discovery/docs/research/open_invention_e12.md) |

\*E1 PASS uses handed discovery menu on battery — see caveats.  
\*E12 PASS is solver strength, not hard curriculum — unified loop solves almost everything.

---

## Reproduce all

```bash
# sparse_poly_discovery (E1–E7, E10–E12)
cd sparse_poly_discovery
zig build open-invention-e1 open-invention-e3 open-invention-e5 --release=fast
# E2/E4/E6/E10/E12: may need direct build if sibling targets break install graph:
zig build-exe open_invention_e2.zig -OReleaseFast -femit-bin=/tmp/e2 && /tmp/e2

# boundary_crossing (E8, E9)
cd boundary_crossing
zig build open-invention-e8 open-invention-e9 --release=fast
```

---

## What actually counts as "open invention"

### Genuine positives (new evidence)

1. **E3 — `mod(count,2)` without Fourier menu.** Parity certified via program synthesis over `{+,×,sin,cos,abs,mod}`. Not hand-named spectral; correct Z₂ readout discovered after monomial saturation. **Strongest anti-remix result.**

2. **E5 — Blind composed pipelines.** Inversion-parity and sum-then-bind solved without being told product or spectral. Stage-1 alone fails; full pipeline certifies at 1.000.

3. **E4 — Minted VM programs.** 0%→90% from cell-only menu via 2 synthesized primitives. Still **inside VM closure** but not pre-listed menu entries.

4. **E11 — LLM proposer, engine judge.** 20 proposals → 8 certified. **`sum_mod7_indicator`** accepted as novel (world-pool family, not Walsh/spectral/monomial). Boolean targets only matched known families — engine honestly rejected creative noise (`gcd`, `sin_variance`, etc.).

5. **E8 — Terminal grounding.** 7/8 live certified predictions on novel command phrasings. Execution as outside verifier works on **action**, not language.

### Honest failures (closure law confirmed)

1. **E6 — k≥3 random aliens: 0/16.** Uncountable clone regime does not auto-discover; same saturation as Boolean forge.

2. **E7 — Corpus runes: +0 lift.** English byte-pairs do not invent grid primitives; T5 still needs spectral; T7 needs world pool.

3. **E9 — Cross-corpus compression: 0 transfer (re-run 2026-06-30).** Train library **0 macros**; held-out delta 5 bytes is search noise, not macro generalization. Crash fixed via chunk caps + vote sampling.

4. **E10 — Novelty-only: 16 atoms, 10.9% random hits.** Confirms wcore tension: irreducibility ≠ usefulness (useful forge: 4/5 zoo vs novelty: 2/5).

5. **E2 — 14/24 XOR-family targets oracle-only.** Forge cannot reach GF(2) XOR parity without injecting Walsh/XOR readout.

### Partial / qualified passes

1. **E1 — Blind battery 11/11 solved, 9 novel primitives** — but escapes use **handed menu** (spectral/Walsh/world). Proves generalization across random targets, not invention of operator families from void.

2. **E12 — 225/225 solved, depth 7/7** — unified loop is too strong; POET curriculum stays empty (0–1 targets in band). Self-play works; **hard curriculum does not**.

---

## Cross-cutting conclusions

### 1. Open invention is real but narrow

- **Program synthesis + certifier** can find `mod(count,2)`, composed pipelines, and VM trees **not explicitly named** in the menu.
- It is **not** open-ended AGI: every success stays inside a **designed search space** (VM ops, pipeline menu, world pool).

### 2. Outside generators that work

| Generator | Experiment | Evidence |
|-----------|------------|----------|
| `mod` / arithmetic synthesis | E3 | Parity without Fourier |
| Composed pipeline search | E5 | Two families blind |
| VM program minting | E4 | 0%→90% |
| World pool (mod arithmetic) | E1, E11 | sum%mod_7 |
| Terminal execution | E8 | 7/8 live predict |
| LLM proposals (subordinated) | E11 | 1 novel certified feature |

### 3. Outside generators that failed

| Generator | Experiment | Evidence |
|-----------|------------|----------|
| English corpus runes | E7 | +0 lift |
| Cross-corpus compression macros | E9 | 0 bytes |
| k≥3 monomial forge alone | E6 | 0/16 |
| Novelty-only promotion | E10 | Useless zoo coverage |
| XOR without Walsh injection | E2 | 14 oracle-only |

### 4. The honest boundary (unchanged)

> **Search inside a fixed closure composes. Open invention = certified selection or synthesis within a deliberately rich outer shell, OR injection from data/execution/LLM-proposer — not minting new mathematics from nothing.**

---

## Recommended next forks (from these results)

1. **Combine E3 + E5:** default discover path = pipeline synthesizer first, spectral menu second (only if saturate).
2. **E2 gap:** inject GF(2) XOR readout when Q38 compound detected — test if hardness router closes the 14 oracle-only cases.
3. **E8 scale:** terminal grind at hundreds of commands — only domain with unlimited fresh verifier labels.
4. **E12 fix:** harder mutators (multi-target, noisy labels) to keep POET curriculum non-empty.
5. **E11 production:** LLM proposes → engine certifies → promote to library (DreamCoder wake-sleep with verifier gate).

---

## Documentation index (all 12 + master)

| Exp | Doc | Status |
|-----|-----|--------|
| E1 | `sparse_poly_discovery/docs/research/open_invention_e1.md` | ✓ |
| E2 | `sparse_poly_discovery/docs/research/open_invention_e2.md` | ✓ |
| E3 | `sparse_poly_discovery/docs/research/open_invention_e3.md` | ✓ |
| E4 | `sparse_poly_discovery/docs/research/open_invention_e4.md` | ✓ |
| E5 | `sparse_poly_discovery/docs/research/open_invention_e5.md` | ✓ |
| E6 | `sparse_poly_discovery/docs/research/open_invention_e6.md` | ✓ |
| E7 | `sparse_poly_discovery/docs/research/open_invention_e7.md` | ✓ |
| E8 | `boundary_crossing/docs/research/open_invention_e8.md` | ✓ |
| E9 | `boundary_crossing/docs/research/open_invention_e9.md` | ✓ (re-run 2026-06-30) |
| E10 | `sparse_poly_discovery/docs/research/open_invention_e10.md` | ✓ |
| E11 | `sparse_poly_discovery/docs/research/open_invention_e11.md` | ✓ |
| E12 | `sparse_poly_discovery/docs/research/open_invention_e12.md` | ✓ |
| **Master** | `docs/research/open_invention_experiments.md` | ✓ |

## File index

| Experiment | Source | Build step |
|------------|--------|------------|
| E1 | `sparse_poly_discovery/open_invention_e1.zig` | `open-invention-e1` |
| E2 | `sparse_poly_discovery/open_invention_e2.zig` | `open-invention-e2` |
| E3 | `sparse_poly_discovery/open_invention_e3.zig` | `open-invention-e3` |
| E4 | `sparse_poly_discovery/open_invention_e4.zig` | `open-invention-e4` |
| E5 | `sparse_poly_discovery/open_invention_e5.zig` | `open-invention-e5` |
| E6 | `sparse_poly_discovery/open_invention_e6.zig` | `open-invention-e6` |
| E7 | `sparse_poly_discovery/open_invention_e7.zig` | `open-invention-e7` |
| E8 | `boundary_crossing/open_invention_e8.zig` | `open-invention-e8` |
| E9 | `boundary_crossing/open_invention_e9.zig` | `open-invention-e9` |
| E10 | `sparse_poly_discovery/open_invention_e10.zig` | `open-invention-e10` |
| E11 | `sparse_poly_discovery/open_invention_e11.zig` + `e11_proposals.json` | `open-invention-e11` |
| E12 | `sparse_poly_discovery/open_invention_e12.zig` | `open-invention-e12` |

See also: `CLOSURE_PRINCIPLE.md`, `inventable_substrate_design.md`, `verify_learn_invent.md`.