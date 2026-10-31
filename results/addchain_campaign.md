# Addition-Chain External-Verification Campaign — Full Documentation

**Pure-Zig pipeline, no Python.** This campaign turns the "third dial" (point a certified
search loop at a genuine unknown) on the classic shortest-addition-chain problem, with an
*independent* verifier as the sole authority on minimality. The engine never judges its own
correctness; the verifier fails loudly (exit 1) on any invalid or non-minimal chain.

Components (all verified by reading source):

| Component | File | Role |
|---|---|---|
| Engine (search + candidate generation) | `boundary_crossing/dial_three.zig` | Iterative-deepening DFS that certifies `l(n)` (sound minimum); `--targets/--json/--factor` modes; `factorChain`/`binaryChain` helpers |
| Independent verifier | `scripts/zig/addchain_check.zig` | Re-checks every chain, proves minimality up to depth 16, exits 1 on any invalid/non-minimal result |
| Target generator | `scripts/zig/addchain_gen.zig` | Targets from `/dev/urandom` (SMALL/LARGE/COMPOSITE); Pollard-Rho for 40-bit composites |
| Baseline battery | `scripts/zig/addchain_baselines.zig` | binary (fixed) / random search / engine comparison with eval counts |

---

## 1. What was built

### 1.1 Engine — `boundary_crossing/dial_three.zig`
- Default sweep (no args): certifies `l(n)` for every `n` in `[2, 1024]`, prints how many
  values **strictly beat** the naive binary-method baseline (`floor(log2 n) + popcount(n) - 1`).
  The engine is a complete iterative-deepening DFS (`shortest`, line 105) with an admissible
  doubling-bound prune; the first depth that succeeds is the **true minimum `l(n)`** — a proof
  at this scale. Every chain is re-checked by an in-file `verify` (line 123), and the engine
  does **not** assert "CERTIFIED" to the verifier — `addchain_check.zig` is the only authority.
  Empirical result of the default sweep, as recorded in the prior campaign doc
  (`results/addchain_campaign_2026_07_07.md:31`): the engine beats binary on **735/1023**
  values, with 0 losses (binary is an upper bound, never optimal-beating).
- `--targets <csv> --json <out>`: reads a CSV of targets (one `n` per line, optionally
  `n,label`), searches each, emits machine-readable JSON `{results:[...]}`. If the search
  exceeds `MAXLEN` (80), it reports `found=false` — an explicit **abstention**, never a
  fake-minimal chain (lines 250-315).
- `--factor`: uses `factorChain` (line 168) — an in-closure heuristic exploiting
  `l(ab) <= l(a) + l(b)`. This is explicitly **not** claimed minimal; it only supplies a
  candidate the blind IDDFS cannot reach on large composites. `binaryChain` (line 54) supplies
  a constructive binary-method chain for factors too large for `shortest()`.

### 1.2 Independent verifier — `scripts/zig/addchain_check.zig`
- For every result where `found==true`:
  1. Re-verifies validity (strictly ascending, each entry a sum of two priors, ends at `n`).
  2. Runs its **own** IDDFS to depth `claimed_len - 1`. If any valid chain is found, the
     engine's claimed length is **not minimal** → REFUTED.
- **Minimality proof is capped at depth 16** (`addchain_check.zig:124-125`). Below that,
  minimality is *independently proven*. Above that (NP-hard, infeasible blind IDDFS), it
  reports `VALID ... minimality=UNPROVEN` — an honest non-claim, not a fake proof.
- Exit codes: `0` = all checked results valid (and minimal where depth≤16); `1` = at least one
  invalid/non-minimal; `2` = usage/parse error.
- **Negative control**: a deliberately non-minimal fake chain (`n=15` claimed length 6, true
  minimum 5) causes the verifier to print `REFUTED non-minimal` and exit 1. This proves the
  verifier will catch a fabricated "minimal" chain — the engine cannot self-certify a lie.

### 1.3 Target generator — `scripts/zig/addchain_gen.zig`
- Reads `/dev/urandom` so targets postdate the build and **cannot be hardcoded** in any engine
  source. Three separable kinds in the CSV:
  - `SMALL` — random `n` in `[2, 1024]` (OEIS A003313 range → rediscovery control).
  - `LARGE` — random 256-bit `n` (not tabulated → genuine unknown; engine abstains).
  - `COMPOSITE` — product of two ~20-bit primes (~40-bit `n`); Pollard-Rho factorization
    (`pollardRho`, line 80) so the factor method stays feasible (`l(p)` for a 20-bit prime is
    short). We do not precompute or know `l(n)`; the engine supplies it.

### 1.4 Baseline battery — `scripts/zig/addchain_baselines.zig`
- For each target: binary method (fixed, 0 evals), random search (N random valid chains,
  reports best length + total eval count), and engine length (from a precomputed engine JSON).
- Reports aggregate win counts (`engine beats binary`, `random beats binary`) and total random
  evals. Honest framing: binary is an upper bound, so a "win" only means *strictly shorter*.

---

## 2. Exact reproduce commands

```bash
# ---- Build (compile to fixed paths) ----
cd boundary_crossing && \
  zig build-exe dial_three.zig -O ReleaseFast -femit-bin=/tmp/dial_three
cd ../scripts/zig && \
  zig build-exe addchain_gen.zig -O ReleaseFast -femit-bin=./addchain_gen && \
  zig build-exe addchain_check.zig -O ReleaseFast -femit-bin=./addchain_check && \
  zig build-exe addchain_baselines.zig -O ReleaseFast -femit-bin=./addchain_baselines

# ---- Default sweep (certify l(n) for every n in [2,1024]) ----
/tmp/dial_three        # prints beats-binary count, champion, showcase; all chains independently verified

# ---- SMALL targets: rediscovery + INDEPENDENTLY PROVEN minimal ----
./addchain_gen 20 0 0 /tmp/t_small.csv
/tmp/dial_three --targets /tmp/t_small.csv --json /tmp/r_small.json
./addchain_check < /tmp/r_small.json        # exit 0: VERIFIED minimal, depth<=16 feasible

# ---- COMPOSITE targets: valid + beats binary, minimality UNPROVEN ----
./addchain_gen 0 0 8 /tmp/t_comp.csv
/tmp/dial_three --targets /tmp/t_comp.csv --json /tmp/r_comp.json --factor
./addchain_check < /tmp/r_comp.json         # exit 0: VALID + BEATS-BINARY + minimality UNPROVEN

# ---- LARGE targets: 256-bit, engine abstains (honest non-answer) ----
./addchain_gen 0 5 0 /tmp/t_large.csv
/tmp/dial_three --targets /tmp/t_large.csv --json /tmp/r_large.json
./addchain_check < /tmp/r_large.json        # ABSTAINED entries; no fake-minimal reported

# ---- Baseline battery ----
./addchain_baselines /tmp/t_comp.csv /tmp/r_comp.json 200000
```

---

## 3. Honest scope of results

| Set | n range | Engine result | Independent check |
|---|---|---|---|
| SMALL (20) | 2..1024 | blind IDDFS, beats binary on most | **VERIFIED minimal** (IDDFS depth≤16 feasible) |
| COMPOSITE (8) | ~40-bit (20-bit primes) | factor method, valid chain | VALID + BEATS-BINARY + **minimality UNPROVEN** (NP-hard; depth>16) |
| LARGE (256-bit) | 2^256 | `found=false` (exceeds MAXLEN) | **ABSTAINED** — explicit non-answer, no fake chain |

- **SMALL = rediscovery.** `l(n)` for small `n` is tabulated in OEIS A003313 (known to
  humanity). The engine produces a *real machine result*, independently verified minimal, but
  it is **not new-to-humanity**. This demonstrates the *mechanism* of invention (undirected,
  certified, not recalled, beats a fixed algorithm) — the honest contribution.
- **COMPOSITE = valid + beats-binary + UNPROVEN.** Found by an in-closure factor heuristic
  (theorem `l(ab) <= l(a)+l(b)`), not an "escape". Minimality is **not provable** by blind
  IDDFS at these lengths (NP-hard). Reported as such; never claimed minimal.
- **LARGE = abstain.** 256-bit targets exceed `MAXLEN`. The engine emits `found=false` and the
  verifier counts it as an honest abstention. **No fake-minimal chain is ever emitted.**
- **No L5 / "new-to-humanity" / "superhuman" / "breakthrough" claim is made.** The pipeline is
  the trustworthy substrate: the engine never judges its own minimality, and `addchain_check.zig`
  is the sole authority and itself fails loudly on any invalid/non-minimal input.

---

## 4. Negative-control result (the important honesty check)

The verifier contains a deliberate falsification path: feeding a non-minimal fake chain
(`n=15`, claimed length 6, true minimum 5) makes `addchain_check.zig` print
`REFUTED non-minimal` and **exit 1**. This confirms the verifier will reject a fabricated
"minimal" certificate. The campaign therefore cannot produce a false-positive "verified
minimal" result — any chain that is not independently minimal is caught and flagged.

---

## 5. Relationship to other repo claims (see NEGATIVE_RESULTS_LEDGER.md)

This campaign is **self-contained and sound**. It does NOT rely on the refuted "CEGIS
rediscovered x&(x-1)" claim or the other unsafe claims documented in
`results/NEGATIVE_RESULTS_LEDGER.md`. The rediscovery mechanism here is exhaustive
iterative-deepening (in `boundary_crossing/superopt.zig` and `dial_three.zig`), which is a
genuine sound proof at small scale — distinct from any CEGIS attribution.
