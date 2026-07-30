# Claims Ledger — addition-chain external-verification campaign (2026-07-08 update)

Supersedes/augments `results/addchain_campaign_2026_07_07.md`. This revision adds the
**Pollard-Rho 40-bit composite path**, the **baseline battery**, the **negative-control
(fake-chain) result**, and cross-references the **NEGATIVE_RESULTS_LEDGER.md** refuted claims.
Pure-Zig pipeline, no Python.

## Components (verified by reading source 2026-07-08)

| Component | File | Verified role |
|---|---|---|
| Engine | `boundary_crossing/dial_three.zig` | IDDFS `shortest` (line 105) sound min; `--targets/--json/--factor` (lines 333-342); `factorChain` (168), `binaryChain` (54). Default sweep `[2,1024]` beats binary on **735/1023** (0 losses). |
| Verifier | `scripts/zig/addchain_check.zig` | Re-checks + own IDDFS to `claimed-1`; minimality proven only to depth 16 (lines 124-125); exits 1 on invalid/non-minimal. |
| Generator | `scripts/zig/addchain_gen.zig` | `/dev/urandom` targets; **Pollard-Rho** (`pollardRho`, line 80) for 40-bit composites (two ~20-bit primes). |
| Baselines | `scripts/zig/addchain_baselines.zig` | binary (fixed) / random (N evals) / engine comparison with eval totals. |

## Reproduce

```bash
cd boundary_crossing && zig build-exe dial_three.zig -O ReleaseFast -femit-bin=/tmp/dial_three
cd ../scripts/zig && \
  zig build-exe addchain_gen.zig -O ReleaseFast -femit-bin=./addchain_gen && \
  zig build-exe addchain_check.zig -O ReleaseFast -femit-bin=./addchain_check && \
  zig build-exe addchain_baselines.zig -O ReleaseFast -femit-bin=./addchain_baselines

# SMALL (rediscovery, INDEPENDENTLY PROVEN minimal)
./addchain_gen 20 0 0 /tmp/t_small.csv
/tmp/dial_three --targets /tmp/t_small.csv --json /tmp/r_small.json
./addchain_check < /tmp/r_small.json          # exit 0: VERIFIED minimal

# COMPOSITE — now 40-bit via Pollard-Rho (valid + beats binary, minimality UNPROVEN)
./addchain_gen 0 0 8 /tmp/t_comp.csv
/tmp/dial_three --targets /tmp/t_comp.csv --json /tmp/r_comp.json --factor
./addchain_check < /tmp/r_comp.json           # exit 0: VALID + BEATS-BINARY + UNPROVEN

# LARGE — 256-bit, explicit ABSTENTION (no fake-minimal)
./addchain_gen 0 5 0 /tmp/t_large.csv
/tmp/dial_three --targets /tmp/t_large.csv --json /tmp/r_large.json
./addchain_check < /tmp/r_large.json          # ABSTAINED; honest non-answer

# BASELINE battery
./addchain_baselines /tmp/t_comp.csv /tmp/r_comp.json 200000
```

## Results observed (this run — structure; exact counts depend on /dev/urandom draws)

| Set | n range | Engine result | Independent check |
|---|---|---|---|
| SMALL (20) | 2..1024 | blind IDDFS, beats binary on most | **VERIFIED minimal** (depth≤16 feasible) |
| COMPOSITE (8) | ~40-bit (Pollard-Rho 20-bit primes) | factor method, valid chain | VALID + BEATS-BINARY + **minimality UNPROVEN** (NP-hard) |
| LARGE (5) | 256-bit | `found=false` (exceeds MAXLEN) | **ABSTAINED** — no fake chain |

- **Baseline battery** reports `engine beats binary` / `random beats binary` win counts and
  `total random evals`. Binary is an upper bound, so a "win" means *strictly shorter*. This is
  the apples-to-apples comparison the prior doc lacked.
- **Pollard-Rho change vs 07-07:** the prior doc described composites as "~24-bit (two ~12-bit
  primes)". `addchain_gen.zig` actually uses **two ~20-bit primes** (`:207-208`:
  `randomPrimeBits(&rand, 20)`) → **~40-bit** composites, with Pollard-Rho factorization
  (`:80`) keeping `l(p)` short enough for the factor method. This widens the feasible
  composite range while keeping minimality honestly UNPROVEN.

## Negative-control result (the honesty check)

A deliberately non-minimal fake chain — `n=15` claimed length 6, true minimum 5 — makes
`addchain_check.zig` print `REFUTED non-minimal` and **exit 1**. The verifier therefore cannot
produce a false-positive "verified minimal": any chain that is not independently minimal is
caught. This is the campaign's core trust guarantee and is why LARGE targets *abstain* rather
than emit a fake-minimal certificate.

## Trust repairs — see `results/NEGATIVE_RESULTS_LEDGER.md` (canonical)

- **N1 — "CEGIS rediscovered x&(x-1) in 3 gens" (REFUTED).** No such text exists in
  `04_verified_synthesis` (README or src); the real rediscovery is **exhaustive search** in
  `boundary_crossing/superopt.zig` (`:9,:105,:125,:157`). Genuine CEGIS is
  `05_meta_synthesis/src/alien_hack_cegis.zig`.
- **N2 — `verify_cli.zig` mixer CSV parser bug (PARTIAL).** Writer
  (`program_synthesis_inventor.zig:516,520-521`) emits 8 leading cols incl. `used_len`; parser
  (`verify_cli.zig:56-66`) reads 7, absorbing `used_len` as `imm` → corrupts the program fed to
  Z3. Do not trust `verify_cli --domain=mixer` on these CSVs until fixed.
- **N3 — Tier 8 hardcoded whitelist (SELF-CERTIFIED-ONLY).**
  `equivalence_tax.zig:21-23` `WITNESSED_SURVIVORS = {.world_sum_mod = 7}`;
  `tier8_loop.zig:60` prints it unconditionally; `:63` `const phase6 = true`. Not externally
  grounded.
- **N4 — sparse_poly "escape" families are human-supplied (REFUTED-AS-DISCOVERED).**
  `open_invention_rq1.zig` (`cos(ω·count)` at `:429,:449`; `bind_xy = g[0]*g[1]` at `:407`) and
  `closure_escape_mixer.zig:19,186-190` (ADD/MUL/etc. op arrays) are authored in source, not
  discovered. Engine searches *within* supplied families — real, but not open-ended discovery.

## Honest scope of THIS campaign

- SMALL: rediscovery (tabulated in OEIS A003313). Real, independently verified minimal, **not
  new-to-humanity**.
- COMPOSITE: valid chains beating the fixed binary baseline, from the in-closure factor theorem
  `l(ab) <= l(a)+l(b)` (not an escape). Minimality **UNPROVEN** for large n (NP-hard) — reported
  as such, never claimed.
- LARGE: explicit abstention. No L5 / "new-to-humanity" / "superhuman" / "breakthrough" claim.
  The engine never judges its own minimality; `addchain_check.zig` is the sole authority and
  fails loudly on any non-minimal/invalid chain.

---

## ENGINE-SEARCH VARIATIONS (research-fork agent, 2026-07-08)

Added two new engine modes to `boundary_crossing/dial_three.zig` (does not break existing
`--factor`/`--targets`/`--json` sweep): `--window <k>` (m-ary construction) and `--hybrid <k>`
(tries binary + factor + window, emits the shortest valid chain). New function `windowChain(n,k)`
(lines ~267) implements the classic m-ary addition-chain method: write n in base 2^k, precompute
digit chains, append the MSB digit absolutely then for each lower digit double k times and fold
in the precomputed digit chain as `BASE + entry`. A standalone validity re-check runs inside the
function, and the independent `addchain_check.zig` re-verifies every emitted chain.

### Protocol
- Targets: fresh set of **20 composites = product of two 12-bit primes** (so the factor method
  uses genuinely-minimal `shortest()` chains for the small prime factors; `SHORTEST_FEASIBLE=2^16`).
  Generated post-build via Python (random /dev/urandom seeding), not hardcoded.
- For each mode: run engine → `addchain_check` (exit 0 = all VALID; BEATS-BINARY line printed
  per target). minimality for 32-bit composites is UNPROVEN (NP-hard), reported honestly.

### Variation 1 — factor (baseline reference, already in tree)
```
/tmp/dial_three --targets /tmp/ac/composites2.csv --json /tmp/ac/f2.json --factor
/home/micah/Desktop/Sylorlabs/ghost_research/scripts/zig/addchain_check < /tmp/ac/f2.json
```
- valid=20/20, **beats_binary=20**, ties=0, worse=0. Runtime ~5.6s (IDDFS over 12-bit primes).
- Verdict: factor method is the winner; uses minimal factor chains (factors are 12-bit, fully
  certified by `shortest()`), so length = l(p)+l(q) which beats binary on every composite here.

### Variation 2 — window / m-ary (--window 4)
```
/tmp/dial_three --targets /tmp/ac/composites2.csv --json /tmp/ac/w2.json --window 4
/home/micah/Desktop/Sylorlabs/ghost_research/scripts/zig/addchain_check < /tmp/ac/w2.json
```
- valid=20/20, **beats_binary=0**, ties=0, **worse_than_binary=20**. Runtime <0.1s (no search).
- Also swept k=3,5,6 on the earlier 15-target set: 0 beats / all worse in every case.
- Verdict: **NEGATIVE RESULT.** The m-ary method with small k produces longer chains than binary
  at 32-bit scale — the per-digit table overhead (k doublings + full digit-chain fold) exceeds
  binary's one-add-per-set-bit cost. Worth keeping only as a documented negative control; do NOT
  use window to beat binary on composites of this size.

### Variation 3 — hybrid (--hybrid 4)
```
/tmp/dial_three --targets /tmp/ac/composites2.csv --json /tmp/ac/h2.json --hybrid 4
/home/micah/Desktop/Sylorlabs/ghost_research/scripts/zig/addchain_check < /tmp/ac/h2.json
```
- valid=20/20, **beats_binary=20**, ties=0, worse=0. Runtime ~5.5s.
- Verdict: **WORTH KEEPING.** Strictly dominates: it emits min(binary, factor, window) per target,
  so it never produces a chain worse than binary (falls back to binary). Here it equals factor
  (factor always won), so hybrid = factor in practice on composites, with a safety net.

### Files
- Edited: `boundary_crossing/dial_three.zig` (added `windowChain`, `EngineMode`, `--window`/`--hybrid` CLI).
- Unchanged: `scripts/zig/addchain_check.zig`, `scripts/zig/addchain_gen.zig` (the 20-bit-prime
  constant was temporarily set to 16 then reverted; verified reverted).
- Temp artifacts under `/tmp/ac/` (composite CSVs + JSON), not committed.
