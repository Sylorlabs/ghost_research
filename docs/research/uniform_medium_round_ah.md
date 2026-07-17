# Round AH / AH1 — uniform capability-free medium

**Verdict: VALID NEGATIVE (infrastructure pass).** This experiment establishes a
small uniform medium that admits raw matter but blocks all seven deliberately
requested human-facing capabilities before a world exists. It does not claim
that a persistent organism, criterion, or intelligence has formed.

## Question

Can a raw finite particle field run without exposing a score, target, decoder,
observation/action interface, organism boundary, template, repair service,
candidate grammar, reproduction routine, or scheduler to the matter?

## Medium and exclusion boundary

There are 24 independent 31×29 toroidal fields. `Matter` is an anonymous
unsigned quantity: it has no ID, owner, tag, callback, function pointer,
boundary, behavior, or reference to host storage. On each of 192 ticks every
location executes the same `localLaw`: half its quantity moves east and the
remainder south. This is the entire runtime transition. It neither reads time,
cohort, policy, evaluator data, nor a special address. Total material is
checked externally after each tick and the evaluator serializes its report
only after a completed run; no result is fed into the field.

The admission firewall runs *before* field allocation. Hostile requests for a
score, decoder, seed/template, candidate builder, repair service, boundary
tag, or scheduler all produce `blocked`, zero charged ticks, and zero material.
Thus they cannot be merely unused capabilities hidden behind an unreachable
branch. The fixed-template row is deliberately admitted only as an exterior
negative control: it shows why a host-written initial arrangement is not an
organism-owned seed.

## Results

| Condition | Admission | Charged ticks | Material conserved | Finding |
|---|---|---:|---:|---|
| raw random matter | admitted | 4,608 | yes | uniform medium executes; no organism claim |
| static equal-material | admitted | 4,608 | yes | transport control |
| random equal-material | admitted | 4,608 | yes | independent random control |
| fixed host template | admitted | 4,608 | yes | explicitly exterior-only negative control |
| score / decoder / template / candidate / repair / boundary / scheduler leaks | **blocked 7/7** | **0 each** | n/a | firewall pass |

Fresh compilation runs `selftest`, emits two CSVs, and compares them
byte-for-byte. It also requires conservation for the clean run and requires
all seven hostile leaks to be rejected prior to allocation.

## What this proves and does not prove

It proves a capability-exclusion mechanism: the raw field has no supplied
organism-level service under the listed attack paths, and all sites have one
identical local transition. It does **not** prove that the exterior physical
law is discovered, that the random initialization is non-human, or that a
self-maintaining organization arose. Those are residual exterior physics:
finite grid topology, the uniform east/south transport law, a run length, and
an externally chosen random distribution. The correct label remains valid
negative until a separately audited birth experiment shows persistence and
recovery better than equal-material controls without smuggling a template.

## Reproduce

```bash
mkdir -p /tmp/zig-cache-ah1 /tmp/zig-global-ah1
zig build-exe sparse_poly_discovery/uniform_medium_round_ah.zig \
  -femit-bin=/tmp/uniform-medium-ah1 --cache-dir /tmp/zig-cache-ah1 \
  --global-cache-dir /tmp/zig-global-ah1
/tmp/uniform-medium-ah1 selftest
/tmp/uniform-medium-ah1 run results/uniform_medium_round_ah.csv
```

Expected: `round_ah_ah1 selftest PASS verdict=VALID_NEGATIVE deterministic=true
uniform_local_law=true forbidden_leaks_blocked=7/7 evaluator_postrun_only=true`.
