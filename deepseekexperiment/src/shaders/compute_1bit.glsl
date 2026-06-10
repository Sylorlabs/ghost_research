#version 450

layout(local_size_x = 64) in;

struct BitBlock {
    uint bits_low;
    uint bits_high;
    float scale;
};

layout(std430, binding = 0) readonly buffer InputNormState {
    float norm_state[];
};

layout(std430, binding = 1) readonly buffer WeightMatrix {
    BitBlock weights[];
};

layout(std430, binding = 2) writeonly buffer OutputVector {
    float out_vec[];
};

layout(push_constant) uniform PushConstants {
    uint input_dim;
    uint output_dim;
} push;

void main() {
    uint out_idx = gl_GlobalInvocationID.x;
    if (out_idx >= push.output_dim) {
        return;
    }

    uint blocks_per_row = push.input_dim / 64;
    float dot_val = 0.0;

    for (uint b = 0; b < blocks_per_row; ++b) {
        uint block_idx = out_idx * blocks_per_row + b;
        BitBlock block = weights[block_idx];
        
        uint base_input_idx = b * 64;

        // Unroll the 32 bits of bits_low
        for (uint i = 0; i < 32; ++i) {
            bool is_one = (block.bits_low & (1u << i)) != 0u;
            float w = is_one ? block.scale : -block.scale;
            dot_val += norm_state[base_input_idx + i] * w;
        }

        // Unroll the 32 bits of bits_high
        for (uint i = 0; i < 32; ++i) {
            bool is_one = (block.bits_high & (1u << i)) != 0u;
            float w = is_one ? block.scale : -block.scale;
            dot_val += norm_state[base_input_idx + 32 + i] * w;
        }
    }

    out_vec[out_idx] = dot_val;
}
