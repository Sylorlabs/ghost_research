const std = @import("std");
const hv = @import("hypervector.zig");
const connectome = @import("connectome.zig");
const Hypervector = hv.Hypervector;
const MemoryMatrix = connectome.MemoryMatrix;

pub fn computeDistancesChunk(vectors: []const Hypervector, query: Hypervector, out_distances: []f32, start_idx: usize, mask: Hypervector) void {
    for (vectors, 0..) |v, i| {
        out_distances[start_idx + i] = hv.maskedDistance(query, v, mask);
    }
}

pub fn parallelSearchMatrix(pool: *std.Thread.Pool, matrix: *const MemoryMatrix, query: Hypervector, out_distances: []f32) void {
    var wg = std.Thread.WaitGroup{};
    const vectors = matrix.concepts.items(.vector);
    const num_threads = pool.threads.len;
    if (vectors.len == 0) return;
    
    if (num_threads == 0 or vectors.len < 256) {
        computeDistancesChunk(vectors, query, out_distances, 0, matrix.entropy_mask);
        return;
    }

    const chunk_size = (vectors.len + num_threads - 1) / num_threads;
    var start_idx: usize = 0;
    while (start_idx < vectors.len) {
        const end_idx = @min(start_idx + chunk_size, vectors.len);
        const chunk = vectors[start_idx..end_idx];
        wg.start();
        pool.spawnWg(&wg, computeDistancesChunk, .{ chunk, query, out_distances, start_idx, matrix.entropy_mask });
        start_idx = end_idx;
    }
    wg.wait();
}

pub fn parallelDaemonBatch(pool: *std.Thread.Pool, matrix: *const MemoryMatrix, pairs_v1: []const Hypervector, pairs_v2: []const Hypervector, out_energies: []f32) void {
    _ = pool;
    const vectors = matrix.concepts.items(.vector);
    if (vectors.len == 0) {
        for (out_energies) |*e| e.* = 1.0;
        return;
    }

    var threads = std.ArrayList(std.Thread).init(matrix.allocator);
    defer threads.deinit();

    for (0..pairs_v1.len) |i| {
        const t = std.Thread.spawn(.{}, struct {
            fn run(vs: []const Hypervector, v1: Hypervector, v2: Hypervector, mask: Hypervector, out: *f32) void {
                const bound = hv.bind(v1, v2);
                const permuted = hv.permute(bound, 1);
                var min_dist: f32 = 1.0;
                for (vs) |v| {
                    const dist = hv.maskedDistance(permuted, v, mask);
                    if (dist < min_dist) min_dist = dist;
                }
                out.* = min_dist;
            }
        }.run, .{ vectors, pairs_v1[i], pairs_v2[i], matrix.entropy_mask, &out_energies[i] }) catch continue;
        threads.append(t) catch {};
    }
    
    for (threads.items) |t| {
        t.join();
    }
}

pub fn parallelInferenceBatch(pool: *std.Thread.Pool, matrix: *const MemoryMatrix, queries: []const Hypervector, rule: Hypervector, out_predictions: []Hypervector, out_distances: []f32) void {
    _ = pool;
    const vectors = matrix.concepts.items(.vector);

    var threads = std.ArrayList(std.Thread).init(matrix.allocator);
    defer threads.deinit();

    for (0..queries.len) |i| {
        const t = std.Thread.spawn(.{}, struct {
            fn run(m: *const MemoryMatrix, vs: []const Hypervector, fact: Hypervector, r: Hypervector, out_p: *Hypervector, out_d: *f32) void {
                const extracted = connectome.traceInference(m, fact, r);
                out_p.* = extracted;
                
                var min_dist: f32 = 1.0;
                for (vs) |v| {
                    const dist = hv.maskedDistance(extracted, v, m.entropy_mask);
                    if (dist < min_dist) min_dist = dist;
                }
                out_d.* = min_dist;
            }
        }.run, .{ matrix, vectors, queries[i], rule, &out_predictions[i], &out_distances[i] }) catch continue;
        threads.append(t) catch {};
    }
    
    for (threads.items) |t| {
        t.join();
    }
}
