# AGI Final Autonomous

This module implements the recursive code-rewrite loop. It links the `Motor` subsystem to the system compiler via a formal verification gateway.

## Implementation
- `src/body.zig`: The main control loop for the autonomous entity.
- `src/compiler_gateway.zig`: The mandatory safety mechanism that prevents unverified logic from overwriting the live binary.

## Operational Constraints
- The system must satisfy all formal proofs in `native_prover` before `compiler_gateway` allows an atomic file swap.
- The AGI currently operates within a sandbox; direct binary-rewrite permissions are gated by the `CompilerGateway`.
