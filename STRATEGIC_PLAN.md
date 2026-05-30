# BitForge Strategic Plan

To transition BitForge from "introspective research" to an "applied breakthrough," the project will target high-value, high-complexity systems engineering bottlenecks rather than general "toy" benchmarking. 

The following four strategic challenges outline the path to transforming BitForge into an indispensable industrial tool.

### 1. The Hardware-Constraint Challenge (SIMD / AVX-512)
**Goal:** Synthesize programs that operate on vector registers (`u512`) where instructions map directly to hardware intrinsics (shuffles, masked moves, permutations) rather than simple arithmetic.
*   **The Approach:** Extend `DomainSpec` to handle Zig's `@Vector(8, u64)`.
*   **The Edge:** Discover verified, branchless SIMD sorting networks or hash mixers that outperform hand-tuned assembly by exploiting complex, non-obvious hardware instruction combinations.

### 2. The Nonlinear Escape Challenge (Breaking Affine Traps)
**Goal:** Automate the discovery of "Cheap Nonlinearity." Overcome the GF(2) affine subspace trap (proved in Thread 07) that guarantees statistical failure for XOR/SHIFT-only programs.
*   **The Approach:** Avoid heavy multiplication (MUL) by forcing the engine to use non-affine operations like `ADD`, `SUB`, or `AND_NOT`. Alter the fitness function to explicitly reward nonlinear structural complexity, bypassing the local minima caused by carry-chain avalanche disruptions early in the search.
*   **The Edge:** Generate a "MUL-free" mixer that passes PractRand by using a minimal, verified set of nonlinear "gadgets."

### 3. The Security-Specification Challenge (SAC in SMT)
**Goal:** Encode the Strict Avalanche Criterion (SAC) directly into the Z3 SMT specification, rather than relying on statistical black-box testing like PractRand.
*   **The Approach:** Formulate an SMT constraint: $\forall x, \forall i : \text{popcount}(P(x) \oplus P(x \oplus 2^i)) = N/2$. To mitigate state explosion, target smaller 16-bit or 32-bit S-boxes first.
*   **The Edge:** Synthesize formally verified, perfect-avalanche S-boxes, transitioning BitForge into a tool for generating cryptographically secure primitives.

### 4. The Compiler-Defiance Challenge (Superoptimization)
**Goal:** Use BitForge as an aggressive Peephole Optimizer (JIT Superoptimizer) capable of outperforming standard LLVM/GCC optimizations on specific algorithms.
*   **The Approach:** Define an oracle function $F_{ref}(x)$ and set the Z3 spec to `assert P(x) == F_ref(x)`. Restrict `MaxProgLen` strictly below the compiler's output length.
*   **The Edge:** Discover deep algebraic simplifications that compilers miss, producing functionally equivalent programs with a significantly reduced instruction count.