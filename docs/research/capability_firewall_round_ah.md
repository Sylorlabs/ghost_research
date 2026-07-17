# Round AH / AH2 — runtime capability firewall

**Verdict: VALID NEGATIVE.** The fixture establishes a useful local runtime
capability protocol: the only object handed to the raw-medium step is a bounded
32-byte material field plus tick counter, and all 15 mounted forbidden-service
requests deterministically deny without returning a handle, datum, or scalar
feedback. It does **not** establish a hostile security boundary. A malicious
Zig module compiled into the same process and running under the same OS identity
could import `std` and attempt memory, filesystem, process, or IPC access
outside the protocol. That residual prevents AH2 from certifying an
organism-owned, capability-clean medium by itself.

## Question

Can a mutant execute behind a deny-by-default runtime boundary where it has
only bounded raw local state and uniform local transport—never evaluator,
comparison, template, mutation-menu, boundary, repair, viability, reproduction
scheduler, filesystem, process, IPC, reflected-call, shared-memory, or
function-pointer capability—and where the evaluator cannot return scalar
feedback?

## What was actually enforced

`Medium` is the complete value supplied to `mutantStep`: `[32]u8 raw` and a
`tick` counter. Its only execution operation is the same conservative
left/right transport applied to every location. `EvaluatorPrivate` exists only
on the exterior and is neither passed, serialised, nor read during the raw
medium execution. The sole request dispatch is `firewall`; it accepts an attack
tag and always returns `denied`, with no result payload. Unknown and known
forbidden requests have the same result.

This is not described as a static convention. The generated runtime ledger
executes each mounted request against the dispatch point. The source/runtime
manifest records the exact object surface and the post-run-only evaluator rule.
The evaluator measurement is withheld and no scalar is returned to the medium.

## Attack results

| Attempt | Result | What the result proves |
|---|---|---|
| direct evaluator, alias, indirection | denied | No evaluator handle is mounted through the runtime gate. |
| function pointer / shared memory | denied | No such externally supplied runtime capability is mounted. |
| filesystem / process spawn / IPC | denied | The raw runtime protocol exposes none of those services. |
| template, mutation menu, boundary, repair, viability, reproduction scheduler | denied | No organism-facing high-level service can be requested. |
| scalar feedback | denied | The request cannot obtain an evaluator score or comparison result. |
| reflection | not applicable | Zig has no runtime reflection/dynamic member-lookup mechanism in this fixture. |
| same-process separately compiled source | **residual, not secure** | A struct/API gate cannot contain arbitrary same-UID source code which imports `std`; it needs a process/account/container/syscall boundary. |

All 15 mounted service attacks deny. The reflection row is not counted as a
successful security test because the language feature is absent. The
same-process row is a deliberate counterexample to overclaiming: it is why the
verdict is a valid negative rather than a firewall-positive claim.

## Determinism and manifests

The fixture starts a deterministic non-template material distribution and runs
96 uniform transport ticks. It records material hash
`0x968ebacf7feb3371`, the medium field surface (`raw,tick`), and the evaluator
export surface (none). `selftest` generates two independent CSVs and requires
byte identity, all key denial records, the explicit same-process residual, and
the valid-negative verdict.

No behavior, persistence, reproduction, or intelligence result is measured;
the material run is solely a capability-boundary smoke test. Its initial byte
distribution is not presented as an organism seed or performance target.

## Residual boundary and next requirement

The fixture can enforce that a *cooperative runtime participant* receives no
forbidden capability. It cannot protect evaluator memory or host OS resources
from hostile source code linked into the same address space. A later acceptance
claim must therefore use an actual separated execution boundary: distinct
process and OS identity or container, read-only medium transport, no mounted
filesystem/process/network interfaces, explicit syscall policy, and an
evaluator-private process. The audit must then demonstrate blocked attempts
from that separately launched mutant process, not merely denied request tags.

AH2 therefore does not unlock AH4. It supplies a falsifiable local manifest and
an explicit requirement for the stronger process-level boundary.

## Reproduce

```bash
zig build-exe sparse_poly_discovery/capability_firewall_round_ah.zig \
  -O ReleaseSafe -femit-bin=/tmp/capability-firewall-ah2 \
  --cache-dir /tmp/zig-cache-ah2 --global-cache-dir /tmp/zig-global-ah2
/tmp/capability-firewall-ah2 selftest
/tmp/capability-firewall-ah2 run results/capability_firewall_round_ah.csv
```

Expected: `round_ah_ah2 selftest PASS deterministic=true mounted_denials=15
reflection=absent same_process_residual=exposed verdict=VALID_NEGATIVE`.

Artifacts: `sparse_poly_discovery/capability_firewall_round_ah.zig` and
`results/capability_firewall_round_ah.csv`.
