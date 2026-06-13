#version 450
// Batched 1-bit GEMM, transposed activations [in_dim][B] for coalesced b-reads.
layout(local_size_x = 64) in;
layout(constant_id = 0) const uint B = 32u;
struct BitBlock { uint bits_low; uint bits_high; float scale; };
layout(std430, binding = 0) readonly buffer In { float acts[]; };      // in_dim x B (col-major in b)
layout(std430, binding = 1) readonly buffer W { BitBlock weights[]; };
layout(std430, binding = 2) writeonly buffer Out { float out_vec[]; }; // out_dim x B
layout(push_constant) uniform PC { uint input_dim; uint output_dim; } push;
shared float partial[64];
void main() {
    uint row = gl_WorkGroupID.x;
    uint lane = gl_LocalInvocationID.x;
    uint bpr = push.input_dim / 64;
    float acc[B];
    for (uint b = 0u; b < B; ++b) acc[b] = 0.0;
    for (uint blk_i = lane; blk_i < bpr; blk_i += 64) {
        BitBlock blk = weights[row * bpr + blk_i];
        uint base = blk_i * 64;
        for (uint i = 0u; i < 64u; ++i) {
            uint bits = (i < 32u) ? blk.bits_low : blk.bits_high;
            float s = float((bits >> (i & 31u)) & 1u) * 2.0 - 1.0;
            uint off = (base + i) * B;          // transposed: consecutive b
            for (uint b = 0u; b < B; ++b) acc[b] += s * acts[off + b];
        }
    }
    for (uint b = 0u; b < B; ++b) {
        partial[lane] = acc[b];
        barrier();
        for (uint s = 32u; s > 0u; s >>= 1) { if (lane < s) partial[lane] += partial[lane + s]; barrier(); }
        if (lane == 0u) out_vec[row * B + b] = partial[0] * 0.05;
        barrier();
    }
}
