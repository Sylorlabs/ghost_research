# E7 — Corpus-invented primitives (data as outside generator)

**Question:** Can byte-pair runes forged from raw corpus text certify escapes on grid predicates
where the monomial forge saturates — and do they add lift **beyond** a frozen symbolic operator menu
(spectral / Walsh / Clifford)?

**Key file:** `sparse_poly_discovery/open_invention_e7.zig`  
**Corpus:** `corpus/train_mix.txt` (250 KB interleaved EN/ZH; override via CLI arg)  
**RNG seed:** `0xE7C0FF01CEE7` (pinned)

## Reproduce

```bash
cd sparse_poly_discovery
zig build open-invention-e7 --release=fast
# or:
zig build-exe open_invention_e7.zig -OReleaseFast -femit-bin=zig-out/bin/ghost_open_invention_e7
./zig-out/bin/ghost_open_invention_e7
```

## Protocol

1. **Rune forge** — ingest corpus bytes; promote top-recurring adjacent pairs into compound runes
   (400 merges; top-128 runes in the discovery menu). Same ladder as `boundary_crossing/rune_native.zig`.
2. **Grid encoding** — each 8-cell sample → comma-separated digit string (`"2,4,1,0,3,5,2,1,"`).
   Rune feature = substring occurrence count of the rune's byte expansion in that encoding.
3. **Phase 1** — monomial inner-transform forge to saturation (7-target zoo from `unified_invention.zig`).
4. **Phase 2A** — frozen symbolic menu only: argmax spectral / Walsh / Clifford, certify escape
   (held-out ≥0.90, R²<0.40).
5. **Phase 2B** — rune-augmented library: same menu, then argmax over 128 corpus runes on remaining gaps.

## Measured (2026-06-30)

```
Rune forge: 400 promotions on 250000 bytes; top runes: e· th d· ·a in t· er s·

Phase 1 monomial saturation:  5/7
  T5 parity-of-count:  0.513
  T7 sum(g)%7:         0.871

Phase 2A frozen menu:         6/7  (+1)
  T5: 0.513 → 1.000  via spectral (ω≈π)

Phase 2B rune-augmented:      6/7  (+1, same)
  T5: 0.513 → 1.000  via spectral (menu; no rune promotion)
  T7: 0.871 — neither menu nor runes certified

Lift numbers:
  frozen menu Δ:  +0.487 on T5 (0.513→1.000)
  rune-augmented Δ: +0.487 on T5 (identical)
  rune-only delta vs menu: +0 targets
```

| Target | mono | frozen-menu | rune-aug | Δ(menu) | Δ(rune) |
|--------|------|-------------|----------|---------|---------|
| T1 φ{2,5} | 1.000* | 1.000* | 1.000* | 0.000 | 0.000 |
| T2 φ{1,3,6} | 1.000* | 1.000* | 1.000* | 0.000 | 0.000 |
| T3 φ{0,4,5,7} | 0.999* | 0.999* | 0.999* | 0.000 | 0.000 |
| T4 sign(c3) | 1.000* | 1.000* | 1.000* | 0.000 | 0.000 |
| T5 parity | 0.513 | **1.000*** | **1.000*** | **+0.487** | **+0.487** |
| T6 oriented | 1.000* | 1.000* | 1.000* | 0.000 | 0.000 |
| T7 sum%7 | 0.871 | 0.871 | 0.871 | 0.000 | 0.000 |

## Verdict: **FAIL**

Corpus runes add **zero** certified lift beyond the frozen symbolic menu.

- **T5** escapes via handed **spectral** operator (count-Fourier at ω≈π) — the same escape Fork 1 /
  unified_invention already measured. No English bigram (`th`, `in`, `er`, …) certified.
- **T7** remains at 0.871 for mono, menu, and rune-augmented arms. That wall needs **world-pool**
  divisibility (`sum%mod_7`), not text-invented features — consistent with Fork 5.

**Interpretation:** Data-as-outside-generator, with grid→comma-digit encoding and substring-count
features, does **not** invent primitives outside the symbolic menu's span on this battery. The outside
corpus supplies compression units for *language*; grid predicates live in a different feature geometry.
Bridging requires either (a) a learned cross-modal encoder, or (b) rune features defined on a substrate
the corpus actually describes (bytes of grid traces, routing logs, etc.) — not hand-mapped digit strings.

## AGI gap

| Still missing | Why E7 matters |
|---------------|----------------|
| Cross-domain feature ontology | Runes from `train_mix.txt` ≠ grid parity geometry |
| Automatic encoding choice | Comma-digit substring count was imposed, not discovered |
| Escape when menu **and** world pool saturate | T7 needs mod_p, not BPE |
| Quality filter on invented primitives | 128 runes tested; none passed certifier |

## See also

- `boundary_crossing/rune_native.zig` — byte-pair rune forge on raw text
- `inner_forge.zig` / `operator_menu_lib.zig` — monomial saturation + symbolic menu escape
- `unified_invention.zig` — menu + world pool (T7 escape via `sum%mod_7`)
- `parallel_forks_2026.md` — Fork 1 (menu) and Fork 5 (unified loop) baselines