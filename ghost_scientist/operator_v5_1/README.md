# Ghost Scientist Operator v5.1

Operator v5.1 is a preserved follow-up to the frozen Operator v5 prospective
FAIL.  v5 missed its predeclared 1% strong-fixed margin by 0.033 percentage
points; 17/18 other gates passed.

v5.1 does not relax that gate.  It reclassifies all v5 outcomes, including the
failed heldout, as calibration evidence; permits one additional typed feature
(`input_elements`) for the unstable explicit-normalization signature; freezes
again; and requires a new seed and a new prospective heldout.

All evaluator, candidate, IR, synthesis, equality-saturation, containment, and
measurement code remains byte-identical to the v5 freeze.  Only the learned
grammar/control memories, v5.1 protocol wrapper, freeze record, and post-freeze
corpus change.

