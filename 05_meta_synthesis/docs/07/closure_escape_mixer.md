# Closure escape in the mixer domain (MUL as the out-of-closure generator)

**Status:** built, measured. Reproduce: `cd 05_meta_synthesis && zig build
-Doptimize=ReleaseFast && ./zig-out/bin/closure_escape_mixer` (12,000 hill-climb
iters × 6 seeds). Companion to the `affine_closure` theorem (this thread) and the
control-domain twin `asi_attempt/docs/research/closure_escape_control.md`.

## The question

The closure principle says: search confined to a closed primitive set cannot
leave that set's closure; the escape is to inject a generator outside it. The
mixer domain is the cleanest place to test it — the substrate's algebra (GF(2))
is explicit. Does the SAME hill-climber escape the affine ceiling when, and only
when, given an out-of-closure op?

## The subtlety the experiment forced: pick the right statistic

First attempt used **mean avalanche** (mean #output bits flipped per input-bit
flip; ideal 32). Both MUL-free and MUL-enabled reached ~32 — *the metric is too
weak.* A dense GF(2)-affine matrix `y = Ax+b` flips ~half the bits on average, so
the first-order statistic cannot see the ceiling. The ceiling lives in the
**second-order** statistic: the strict avalanche criterion (SAC), the mean over
all 64×64 (input-bit, output-bit) pairs of `|P(flip) − 0.5|`.

## Results

```
  mode              | mean av | mean SAC-err | best SAC-err
  ------------------+---------+--------------+-------------
  MUL-free          |  31.970 |     0.1269   |    0.0331
  MUL-enabled       |  32.042 |     0.0213   |    0.0174
```

## Reading — a two-level escape

- **Pure GF(2)-affine (XOR/shift only): SAC-error = 0.5 exactly — a theorem.**
  Flipping input bit `i` changes `Δy = A·e_i` (column `i` of `A`), independent of
  `x`: every output bit flips deterministically (prob 0 or 1), so `|P−0.5| = 0.5`
  for all pairs. No search can move it. (This is `affine_closure` viewed through
  SAC rather than PractRand.)
- **MUL-free *with ADD* → 0.127.** This op set is not pure-affine: ADD's carry
  chain is nonlinear over GF(2), so it escapes 0.5 — but plateaus an order of
  magnitude short of ideal.
- **MUL-enabled → 0.021 (~6× lower).** Integer multiply is a strong nonlinear
  diffuser; it drives SAC toward 0.

So nonlinearity is the out-of-closure generator: the GF(2)-linear core is pinned
at 0.5 (theorem), ADD's carry buys a partial escape, MUL buys a full one. Same
search, generators added — exactly the structure of the control-domain result
where the XOR/bundle substrate is pinned at chance on the band predicate and the
SUM readout (`mb_mass`) escapes it.

## Place in the cross-domain picture

| domain | closed substrate | ceiling statistic | out-of-closure generator | escape |
|--------|------------------|-------------------|--------------------------|--------|
| mixers | GF(2)-affine | SAC-error 0.5 | ADD (carry), MUL | 0.5 → 0.13 → 0.02 |
| control | XOR/bundle VSA | band-readout = chance | the SUM (mb_mass) | chance → beats thermostat |
| invention (wcore) | fixed opcode VM | only known mechanisms | a new atom | Claim C |

Three domains, one principle, each now with a runnable controlled before/after.
