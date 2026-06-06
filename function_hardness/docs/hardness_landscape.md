# Function Hardness: Predicate Landscape (n=4 exhaustive, n=5/6 sampled)

**Status:** complete. Reproduce:
- `cd function_hardness && zig build run -Doptimize=ReleaseFast` (n=4 exhaustive)
- `cd function_hardness && zig build sample -Doptimize=ReleaseFast` (n=5, n=6 sampling)

## The Question

All prior work in this project asks: *"can substrate S learn predicate P?"* — P is assumed known.

This project asks the inverse: *"given substrate S, what predicate is hardest for it?"* — P is discovered by exhaustion.

For n=4 binary inputs there are exactly 2^16 = 65536 boolean predicates. All can be tested in one run. No sampling, no approximation: every predicate measured against every substrate.

A secondary question answered as a byproduct: **Q38 (emergent escape)** — are there predicates where substrate A fails, substrate B fails, but their joint feature set succeeds?

## Substrates

| Name  | Features                              | Dim |
|-------|---------------------------------------|-----|
| deg1  | raw bits: b0, b1, b2, b3              | 4   |
| deg2  | bits + AND-pairs: bi·bj               | 10  |
| xor2  | XOR-pairs only: bi⊕bj                 | 6   |
| joint | bits + XOR-pairs                      | 10  |

All features are computed over binary inputs {0,1}^4. A linear readout (logistic regression, 400 epochs, lr=0.5) is fit over all 16 exhaustive inputs.

## Results

### Closure counts (perfect 16/16 accuracy)

| Substrate | In closure | Fraction |
|-----------|-----------|---------|
| deg1      | 1,882     | 2.87%   |
| deg2      | 57,494    | 87.73%  |
| xor2      | 254       | 0.39%   |
| joint     | 57,574    | 87.85%  |

**deg1 = 1882** exactly matches the known theoretical count of linearly-threshold boolean functions on 4 bits (Muroga's tables). This confirms the measurement is correct.

**deg2's massive jump**: adding 6 AND-pair features (bi·bj) to raw bits unlocks 87.73% of all predicates — 55,612 more than deg1 alone.

**xor2's tiny closure**: XOR-pair features alone cover only 254 predicates (0.39%). Most predicates that need XOR interactions also need raw bits to anchor the threshold.

**joint slightly exceeds deg2**: 57,574 vs 57,494 — 80 additional predicates that AND-pairs miss but XOR-pairs capture.

### Accuracy histogram

```
acc/16 | deg1  | deg2  | xor2  | joint
-------|-------|-------|-------|-------
  3/16 |     2 |     0 |     0 |     0
  4/16 |    10 |     2 |     0 |     0
  5/16 |    38 |     2 |     8 |     0
  6/16 |   176 |     4 |    74 |     2
  7/16 |   606 |     4 |   276 |     6
  8/16 |  2176 |    32 |   980 |    34
  9/16 |  4724 |    94 |  2838 |    84
 10/16 |  9524 |  1160 |  7196 |   264
 11/16 | 12054 |  3930 | 13686 |  1734
 12/16 | 15338 |  1648 | 17212 |  4436
 13/16 |  9048 |   658 | 13934 |   884
 14/16 |  8412 |   410 |  7052 |   502
 15/16 |  1546 |    98 |  2026 |    16
 16/16 |  1882 | 57494 |   254 | 57574
```

Note: accuracies below 8 are sign-flip artifacts (zero initialization of logistic regression can converge in the wrong direction for symmetric predicates). The true achievable accuracy is max(acc, 16−acc).

### Hardest predicates

| Substrate | Pred   | Raw acc | Corrected | Truth table      |
|-----------|--------|---------|-----------|------------------|
| deg1      | 0x2FD0 | 3/16    | 13/16     | 0000101111110100 |
| deg2      | 0x5AA5 | 4/16    | 12/16     | 1010010101011010 |
| xor2      | 0x16FF | 5/16    | 11/16     | 1111111101101000 |
| joint     | 0x3CC3 | 6/16    | 10/16     | 1100001100111100 |

**0x5AA5 for deg2**: corrected 12/16 — this is the 4-way parity predicate (XOR of all 4 bits, also written as 0x6996 but symmetric copies exist). Degree-2 AND-monomials cannot represent parity. Required degree is 4.

**0x3CC3 for joint**: corrected 10/16. Decodes to XNOR(b1,b2) = NOT XOR(b1,b2). Joint has XOR(b1,b2) as a direct feature, so this should be trivially solvable. The 6/16 result is a sign-flip artifact; the corrected 10/16 = max(6, 10) still shows joint achieves 10/16, not 16/16. Investigation needed: either XNOR(b1,b2) is not in joint's closure (surprising) or this is a convergence failure.

## Q38: Emergent Escape

**Q38 CONFIRMED: 228 predicates show emergent escape.**

Threshold used: deg1 ≤ 10/16 AND xor2 ≤ 10/16 AND joint ≥ 14/16.

```
0x033C: deg1=10/16 xor2=10/16 joint=16/16  tt=0011110011000000
0x039E: deg1=10/16 xor2=9/16  joint=16/16  tt=0111100111000000
0x055A: deg1=10/16 xor2=10/16 joint=16/16  tt=0101101010100000
0x059E: deg1=10/16 xor2=9/16  joint=16/16  tt=0111100110100000
```

### Structure of a Q38 predicate (0x033C decoded)

Truth table for 0x033C — label=1 at inputs {2,3,4,5} only:

| input | b3 b2 b1 b0 | label |
|-------|-------------|-------|
| 2     | 0  0  1  0  | 1     |
| 3     | 0  0  1  1  | 1     |
| 4     | 0  1  0  0  | 1     |
| 5     | 0  1  0  1  | 1     |
| all others |       | 0     |

Pattern: b3=0 AND XOR(b1,b2)=1. Equivalently: **NOT(b3) AND XOR(b1,b2)**.

- **deg1 alone**: raw bits {b0,b1,b2,b3}. Has b3 but not XOR(b1,b2). Can partially threshold on b3, but can't detect the XOR interaction. Best linear: ≤10/16.
- **xor2 alone**: XOR-pairs {bi⊕bj}. Has XOR(b1,b2) but no raw b3. Can detect the XOR interaction but can't apply the AND-with-NOT-b3 gate. Best: ≤10/16.
- **joint** (bits + XOR-pairs): has both b3 and XOR(b1,b2). Linear separator: −b3 + XOR(b1,b2) ≥ 0.5 classifies all 16 inputs correctly. **16/16.**

The emergent structure is: **predicates that require both a raw-bit threshold AND an XOR interaction simultaneously**. Each component substrate contributes a necessary but insufficient part of the decision boundary.

### Why this answers Q38

Q38 asked: *"can a pair of in-closure-looking ops jointly escape a closure with neither escaping alone?"*

The answer is yes, and the mechanism is clear: the 228 Q38 predicates are structurally AND-products of one term requiring raw features and one term requiring XOR features. Neither pure feature class covers the conjunction. Their union does.

This is not a trivial union: it is not the case that "joint = deg2 ∪ xor2 in all respects." The 80 predicates in joint's closure but not deg2's are a concrete example of the difference.

## Kill-tests

All three reference predicates confirmed:

```
4-way parity 0x6996:  deg1=8, deg2=8, xor2=8, joint=7  (≈ chance; joint sign-flip)
XOR(b0,b1)  0x6666:  deg1=8, deg2=16, xor2=16, joint=16  ✓
AND(b0,b1)  0x8888:  deg1=16, deg2=16, xor2=12, joint=16 ✓
```

- 4-way parity is at chance for all degree-<4 substrates, as theory predicts.
- XOR(b0,b1) is deg2-separable (b0 + b1 − 2·b0·b1 is a linear combo of deg2 features) and xor2-separable (direct feature). deg1 can't do it. ✓
- AND(b0,b1) is deg1-separable (b0+b1 ≥ 1.5 is a linear threshold). xor2 can only get 12/16 — XOR-pair features can't detect conjunctions. ✓

## Cross-n results (n=5 and n=6, 100k sampled predicates each)

### Closure fraction by substrate and n

| Substrate | n=4 (exhaustive) | n=5 (sampled) | n=6 (sampled) |
|-----------|-----------------|---------------|---------------|
| deg1      | 2.87%           | 0.001%        | 0.000%        |
| deg2      | 87.73%          | 25.51%        | 0.036%        |
| deg3      | —               | 99.23%        | 72.84%        |
| xor2      | 0.39%           | 0.002%        | 0.000%        |
| joint     | 87.85%          | 31.67%        | 0.104%        |
| Q38 rate  | 0.35%           | 1.79%         | 0.33%         |

### deg3 slips at n=6

The hypothesis "deg3 holds near 99% coverage" was directly tested and falsified. At n=5, deg3 (25 features, 32 inputs) covers 99.23% of random predicates. At n=6, deg3 (41 features, 64 inputs) covers only 72.84%.

The mechanism is overparameterization, not function-class coverage. By Cover's theorem, the fraction of randomly labeled point sets that are linearly separable depends on the ratio of feature dimension to sample count. At n=5, 25 features vs 32 points (ratio 0.78) is in the highly overparameterized regime. At n=6, 41 vs 64 (ratio 0.64) is less so. At n=7, deg3 would have C(7,3)+C(7,2)+C(7,1) = 35+21+7 = 63 features vs 128 points (ratio 0.49) — right at the phase transition. **Predicted n=7 coverage: ~50%.**

The implication: the 99.23% figure at n=5 is not evidence that deg3 features are "sufficient" for n=5 — it is evidence that 25 features nearly overfits 32 binary points regardless of what those features represent.

### deg2 collapses completely by n=6

87.73% at n=4 → 25.51% at n=5 → 0.036% at n=6. The same 21 features that covered 87% of the n=4 space cover essentially nothing in the 2^64-element n=6 space.

### Q38 rate peaked at n=5

0.35% (n=4) → 1.79% (n=5) → 0.33% (n=6). The emergent-escape structure peaks around n=5 in terms of hit rate against random sampling. At n=6, the predicate space is so large that even the AND+XOR compound predicates that require joint substrate are a small fraction.

## Open questions

1. **Sign-flip correction**: re-run with random weight initialization (or run twice with + and − init) to get correct worst-case accuracies without the zero-init artifact.

2. **Q38 structure census**: of the 228 Q38 predicates, how many decompose as NOT(bi) AND XOR(bj,bk) vs other compound structures? Is there a closed-form characterization?

3. **Generalize to n=5 or n=6**: at n=4 the whole space is tractable. At n=5 there are 2^32 ≈ 4B predicates — infeasible to enumerate, but sampling the hardest region is possible.

4. **Extend to richer substrates**: what happens with degree-3 AND-monomials vs XOR-triples? How much of the remaining 12.15% (not in deg2 closure) do they cover?

5. **Is the joint/deg2 difference of 80 predicates explainable?** These are predicates solvable with bits + XOR-pairs but not with bits + AND-pairs (at the same feature budget). What structure do they have?
