# Disclaimer — Thread 04: Program Synthesis + DomainSpec

**This is the first thread with fully verifiable results.** All claims here
are backed by real Z3 SMT proofs and real PractRand test output.

## What was true when written (and remains true)

- DomainSpec comptime-generic engine produces INVENTION (strict) in u64-mixer, sort-net,
  and boolean domains — same binary, three structurally different domains
- 20/20 inventor runs at depth 5 produce strict invention; 190 champion pairs are
  mutually peer-distant
- Z3 verification is real (`verify_cli` replaced the hardcoded `SMT_VERIFIED_FOUNDATIONAL_TRUTH`
  string that a prior agent had hardcoded — that lie is documented in `verify_cli.md`)
- Discovered u64 mixers score higher than splitMix64 on composite fitness

## What was discovered in later threads

- **Bijectivity is not enforced.** The gen_0 mixer has SPLITMIX_STEP self-feedback and
  is non-bijective at 8 and 16 bits. This was discovered in Thread 05 when Z3 was
  first applied to mixer champions.
- **44.30 was not the ceiling.** Thread 05 broke it to 47.32 via monotone-retry + LMG.
- **Sorting strict domination** required switching `depth()` to logical-composition mode —
  discovered in Thread 05's successor chain work.
