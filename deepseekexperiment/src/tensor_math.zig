const std = @import("std");

/// Computes the dot product of two vectors
pub fn dot(a: []const f32, b: []const f32) f32 {
    std.debug.assert(a.len == b.len);
    var sum: f32 = 0.0;
    for (a, b) |va, vb| {
        sum += va * vb;
    }
    return sum;
}

/// Computes y = A * x, where A is a matrix of size (rows x cols) and x is a vector of size (cols)
pub fn matVecMul(allocator: std.mem.Allocator, A: []const f32, x: []const f32, rows: usize, cols: usize) ![]f32 {
    std.debug.assert(A.len == rows * cols);
    std.debug.assert(x.len == cols);
    
    const y = try allocator.alloc(f32, rows);
    for (0..rows) |i| {
        y[i] = dot(A[i * cols .. (i + 1) * cols], x);
    }
    return y;
}

/// Zero-copy BF16 Matrix-Vector Multiplication directly from memory-mapped bytes
pub fn matVecMulBf16(allocator: std.mem.Allocator, A_bf16_bytes: []const u8, x: []const f32, rows: usize, cols: usize) ![]f32 {
    std.debug.assert(A_bf16_bytes.len == rows * cols * 2);
    std.debug.assert(x.len == cols);
    
    const y = try allocator.alloc(f32, rows);
    for (0..rows) |i| {
        var sum: f32 = 0.0;
        const row_start = i * cols * 2;
        for (0..cols) |j| {
            const byte_idx = row_start + j * 2;
            const b0 = A_bf16_bytes[byte_idx];
            const b1 = A_bf16_bytes[byte_idx + 1];
            
            // Reconstruct BF16 (little-endian) and shift to F32 format
            const b = @as(u32, b0) | (@as(u32, b1) << 8);
            const f_bits = b << 16;
            const A_val = @as(f32, @bitCast(f_bits));
            
            sum += A_val * x[j];
        }
        y[i] = sum;
    }
    return y;
}

/// Zero-copy I8 Matrix-Vector Multiplication
pub fn matVecMulI8(allocator: std.mem.Allocator, A_i8_bytes: []const u8, x: []const f32, rows: usize, cols: usize) ![]f32 {
    std.debug.assert(A_i8_bytes.len == rows * cols);
    std.debug.assert(x.len == cols);
    
    const y = try allocator.alloc(f32, rows);
    for (0..rows) |i| {
        var sum: f32 = 0.0;
        const row_start = i * cols;
        for (0..cols) |j| {
            const b = A_i8_bytes[row_start + j];
            const A_val = @as(f32, @floatFromInt(@as(i8, @bitCast(b))));
            sum += A_val * x[j];
        }
        y[i] = sum;
    }
    return y;
}

/// Zero-copy FP8_E4M3 Matrix-Vector Multiplication
pub fn matVecMulFp8(allocator: std.mem.Allocator, A_fp8_bytes: []const u8, x: []const f32, rows: usize, cols: usize) ![]f32 {
    std.debug.assert(A_fp8_bytes.len == rows * cols);
    std.debug.assert(x.len == cols);
    
    const y = try allocator.alloc(f32, rows);
    for (0..rows) |i| {
        var sum: f32 = 0.0;
        const row_start = i * cols;
        for (0..cols) |j| {
            const b = A_fp8_bytes[row_start + j];
            
            var A_val: f32 = 0.0;
            if (b != 0) {
                const sign = @as(u32, b >> 7) << 31;
                const exp_val = (b >> 3) & 0x0F;
                const mantissa = @as(u32, b & 0x07);
                
                if (exp_val != 0) {
                    const f32_exp = @as(u32, exp_val) + 127 - 7;
                    const f32_mantissa = mantissa << 20;
                    const f_bits = sign | (f32_exp << 23) | f32_mantissa;
                    A_val = @as(f32, @bitCast(f_bits));
                }
            }
            
            sum += A_val * x[j];
        }
        y[i] = sum;
    }
    return y;
}

/// Applies Sigmoid function to an array in-place
pub fn sigmoidInPlace(x: []f32) void {
    for (x) |*val| {
        val.* = 1.0 / (1.0 + @exp(-val.*));
    }
}

/// Applies SiLU (Swish) activation: x * sigmoid(x)
pub fn siluInPlace(x: []f32) void {
    for (x) |*val| {
        val.* = val.* * (1.0 / (1.0 + @exp(-val.*)));
    }
}

/// Elementwise a = a * b
pub fn elementwiseMulInPlace(a: []f32, b: []const f32) void {
    std.debug.assert(a.len == b.len);
    for (a, b) |*va, vb| {
        va.* = va.* * vb;
    }
}

pub const TopKResult = struct {
    indices: []usize,
    values: []f32,
};

/// Finds the top K values and their indices. Very fast for small K (like K=1 or 2).
pub fn topK(allocator: std.mem.Allocator, x: []const f32, k: usize) !TopKResult {
    const indices = try allocator.alloc(usize, k);
    const values = try allocator.alloc(f32, k);
    
    @memset(values, -std.math.inf(f32));
    @memset(indices, 0);
    
    for (x, 0..) |val, i| {
        // Simple insertion sort for Top K
        var curr_val = val;
        var curr_idx = i;
        for (0..k) |j| {
            if (curr_val > values[j]) {
                const temp_val = values[j];
                const temp_idx = indices[j];
                values[j] = curr_val;
                indices[j] = curr_idx;
                curr_val = temp_val;
                curr_idx = temp_idx;
            }
        }
    }
    
    return TopKResult{
        .indices = indices,
        .values = values,
    };
}

/// Finds the Top-K indices and values, but ONLY allowed to pick from the provided allowed_experts slice
pub fn restrictedTopK(allocator: std.mem.Allocator, logits: []const f32, k: usize, allowed_experts: []const usize) !TopKResult {
    const indices = try allocator.alloc(usize, k);
    const values = try allocator.alloc(f32, k);
    
    @memset(indices, 0);
    for (values) |*v| v.* = -std.math.inf(f32);
    
    // Only iterate through the experts currently locked in VRAM cache
    for (allowed_experts) |expert_idx| {
        if (expert_idx >= logits.len) continue;
        
        var curr_val = logits[expert_idx];
        var curr_idx = expert_idx;
        
        for (0..k) |j| {
            if (curr_val > values[j]) {
                const temp_val = values[j];
                const temp_idx = indices[j];
                values[j] = curr_val;
                indices[j] = curr_idx;
                curr_val = temp_val;
                curr_idx = temp_idx;
            }
        }
    }
    
    return TopKResult{
        .indices = indices,
        .values = values,
    };
}
