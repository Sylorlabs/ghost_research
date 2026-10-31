# Claims Ledger — addition-chain external-verification campaign (2026-07-07)

Pure-Zig pipeline, no Python. Engine: `boundary_crossing/dial_three.zig` (patched with
`--targets/--json/--factor` modes). Independent verifier: `scripts/zig/addchain_check.zig`.
Target generator: `scripts/zig/addchain_gen.zig` (reads `/dev/urandom`).

## Reproduce

```bash
# engine (compile to a fixed path; `zig build dial-three` only runs the sweep step)
cd boundary_crossing && zig build-exe dial_three.zig -O ReleaseFast -femit-bin=/tmp/dial_three
# tools
cd ../scripts/zig && zig build-exe addchain_gen.zig -O ReleaseFast && zig build-exe addchain_check.zig -O ReleaseFast

# SMALL targets (n<=1024, OEIS A003313 range) — minimality INDEPENDENTLY PROVEN
./addchain_gen 20 0 0 /tmp/t_small.csv
/tmp/dial_three --targets /tmp/t_small.csv --json /tmp/r_small.json
./addchain_check < /tmp/r_small.json        # exit 0, all VERIFIED minimal

# COMPOSITE targets (product of two ~12-bit primes, ~24-bit n) — valid + beats binary,
# minimality UNPROVEN (NP-hard; blind IDDFS infeasible past depth 16)
./addchain_gen 0 0 8 /tmp/t_comp.csv
/tmp/dial_three --targets /tmp/t_comp.csv --json /tmp/r_comp.json --factor
./addchain_check < /tmp/r_comp.json        # exit 0, all VALID + BEATS-BINARY + UNPROVEN
```

## Results observed (this run)

| Set | n range | Engine result | Independent check |
|---|---|---|---|
| SMALL (20) | 2..1024 | blind IDDFS, beats binary on most | VERIFIED minimal (IDDFS to depth<=16 feasible) |
| COMPOSITE (8) | ~24-bit | factor method, len 29-31 | VALID + BEATS-BINARY (7/8) + minimality UNPROVEN |

Refutation test: feeding a non-minimal fake chain (n=15 claimed len 6, true min 5) →
`addchain_check` exits 1, prints "REFUTED non-minimal". The verifier is sound.

## Trust repairs (documented negative results — NOT deleted)

- `04_verified_synthesis` README/INDEX claim "CEGIS rediscovered x&(x-1) in 3 gens":
  REFUTED. No CEGIS in `04_verified_synthesis/src/`; the real rediscovery is exhaustive
  search in `boundary_crossing/superopt.zig` (not CEGIS, not 3 gens). Genuine CEGIS lives
  in `05_meta_synthesis/src/alien_hack_cegis.zig`. → Retract the attribution.
- `04_verified_synthesis/verify_cli.zig` mixer CSV parser: PARTIAL/buggy. Writer emits 8
  leading cols; `parseMixerCsv` reads 7, absorbing `used_len` as `imm_hex` → verifies a
  corrupted program. → Fix or annotate before trusting any VERIFIED output.
- Tier 8 `equivalence_tax.zig:21-23`: `WITNESSED_SURVIVORS = {.world_sum_mod = 7}` — a
  hardcoded whitelist. `tier8_loop.zig:60` prints "witnessed survivor: world_sum_mod=7"
  unconditionally; Phase 5 uses `.approved=true`; Phase 6 is `const true`. → Self-certified
  only; not externally grounded.
- sparse_poly / boundary_crossing escape generators: every "escape" is a HUMAN-SUPPLIED
  opcode family (cos(ω·count), ADD/MUL) or human-authored list, not system-discovered.
  Labeled REFUTED-as-discovered.

## Honest scope of THIS campaign

- SMALL targets: rediscovery (l(n) tabulated in OEIS). Real machine result, independently
  verified minimal, but NOT new-to-humanity.
- COMPOSITE targets: valid chains that beat the fixed binary-method baseline, found by an
  in-closure factor heuristic (theorem l(ab)<=l(a)+l(b), not an escape). Minimality is
  UNPROVEN for large n (NP-hard) — reported as such, never claimed.
- No L5 ("new-to-humanity") claim is made. The pipeline is the trustworthy substrate: the
  engine never judges its own minimality; `addchain_check.zig` is the sole authority and
  itself fails loudly on any non-minimal/invalid chain.
