# AGI Grounded Causality (The World Engine)

This module implements a non-deterministic world simulator used to ground the AGI's bit-level cognition into causal action-effect relationships.

## Implementation
- `src/physics_synthesis.zig`: Executes the 'Causal Inference Domain' where the machine models state transitions.
- `domain_agi_causality.zig`: Defines the 'World Engine' physics, mapping bit-vector actions to state-vector changes under probabilistic noise.

## Causal Inference
- The AGI is tasked with minimizing prediction error between $P(state_{t+1})$ and $actual\_state_{t+1}$, forcing it to learn a predictive causal model rather than mere pattern matching.
