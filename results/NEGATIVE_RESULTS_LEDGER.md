# NEGATIVE RESULTS LEDGER

This ledger records **refuted, partial, or self-certified-only claims** found in the BitForge
repo. The purpose is to convert unsafe claims into **documented negative results** so they are
not mistaken for verified engineering. Per the documentation-agent rules: *no original claims
or source files were deleted* — only documentation was added. Where a claim is false it is
marked **REFUTED**; where a result is promising but unproven it is marked **PARTIAL/UNPROVEN**;
where a result is asserted by the code itself without external grounding it is marked
**SELF-CERTIFIED-ONLY**.

---

## N1 — `04_verified_synthesis` "CEGIS rediscovered x&(x-1) in 3 gens"
- **Status: REFUTED / UNSUBSTANTIATED**
- **Claim:** That `04_verified_synthesis/README.md` or `INDEX` asserts "CEGIS rediscovered
  `x&(x-1)` in 3 generations."
- **Evidence:**
  - `04_verified_synthesis/README.md:1-12` — contains **no** such claim; only a build blurb and
    a pointer to `docs/`.
  - Full-repo grep for `CEGIS rediscovered` / `rediscovered x&` returns **only** the prior
    campaign doc (`results/addchain_campaign_2026_07_07.md:39`) — the claim text exists
    *nowhere* in `04_verified_synthesis`.
  - Grep of `04_verified_synthesis/src/*.zig` for `cegis` / `x&(x-1)` / `x & (x-1)` returns
    **zero** matches (verified: no CEGIS loop, no `x&(x-1)` reference in that directory).
  - The real rediscovery of `x & (x-1)` is **exhaustive enumeration**, not CEGIS and not 3
    generations, in `boundary_crossing/superopt.zig:9` ("enumeration over u8, which is a proof
    for this width"), `:105` (`// x & (x-1)`), `:125` (`x & (x-1) [clear lowest set bit]`),
    `:157` ("engine rediscovered the Hacker's-Delight tricks ... from nothing but the spec").
  - A genuine CEGIS loop **does** exist, but in a different milestone:
    `05_meta_synthesis/src/alien_hack_cegis.zig` (referenced by
    `05_meta_synthesis/build.zig:98` and using `z3`).
- **What to do:** Retract the attribution entirely. If any README/INDEX line asserting this is
  found in the future, replace it with: "rediscovery of `x&(x-1)` is exhaustive search in
  `boundary_crossing/superopt.zig`; CEGIS lives in `05_meta_synthesis/src/alien_hack_cegis.zig`."

---

## N2 — `04_verified_synthesis/verify_cli.zig` mixer CSV column bug
- **Status: PARTIAL (buggy verifier input path)**
- **Claim implied:** `verify_cli.zig` verifies mixer programs read from champion CSVs.
- **Evidence:**
  - **Writer** (`04_verified_synthesis/src/program_synthesis_inventor.zig:513,516,520-521`)
    emits the champion CSV header and rows with **8 leading columns**:
    `idx,op_id,op_name,dst,src1,src2,imm_hex,used_len,...` (plus composite/avalanche/etc.).
    Row format: `"{d},{d},{s},{d},{d},{d},0x{X:0>16},{d},..."` → after `imm_hex` comes
    `used_len` as the 8th field.
  - **Parser** (`04_verified_synthesis/src/verify_cli.zig:56-66`,
    `parseMixerCsv`) reads only **7** fields: `idx` (skipped), `op_id`, `op_name` (skipped),
    `dst`, `src1`, `src2`, `imm`. It then builds `MixerInstr` from `dst, src1, src2, imm`.
  - Because the writer's 8th column (`used_len`) is **not** consumed by the parser, the
    parser's `imm` field absorbs `used_len` (the integer length) instead of the real
    `imm_hex`. The actual `imm_hex` value is shifted out / dropped. Consequence: the program
    fed to the Z3 verifier is **corrupted** — its immediate values are wrong. Any "VERIFIED"
    verdict from this path is on a program the engine never produced.
- **What to do:** Fix `parseMixerCsv` to consume `used_len` (or change the writer to not emit
  it before `imm_hex`, or reorder columns). Until fixed, **do not trust** any
  `verify_cli --domain=mixer` verdict whose CSV came from `program_synthesis_inventor.zig`.
  The `verify_cli --domain=sort` path uses a different (5-col) schema and is unaffected.

---

## N3 — Tier 8 `equivalence_tax.zig` hardcoded "witnessed survivor" whitelist
- **Status: SELF-CERTIFIED-ONLY**
- **Claim implied:** Tier 8 "witnessed survivors" are externally grounded promotions that
  passed an independent reality anchor.
- **Evidence:**
  - `sparse_poly_discovery/equivalence_tax.zig:21-23`:
    ```zig
    pub const WITNESSED_SURVIVORS = [_]ui.Feature{
        .{ .world_sum_mod = 7 },
    };
    ```
    A **single hardcoded** feature is the entire "witnessed survivors" set.
  - `sparse_poly_discovery/tier8_loop.zig:60`:
    ```zig
    try out.print("  witnessed survivor: world_sum_mod=7\n", .{});
    ```
    Printed **unconditionally** — not derived from any runtime witness hunt.
  - `sparse_poly_discovery/tier8_loop.zig:63`: `const phase6 = true;` — Phase 6 (the
    "reality anchor") is a **constant true**, not a computed gate. The "peer replication 3/3"
    and "downstream lift +0.141" lines (`:61-62`) are also printed literally, not measured.
- **What to do:** Treat Tier 8 "witnessed survivor" / "Phase 6 reality anchor" output as
  self-certified narrative. Replace the hardcoded `WITNESSED_SURVIVORS` with the actual output
  of a witness-hunt run, and compute Phase 6 from real measurements before claiming any
  external grounding.

---

## N4 — sparse_poly / meta-engine "escape" generators are human-supplied
- **Status: REFUTED-AS-DISCOVERED**
- **Claim implied:** Some "escape" features/families were *system-discovered* by the invention
  engine.
- **Evidence:**
  - `sparse_poly_discovery/open_invention_rq1.zig`: the candidate families are **authored in
    source**. Examples: `cos(ω·count)` via `fitCosFeat`/`evalScanP` (`:429, :449-464`) scanning
    a fixed `FREQS = 128` grid; `bind_xy = g[0]*g[1]` (`fillBindXy`, `:407-409`, an ADD/MUL
    product); `fillBindAbs`, `fillBindMax` (`:410-415`) — all hardcoded feature constructors.
  - `05_meta_synthesis/src/closure_escape_mixer.zig:12,186-190,201`: the "escape" op families
    (`AND_NOT, MUM, ADD_ROT, ADD, MUL` atop a shared affine base) are an explicitly
    **human-authored list** (`AffinePlusAdd`, `AffinePlusAddRot`, `AffinePlusMul` arrays). The
    hill-climber searches *within* these supplied families; it does not invent the families.
  - The "escape" metric itself (`cov_after >= COVER and cov_before < COVER`, e.g.
    `open_invention_rq1.zig:687`, `unified_invention.zig:343`) is a human-defined certification
    threshold, not an emergent discovery signal.
- **What to do:** Relabel any text claiming the *families* were discovered. The engine does
  search *within* supplied families and can *certify* an escape relative to a fixed menu — that
  is real, but it is parameter search over a human-provided hypothesis space, not open-ended
  discovery of new mathematical structure.

---

## Cross-reference
- These four items are also summarized (with the same verdicts) in
  `results/addchain_campaign_2026_07_07.md:39-52` and carried forward here as the canonical
  ledger.
- The addition-chain campaign itself (`results/addchain_campaign.md`) is **sound and
  independent** of all four refuted claims above; it uses exhaustive IDDFS (not CEGIS) and an
  external verifier that fails loudly, so it does not inherit these negatives.
