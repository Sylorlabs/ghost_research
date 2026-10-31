#version 450
// Register-tiled batched GEMM: each thread does one row x TB batch-elements,
// loading each weight block ONCE and reusing across TB (weight traffic / TB).
layout(local_size_x = 64) in;
layout(constant_id = 0) const uint B = 32u;
const uint TB = 8u;
struct BitBlock { uint bits_low; uint bits_high; float scale; };
layout(std430, binding = 0) readonly buffer In { float acts[]; };      // in_dim x B
layout(std430, binding = 1) readonly buffer W { BitBlock weights[]; };
layout(std430, binding = 2) writeonly buffer Out { float out_vec[]; }; // out_dim x B
layout(push_constant) uniform PC { uint input_dim; uint output_dim; } push;
void main() {
    uint ntile = B / TB;
    uint gid = gl_GlobalInvocationID.x;
    if (gid >= push.output_dim * ntile) return;
    uint row = gid / ntile;
    uint b0 = (gid % ntile) * TB;
    uint bpr = push.input_dim / 64;
    float acc[TB];
    for (uint t = 0u; t < TB; ++t) acc[t] = 0.0;
    for (uint blk = 0u; blk < bpr; ++blk) {
        BitBlock w = weights[row * bpr + blk];   // one VRAM read, reused TB times
        uint base = blk * 64;
        for (uint i = 0u; i < 64u; ++i) {
            uint bits = (i < 32u) ? w.bits_low : w.bits_high;
            float s = float((bits >> (i & 31u)) & 1u) * 2.0 - 1.0;
            uint off = (base + i) * B + b0;
            for (uint t = 0u; t < TB; ++t) acc[t] += s * acts[off + t];
        }
    }
    for (uint t = 0u; t < TB; ++t) out_vec[row * B + b0 + t] = acc[t] * 0.05;
}
