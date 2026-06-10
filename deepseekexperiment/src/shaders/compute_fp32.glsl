#version 450

layout(local_size_x = 256) in;

layout(set = 0, binding = 0) buffer InBuffer {
    float in_vec[];
};

layout(set = 0, binding = 1) buffer WeightBuffer {
    float w_matrix[];
};

layout(set = 0, binding = 2) buffer OutBuffer {
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
    
    float dot = 0.0;
    uint row_offset = out_idx * push.input_dim;
    
    for (uint i = 0; i < push.input_dim; i++) {
        dot += in_vec[i] * w_matrix[row_offset + i];
    }
    
    out_vec[out_idx] = dot;
}
