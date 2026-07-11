# LM baseline — an LLM as addition-chain generator, gated by the same verifier

**Status:** harness built, **not yet run** (running makes live `claude` CLI calls).
`scripts/zig/lm_baseline.zig`; build `zig build-exe lm_baseline.zig -O ReleaseFast`;
run `./lm_baseline <targets.csv> [addchain_check_bin] [claude_bin]`.

## Why this exists (the AlphaEvolve head-to-head, made honest)

The addition-chain campaign (`results/addchain_campaign_2026_07_07.md`,
`addchain_v2.md`) established the pure-Zig engine's yield on random targets,
every chain forced through the independent verifier `scripts/zig/addchain_check.zig`.
The standing question for the "better than AlphaEvolve" north star is a *direct*
one: AlphaEvolve is an **LLM proposer + a verifier**. So how does an LLM proposer,
gated by *our* sound verifier, compare to the engine on the *same* targets?

This harness answers it apples-to-apples. It is the fair baseline: put an LLM in
the exact role AlphaEvolve uses it for (propose a candidate), and hold it to the
exact standard the engine is held to (independent verification, never the
proposer's self-report).

## What it does

For each target `n` in a CSV:
1. Shell out to `claude -p "<addition-chain prompt for n>"` (non-interactive).
2. Extract the first balanced JSON integer array from the reply (the proposed
   chain) — the LLM's prose and self-assessment are discarded.
3. Wrap it as an `addchain_check` record and pipe it to the **independent
   verifier** — the same binary the engine's chains go through.
4. Parse the verifier's verdict: VALID? minimal (`VERIFIED minimal` vs
   `minimality=UNPROVEN`)? BEATS-BINARY? REFUTED? Tally.

Cost is measured honestly in **API calls (1 per target)** and wall time — the
resource axis that matters for the comparison, since the engine's cost is
CPU-seconds. If the `claude` CLI is unavailable or the subprocess fails (rate
limit, auth), the harness reports **"LLM unavailable"** for that target as an
honest non-answer and continues — it never crashes and never counts an
unverified LLM claim as a solve.

## The comparison it is designed to make (when run)

| axis | pure-Zig engine (`dial_three`/`addchain_v2`) | LLM baseline (this harness) |
|------|----------------------------------------------|------------------------------|
| proposer | IDDFS / window / factor / stochastic search | `claude -p` (one call per target) |
| verifier | `addchain_check` (independent, sound) | `addchain_check` (**same** binary) |
| trust model | never trust proposer's "minimal" | never trust LLM's "minimal" |
| cost unit | CPU-seconds | API calls + wall time |
| honest failure | UNPROVEN / no-beat | "LLM unavailable" / REFUTED / no-beat |

The point is not to make the LLM look bad or good — it is to have the **fair,
verifier-gated number** so the engine's yield (52/60 beat the classical stack at
40-bit, minimality proven ≤16384; `addchain_v2.md`) can be stated *relative to an
LLM proposer under identical verification*, not in a vacuum.

## Honest status

- **Built, not run here.** No results are claimed. Running it consumes live
  `claude` CLI calls; that is the user's call (cost + rate limits).
- It is distinct from `llm_proposer.md` (Claude proposing number-theoretic
  *predicate* generators) — this one is specifically the addition-chain
  generator baseline against `addchain_check`.
- When run, results belong in `results/lm_baseline_<date>.csv` and a verdict
  section here, with the per-target verifier tally and the API-call/wall-time
  cost beside the engine's CPU-seconds.

## Files
- `scripts/zig/lm_baseline.zig` — the harness
- Verifier reused unmodified: `scripts/zig/addchain_check.zig`
- Related: [[llm_proposer]] (LLM proposing predicate generators, a different task),
  `addchain_v2.md` (the engine's side of the comparison).
