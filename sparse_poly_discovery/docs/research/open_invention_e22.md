# E22 — Corpus runes v2 (execution traces)

**Question:** Do rune features forged from **terminal execution traces** invent grid primitives
beyond the frozen symbolic menu on the Boolean/zoo battery — especially on **T5** (parity) and
**T7** (sum%7)?

**Key file:** `sparse_poly_discovery/open_invention_e22.zig`  
**RNG seed:** `0xE7C0FF01CEE7` (same grid zoo as E7 for direct comparison)  
**Pass bar:** ≥**+0.15** held-out lift on **T5 or T7** (`rune-aug` − `frozen-menu`)

## Reproduce

```bash
cd sparse_poly_discovery
zig build open-invention-e22 --release=fast
# simulated traces (no shell):
zig build open-invention-e22 --release=fast -- --sim
```

## Protocol

1. **Terminal grind** — run **200** safe whitelisted commands live (`sh -c`); record per-run
   trace bytes: `>cmd\n!exit\nt{ms}\n#stdout\n$stderr\n` (patterns from `terminal_grind_big.zig`,
   `open_invention_e18.zig`).
2. **Rune forge** — byte-pair promotion ladder on trace corpus (400 merges; top-128 runes;
   same as `boundary_crossing/rune_native.zig` / E7).
3. **Grid encoding** — each 8-cell sample → comma-separated digit string; rune feature =
   substring occurrence count in that encoding (E7 protocol).
4. **Phase 1** — monomial inner-transform forge to saturation (7-target zoo).
5. **Phase 2A** — frozen symbolic menu only (spectral / Walsh / Clifford).
6. **Phase 2B** — rune-augmented library: menu first, then argmax over 128 trace runes.

## Measured (2026-06-30, live shell)

```
Phase 0 terminal grind:  200 commands (140 exit_ok); trace corpus 35630 bytes
Rune forge:              400 promotions; top runes: es co ar h/ zi zig ho .zig

Phase 1 monomial saturation:  5/7
  T5 parity-of-count:  0.513
  T7 sum(g)%7:         0.871

Phase 2A frozen menu:         6/7  (+1)
  T5: 0.513 → 1.000  via spectral

Phase 2B rune-augmented:      6/7  (+1, identical)
  T5: 0.513 → 1.000  via spectral (menu; no rune promotion)
  T7: 0.871 — neither menu nor trace runes certified

T5/T7 rune-aug vs frozen-menu lift:
  T5: +0.000  (menu already at 1.000)
  T7: +0.000  (stuck at 0.871)
```

| Target | mono | frozen-menu | rune-aug | Δ(menu) | Δ(rune vs menu) |
|--------|------|-------------|----------|---------|-----------------|
| T1 φ{2,5} | 1.000* | 1.000* | 1.000* | 0.000 | 0.000 |
| T2 φ{1,3,6} | 1.000* | 1.000* | 1.000* | 0.000 | 0.000 |
| T3 φ{0,4,5,7} | 0.999* | 0.999* | 0.999* | 0.000 | 0.000 |
| T4 sign(c3) | 1.000* | 1.000* | 1.000* | 0.000 | 0.000 |
| T5 parity | 0.513 | **1.000*** | **1.000*** | **+0.487** | **+0.000** |
| T6 oriented | 1.000* | 1.000* | 1.000* | 0.000 | 0.000 |
| T7 sum%7 | 0.871 | 0.871 | 0.871 | 0.000 | 0.000 |

```
E22_RESULT pass=false t5_lift=0.000 t7_lift=0.000 menu_solved=6 rune_solved=6
```

## Verdict: **FAIL**

Trace runes add **zero** lift beyond the frozen symbolic menu on T5/T7.

- **T5** still escapes only via handed **spectral** (count-Fourier at ω≈π) — same as E7. Top
  trace runes (`es`, `co`, `ar`, `h/`, `zi`, `zig`, `.zig`) are path/stdout fragments from
  `ls`/`wc`/`stat` probes; none certified on grid comma-digit encoding.
- **T7** remains at **0.871** for mono, menu, and rune-augmented arms. World-pool divisibility
  (`sum%mod_7`) is outside both the symbolic menu and trace-substring features.

**Interpretation:** Switching the outside generator from English text (E7) to **live execution
traces** (E22) does not bridge to grid predicate geometry under the E7 substring-count readout.
The traces describe *shell I/O*, not *8-cell value patterns*. E7's doc predicted this: rune
features must be defined on a substrate aligned with the target domain — traces help terminal
grounding (E8), not comma-digit grid parity/mod without a learned cross-modal encoder.

## AGI gap

| Still missing | Why E22 matters |
|---------------|-----------------|
| Cross-modal trace→grid encoder | Trace bigrams ≠ parity/sum%7 geometry |
| Escape when menu saturates T5 | Spectral still the only T5 certifier |
| T7 world-pool without mod_p injection | Trace runes cannot invent mod arithmetic |
| Automatic feature readout choice | Substring count on digit string still imposed |

## See also

- `open_invention_e7.md` — text corpus runes (same FAIL pattern)
- `boundary_crossing/open_invention_e8.md` — terminal grounding on *action*, not grid
- `boundary_crossing/terminal_grind_big.zig` — 200-command grind patterns
- `boundary_crossing/rune_native.zig` — byte-pair rune ladder
- `unified_invention.zig` — T7 escape via world pool `sum%mod_7`