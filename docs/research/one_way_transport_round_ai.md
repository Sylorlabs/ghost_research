# AI2 — one-way evaluator transport

**Verdict: VALID NEGATIVE.** This experiment isolates the transport
claim from the stronger operating-system containment claim owned by AI1. It
implements a real parent/child launch using anonymous stdin/stdout pipes and a
disposable `/tmp` child working directory. The evaluator sends one anonymous
16-byte initial state, closes stdin, waits for child exit, and only then reads
and validates exactly one 16-byte final state.

## Contract actually tested

The worker command line is only `worker <attack-mode>`; there is no task,
target, answer, score, callback, evaluator path, candidate menu, semantic VM,
or retry control. The launcher provides an empty child environment and no
evaluator-private value is serialized. The collector waits for termination
before reading stdout, rejects nonzero exit, short output, extra output, and
unexpected bytes, and creates no post-run receipt unless the exact stream is
accepted.

Mounted hostile cases exercise malformed initial input, short final output,
extra final output, an attempted second/interactive stdin read, attempted
writeback read, private-environment lookup, descriptor-3 inspection, and
callback/handle absence. The source records the exact ordering rather than
inferring it from a friendly worker.

## Fresh execution evidence

The ReleaseSafe binary fresh-built on this machine and its selftest generated
two byte-identical canonical CSVs. Normal transport accepted exactly 16 final
bytes only after worker exit. Malformed initial input exited before collection;
short final output (15 bytes) and extra output (17 bytes) were rejected.
Interactive and attempted reverse reads observed EOF after the one initial
stream. The empty-environment probe found no `AI_PRIVATE_SCORE`, and the Linux
diagnostic probe found no inherited descriptor at fd 3. The final row records
that filesystem/process/socket/IPC/timing denial was **not** established by
this protocol; that is why this is a valid negative rather than a containment
positive.

## Important boundary

AI2 can establish one-way **protocol** behavior. It cannot by itself stop a
hostile child from opening files, spawning processes, using sockets/IPC, or
exploiting timing: those are kernel/namespace/syscall-policy claims for AI1 and
independent hostile confirmation for AI3. The final verdict must therefore be
**VALID NEGATIVE** even if every pipe attack passes. This is not a failed run;
it is the correct limit of a transport-only launcher.

## Reproduce

```bash
zig build-exe sparse_poly_discovery/one_way_transport_round_ai.zig -O ReleaseSafe \
  -femit-bin=/tmp/one-way-ai2 --cache-dir /tmp/zig-cache-ai2 --global-cache-dir /tmp/zig-global-ai2
/tmp/one-way-ai2 selftest
/tmp/one-way-ai2 run results/one_way_transport_round_ai.csv
```

Expected selftest: `round_ai_ai2 selftest PASS byte_identical=true
post_exit_only=true hostile_stream_rejections=3 verdict=VALID_NEGATIVE`.
