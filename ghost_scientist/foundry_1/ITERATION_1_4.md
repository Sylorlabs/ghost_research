# Foundry-1.4 process-tree resource-accounting iteration

This iteration replaces direct-child-only accounting with a Linux
process-group meter. It samples every process in the group for CPU ticks and
RSS, charges aggregate reaped-child CPU, enforces wall/CPU/RSS limits, kills
the whole group on timeout, binds stdout and stderr by digest, and verifies
that the group is reaped.

The hostile self-test covers a nested CPU-consuming descendant, an explicit
failure, and a parent plus sleeping descendant killed by a wall limit.
Representative forge, fixed, verifier, TorchInductor, and upstream-corpus
export arms then run under the same meter.

The current environment exposes cgroup v2 but does not allow creating a
private cgroup. The final trial must deny session escape and process creation
where unnecessary, or run this meter inside a writable delegated cgroup.
External controls are not yet executable, so `P3` remains incomplete.

