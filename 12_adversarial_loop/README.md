# AGI Autonomy Immune Loop

This module implements the self-preservation mechanism required for autonomous recursive evolution.

## Components
- `src/immune_loop.zig`: The monitoring loop that calculates Vitality and triggers state rollbacks upon divergence detection.
- `domain_agi_snapshot.zig`: Implements persistent system state preservation.
- `domain_agi_adversarial_tester.zig`: Generates adversarial inputs to verify system stability against noise.

## Safety
- If the system vitality drops below the threshold defined by the `Alien Law`, the immune loop triggers an immediate rollback to the latest valid snapshot.
