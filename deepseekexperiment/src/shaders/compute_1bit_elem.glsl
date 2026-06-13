#version 450
// One thread per output element (row,b). No reduction, no shared mem. Each
// thread does a full dot product. global threads = out_dim*B.
layout(local_size_x = 64) in;
layout(constant_id = 0) const uint B = 32u;
struct BitBlock { uint bits_low; uint bits_high; float scale; };
layout(std430, binding = 0) readonly buffer In { float acts[]; };      // in_dim x B
layout(std430, binding = 1) readonly buffer W { BitBlock weights[]; };
layout(std430, binding = 2) writeonly buffer Out { float out_vec[]; }; // out_dim x B
layout(push_constant) uniform PC { uint input_dim; uint output_dim; } push;
void main() {
    uint gid = gl_GlobalInvocationID.x;
    uint total = push.output_dim * B;
    if (gid >= total) return;
    uint row = gid / B;
    uint b = gid % B;
    uint bpr = push.input_dim / 64;
    float acc = 0.0;
    for (uint blk = 0u; blk < bpr; ++blk) {
        BitBlock w = weights[row * bpr + blk];
        uint base = blk * 64;
        for (uint i = 0u; i < 64u; ++i) {
            uint bits = (i < 32u) ? w.bits_low : w.bits_high;
            float s = float((bits >> (i & 31u)) & 1u) * 2.0 - 1.0;
            acc += s * acts[(base + i) * B + b];
        }
    }
    out_vec[row * B + b] = acc * 0.05;
}
