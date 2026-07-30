# Ghost Scientist Tensor v4

Tensor v4 tests machine-generated conditional tensor rewrites on projection
clusters extracted from real installed AI implementations. Transformer-derived
graphs are deliberately inefficient control artifacts, not the target
architecture. No model is trained and no GPU execution is part of the
protocol.

The restricted typed language contains same-input linear projections, exact
packing/splitting, head reshapes, and transposes. The constructor enumerates
every set partition, measures development outcomes with CPU TorchInductor, and
learns a conditional decision tree. A contained candidate applies the frozen
tree to one post-freeze artifact at a time.

Important files:

- `PROTOCOL.md`: predeclared corpus, controls, measurements, heldout seed, and
  verdict gate.
- `ghost_tensor_extract_v4.py`: real `torch.export` extraction plus split
  public/private provenance.
- `ghost_tensor_constructor_v4.py`: exhaustive development measurement and
  outcome-tree learner.
- `ghost_tensor_candidate_v4.py`: independent contained rule application.
- `ghost_tensor_egraph_v4.py`: genuine fixed equality-saturation control.
- `ghost_tensor_verify_v4.py`: independent structural and numerical verifier.
- `ghost_tensor_trial_v4.py`: prospective containment/control/measurement
  runner.
- `ghost_tensor_freeze_v4.py`: pre-heldout SHA-256 freeze creation and
  verification.

The strongest allowed claim is a replayable conditional rewrite result on this
restricted CPU graph language. It is not evidence for Transformer efficiency,
pretrained-model speed, GPU speed, autonomous primitive invention, or general
AI architecture discovery.
