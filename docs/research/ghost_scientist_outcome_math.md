# Ghost Scientist outcome learning on mathematical programs

**Status: PROSPECTIVE BOUNDED POSITIVE after one preserved prospective
negative.**

Ghost Scientist now constructs exactly one reusable multiplication program for
each visible equation \(x^n\), and its second frozen policy beats a
compute-favored strong fixed portfolio on a fresh 60-target batch. This is real
addition-chain optimization with independently checked programs. It is not a
new mathematical theorem, a proof of globally shortest chains at 24–40 bits,
autonomous invention of primitive semantics, or a general scientist.

## The mathematical artifact

An addition chain for exponent \(n\) is

\[
1=a_0<a_1<\dots<a_k=n,
\]

where every \(a_i\) is the sum of two earlier exponents. It is a reusable
equation-transformation tool: once constructed, the chain computes \(x^n\) for
any \(x\) using exactly \(k\) multiplications. The evaluator sees the complete
chain rather than a scalar score.

The independent verifier does not import candidate code. It checks:

1. one exact protocol line with no extra tokens;
2. start at 1, strict ascending order, and end at the requested \(n\);
3. an earlier-pair addition witness for every step; and
4. execution against binary modular exponentiation for seven bases over six
   modular rings.

The structural check is the mathematical proof for the addition-chain model.
The 42 modular executions are an independent implementation cross-check.

## Prospective discipline

The candidate, evaluator, controls, target generator, budgets, gates, and
containment probe were hash-frozen before each held-out batch existed. The
frozen generator then drew 60 unique 24–40-bit exponents and evaluator seeds
from `/dev/urandom`. All 60 were scored in original order; there was no
mid-run feedback, target exclusion, or early stopping.

The first prospective result was retained as a negative:

| Trial | Learned mechanism | Learned | Strong fixed | Wins / ties / losses | Verdict |
|---|---|---:|---:|---:|---|
| v1 fresh batch | eight exact-digit power-of-two radices | 2338 | 2338 | 0 / 60 / 0 | **FAIL** |
| v2 fresh batch | all-radix exact-chain crossover | **2364** | 2373 | **9 / 51 / 0** | **PASS** |

The v1 target, ledger, summary, and pre-target freezes are independently
attested. That batch became development data only after failure and was never
rescored as held-out.

## What outcomes changed

V1 allocated 3,992 of 4,000 constructions to the inherited
binary/factor/window/stochastic portfolio and eight constructions to exact
digit Horner programs at bases \(2,4,\dots,256\). It won on development data,
but no learned radix was selected on the first fresh batch.

That failure rejected the narrow schedule. Merely searching every radix
2–256 as a standalone replacement also failed on the former held-out batch:
0 wins, 13 ties, 47 losses. The useful outcome was more specific: radix
programs contained intermediate exponents that could repair the inherited
program even when their complete chains were worse.

V2 therefore:

1. builds one inherited chain with 47,745 constructions;
2. constructs exact small chains for every radix and digit in 2–256;
3. unions each radix-Horner chain with the inherited chain;
4. retains 64 promising unions and deletes values made redundant by
   cross-chain witnesses; and
5. emits exactly one final chain.

The hybrid is charged 48,000 constructions. The primary fixed portfolio gets
96,000 constructions—twice the nominal count and more observed development
runtime. On the new prospective batch the nine strict wins use radices:

```text
128, 33, 68, 96, 128, 64, 256, 128, 256
```

This is evidence for outcome-driven grammar revision: failed whole-program
selection led to component crossover and independently generalized. The
revision itself was authored by the research agent; the machine did not invent
the operation alphabet or rewrite semantics from nothing.

## Controls and results

The v2 frozen ledger has 60 rows and 34 fields per row. Every hybrid and
control chain passed independent equivalence verification.

| Policy | Construction allowance | Aggregate chain length |
|---|---:|---:|
| outcome-learned hybrid | 48,000 programs | **2364** |
| strong fixed / no memory / no development-outcome probe | **96,000 programs** | 2373 |
| bounded radix-Horner rewrite saturation | 4,000 programs | 2542 |
| fixed base-64 replay | 1 program | 2523 |
| fixed binary simplification | 1 program | 2787 |
| bounded exact brute force | 4,000 node expansions, then binary fallback | 2787 |
| random backward construction | 4,000 programs, then binary fallback | 2787 |

The equality-saturation row is a bounded saturation/extraction proxy over the
fixed radix-Horner rewrite grammar, not a general external e-graph system. The
brute-force row is intentionally bounded; complete exact search is infeasible
at these widths. Those scopes are part of the frozen protocol and must not be
silently upgraded in later claims.

No-memory and no-probe both remove the outcome-learned crossover and use the
strong 96,000-build fixed portfolio. The hybrid beats that causal ablation
despite receiving half as many nominal constructions.

## Reuse value

Every final chain was executed across the verifier's 42 modular inputs. Reuse
therefore costs:

```text
hybrid:      2364 * 42 = 99,288 multiplications
strong fixed: 2373 * 42 = 99,666 multiplications
saving:                       378 multiplications
```

This demonstrates cheaper reuse. It does not demonstrate a newly reachable
mathematical result: the fixed policies also emit valid chains. The result is
quality/cost improvement, not discovery of an exponentiation capability that
was impossible before.

## Evaluator and containment

One frozen runner now performs:

- source and protocol hash verification;
- fresh build of both candidate stages and every control;
- target uniqueness/range and literal-leak scans;
- evaluator-owned seeds and hidden baseline outcomes;
- exactly one final candidate chain per target;
- independent structural and modular equivalence checking;
- four planted verifier mutations, all rejected;
- inherited-stage and crossover-stage byte-identical replay for all 60 targets;
- resource recount and aggregate gate reduction; and
- an AP-compatible six-class syscall denial probe.

Both candidate stages run separately under Bubblewrap user/PID/IPC/UTS/mount
isolation, `prlimit`, an empty environment/workspace, and their own final
seccomp policy. Fork, open, socket, unshare, signal, and clock probes all
returned `EPERM`.

The current host denies Bubblewrap's `--unshare-net` loopback initialization.
Network syscalls are still denied by candidate seccomp, but this is not the
complete AP network-namespace path. The seccomp policy is default-allow for
unlisted syscalls. Absolute hostile-process containment therefore remains
open.

## Direct answer to the five original gaps

| Gap | Current answer |
|---|---|
| The machine does not choose or construct the tool grammar | **Partially closed.** Per target it constructs and emits one exact chain inside a generic crossover grammar, and outcome failure changed the next generic grammar. The primitive grammar revision was research-agent-authored, not autonomously invented from raw reality. |
| AX has three supplied forms, not 27 inventions | **Closed as an accounting error.** This work claims one inherited constructor form plus one crossover form and 60 generated tool instances—not 60 inventions and never 27 AX inventions. |
| No integrated candidate beats a strong fixed portfolio on held-out real artifacts | **Closed for this bounded math domain.** On fresh post-freeze exponents: 2364 vs 2373, 9 wins / 51 ties / 0 losses, while fixed receives 96k versus hybrid 48k constructions. |
| Synthetic causal learning is not connected to real tool construction | **Bounded connection demonstrated.** A valid prospective failure changed a target-generic program-construction mechanism, which then generalized on a second fresh mathematical batch. The learning loop was agent-mediated, not a self-modifying autonomous scientist. |
| Tool reuse has not shown cheaper or newly reachable discoveries | **Cheaper passed; newly reachable did not.** Forty-two verified reuses save 378 multiplications; all methods remain within known addition-chain mathematics. |
| Evaluator pieces are not one production protocol | **Local production-style protocol passed.** Freeze, generation, containment, controls, verification, mutation, leakage, replay, reuse, and aggregation run together. Full AP network namespaces and a minimal syscall allow-list remain open. |

## Claim boundary

The result supports a narrow thesis: machines can advance AI research by
turning failed prospective outcomes into new executable program-construction
mechanisms, then forcing those mechanisms through stronger compute-favored
controls on fresh problems. That is more than another LLM benchmark, but it is
not autonomous science.

The next serious extension is not a larger language model. It is to transfer
the same freeze → construct → verify → fail → revise → refreeze loop to a
second mathematical domain, such as matrix-expression or attention-kernel
rewrites, with a real external equality-saturation implementation and the full
AP network namespace available.

## Reproduce and audit

Fast immutable outcome audits:

```bash
scripts/verify_ghost_math_prospective_v1_attestation.sh
scripts/verify_ghost_math_prospective_v2_attestation.sh
```

Full deterministic v2 replay over the recorded fresh targets:

```bash
scripts/run_ghost_math_prospective_v2.sh
```

Primary evidence:

- `results/ghost_math_prospective_v1_attestation.txt`
- `results/ghost_math_prospective_v2_attestation.txt`
- `results/ghost_math_prospective_v2.csv`
- `results/ghost_math_prospective_v2.summary.txt`
- `results/ghost_math_candidate_v2_freeze_v4.txt`
- `results/ghost_math_v2_protocol_freeze_v5.txt`
