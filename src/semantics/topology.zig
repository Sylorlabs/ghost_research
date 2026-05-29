const std = @import("std");
const vsa = @import("vsa");
const codebook = @import("ghost_codebook");

// ============================================================================
// TOPOLOGY EXTRACTOR
//
// Bridges the Void Engine's 512-chamber geometric state to a ConceptGraph.
//
// The ENTIRE 512-chamber array is treated as a single high-dimensional vector.
// It is projected to a 1024-bit Hypervector (2 bits per chamber), then
// dot-producted against the 10 concept HVs in the codebook to determine
// which concepts are "active" (resonating above noise threshold).
//
// Edges between active concepts are extracted using VSA bind algebra:
// if similarity(state_hv, bind(concept_A, concept_B)) > threshold,
// then A and B are structurally related in the AST.
// Direction is determined by resonance magnitude (higher = parent).
// ============================================================================

pub const ChamberCount: usize = 512;
pub const MaxNodes: usize = 12;
pub const MaxChildren: usize = 4;

pub const GraphNode = struct {
    concept: codebook.Concept,
    children: [MaxChildren]u8, // indices into ConceptGraph.nodes
    child_count: u8,
    resonance: u32, // similarity score against state HV
};

pub const ConceptGraph = struct {
    nodes: [MaxNodes]GraphNode,
    node_count: u8,
    root: u8, // index of root node

    pub fn getNode(self: *const ConceptGraph, idx: u8) GraphNode {
        return self.nodes[idx];
    }

    pub fn printTopology(self: *const ConceptGraph, writer: anytype) !void {
        try writer.print("\n=== RAW CONCEPT GRAPH TOPOLOGY ===\n", .{});
        try writer.print("Nodes: {d}\n", .{self.node_count});
        try writer.print("Root Index: {d}\n\n", .{self.root});

        for (0..self.node_count) |i| {
            const node = self.nodes[i];
            try writer.print("Node [{d}]: {s}\n", .{ i, @tagName(node.concept) });
            try writer.print("  Resonance: {d}/1024\n", .{node.resonance});
            if (node.child_count > 0) {
                try writer.print("  Edges: -> [", .{});
                for (0..node.child_count) |c| {
                    if (c > 0) try writer.writeAll(", ");
                    try writer.print("{d}", .{node.children[c]});
                }
                try writer.print("]\n", .{});
            } else {
                try writer.print("  Edges: None\n", .{});
            }
            try writer.writeAll("\n");
        }
        try writer.print("==================================\n", .{});
    }
};

// ============================================================================
// CHAMBER → HYPERVECTOR PROJECTION
//
// 512 chambers × 2 bits each = 1024 bits = exactly vsa.Dim.
// This is NOT a coincidence; the architecture was designed for this mapping.
//
// For each chamber i:
//   bit 2*i:     1 if chamber[i] > median, else 0
//   bit 2*i + 1: 1 if chamber[i] > 0, else 0
//
// This encodes both the relative position (above/below median) and
// the absolute polarity (positive/negative) of each chamber into the
// binary vector space where concept HVs live.
// ============================================================================

pub fn projectChambers(chambers: *const [ChamberCount]i128) vsa.Hypervector {
    var hv = vsa.Hypervector.initEmpty();

    for (0..ChamberCount) |i| {
        const pos_a = i * 2;
        const pos_b = i * 2 + 1;

        // Split the i128 into two independent i64 halves
        const low: i64 = @truncate(chambers[i]);
        const high: i64 = @as(i64, @truncate(chambers[i] >> 64));

        const bit_low: u64 = if (low > 0) 1 else 0;
        const bit_high: u64 = if (high > 0) 1 else 0;

        hv.data[pos_a / 64] |= bit_low << @as(u6, @intCast(pos_a % 64));
        hv.data[pos_b / 64] |= bit_high << @as(u6, @intCast(pos_b % 64));
    }

    return hv;
}

// ============================================================================
// GRAPH EXTRACTION
//
// 1. Project full 512-chamber state → 1024-bit Hypervector
// 2. Dot-product against all 10 concept HVs → resonance scores
// 3. Select active concepts (above noise threshold)
// 4. Extract edges via VSA bind: similarity(state, bind(A, B)) > threshold
// 5. Enforce single-root DAG
// ============================================================================

pub fn extractGraph(chambers: *const [ChamberCount]i128) ConceptGraph {
    var graph = ConceptGraph{
        .nodes = undefined,
        .node_count = 0,
        .root = 0,
    };
    // Zero-init all nodes
    for (0..MaxNodes) |i| {
        graph.nodes[i] = .{
            .concept = .FnDecl,
            .children = [_]u8{0} ** MaxChildren,
            .child_count = 0,
            .resonance = 0,
        };
    }

    // Step 1: Project the ENTIRE 512-chamber state to a 1024-bit HV
    const state_hv = projectChambers(chambers);

    // Step 2: Compute resonance for all 10 concepts
    const scores = codebook.Codebook.computeResonance(state_hv);

    // Step 3: Sort concepts by resonance (descending) and select active ones
    var concept_order: [codebook.ConceptCount]struct {
        concept: codebook.Concept,
        score: u32,
    } = undefined;

    for (0..codebook.ConceptCount) |i| {
        concept_order[i] = .{
            .concept = @enumFromInt(i),
            .score = scores[i],
        };
    }

    // Bubble sort descending by score (only 10 elements)
    for (0..codebook.ConceptCount - 1) |i| {
        for (i + 1..codebook.ConceptCount) |j| {
            if (concept_order[j].score > concept_order[i].score) {
                const tmp = concept_order[i];
                concept_order[i] = concept_order[j];
                concept_order[j] = tmp;
            }
        }
    }

    // Activation threshold: random baseline is ~512.
    // We accept concepts that are even slightly above noise to be inclusive.
    // The feedback loop will prune bad topologies via compiler errors.
    const activation_threshold: u32 = 516;

    for (0..codebook.ConceptCount) |i| {
        if (concept_order[i].score >= activation_threshold and graph.node_count < MaxNodes) {
            graph.nodes[graph.node_count] = .{
                .concept = concept_order[i].concept,
                .children = [_]u8{0} ** MaxChildren,
                .child_count = 0,
                .resonance = concept_order[i].score,
            };
            graph.node_count += 1;
        }
    }

    // Floor: always have at least 3 active concepts
    if (graph.node_count < 3) {
        graph.node_count = 3;
        for (0..3) |i| {
            graph.nodes[i] = .{
                .concept = concept_order[i].concept,
                .children = [_]u8{0} ** MaxChildren,
                .child_count = 0,
                .resonance = concept_order[i].score,
            };
        }
    }

    // Root is the highest-resonance concept (index 0 after sort)
    graph.root = 0;

    // Step 4: Extract edges using VSA bind algebra
    // For each pair (i, j) where i has higher resonance:
    //   relationship_hv = bind(concept_i_hv, concept_j_hv)
    //   edge_score = similarity(state_hv, relationship_hv)
    //   If edge_score > edge_threshold, i → j is an edge
    const edge_threshold: u32 = 508;

    for (0..graph.node_count) |i| {
        const concept_a = graph.nodes[i].concept;
        const geom_a = codebook.Codebook.getConceptGeometry(concept_a);

        var j: usize = i + 1;
        while (j < graph.node_count) : (j += 1) {
            if (graph.nodes[i].child_count >= MaxChildren) break;

            const concept_b = graph.nodes[j].concept;
            const geom_b = codebook.Codebook.getConceptGeometry(concept_b);

            // 1. VOID TENSION: Does the raw mathematical state want this edge?
            // We check if the state contains the relationship of A's identity -> B's identity.
            const rel_hv = geom_a.identity.bind(codebook.Port_Parent).bind(geom_b.identity.bind(codebook.Port_Child));
            const raw_edge_score = state_hv.similarity(rel_hv);

            // 2. SYNTACTIC VALENCE: Does the geometry of Zig allow this edge?
            // UNBIND the cryptographic ports to project roles back into a shared subspace
            const expected_raw_role = geom_a.expectation.unbind(codebook.Port_Child);
            const defined_raw_role = geom_b.definition.unbind(codebook.Port_Parent);

            // Compute clean semantic resonance in the raw shared subspace
            const syntactic_resonance = expected_raw_role.similarity(defined_raw_role);

            // 3. THE GEOMETRIC FILTER
            // The edge is formed ONLY if both the tension matrix and the syntax geometry align above threshold.
            const grammar_threshold: u32 = 650; 

            if (raw_edge_score >= edge_threshold and syntactic_resonance >= grammar_threshold) {
                if (concept_a == .VarAssign and concept_b == .Parameter) {
                    std.debug.print("VarAssign -> Parameter passed! raw_score={} resonance={} geom_a.exp={} geom_b.def={}\n", .{raw_edge_score, syntactic_resonance, geom_a.expectation.data[0], geom_b.definition.data[0]});
                }
                graph.nodes[i].children[graph.nodes[i].child_count] = @intCast(j);
                graph.nodes[i].child_count += 1;
            }
        }
    }

    // Step 5: Ensure every non-root node has at least one parent.
    // Orphans get attached to root.
    for (1..graph.node_count) |j| {
        var has_parent = false;
        for (0..graph.node_count) |i| {
            for (0..graph.nodes[i].child_count) |c| {
                if (graph.nodes[i].children[c] == @as(u8, @intCast(j))) {
                    has_parent = true;
                    break;
                }
            }
            if (has_parent) break;
        }
        if (!has_parent and graph.nodes[0].child_count < MaxChildren) {
            graph.nodes[0].children[graph.nodes[0].child_count] = @intCast(j);
            graph.nodes[0].child_count += 1;
        }
    }

    return graph;
}

// ============================================================================
// TESTS
// ============================================================================

test "projectChambers produces deterministic 1024-bit HV from 512 chambers" {
    var chambers: [ChamberCount]i128 = undefined;
    // Fill with a known pattern: chamber[i] = i * 7 - 1792
    for (0..ChamberCount) |i| {
        chambers[i] = @as(i128, @intCast(i)) * 7 - 1792;
    }

    const hv1 = projectChambers(&chambers);
    const hv2 = projectChambers(&chambers);

    // Same input → same output
    try std.testing.expectEqual(hv1.data, hv2.data);

    // Not all zeros (some chambers are above median and positive)
    var any_nonzero = false;
    for (hv1.data) |word| {
        if (word != 0) {
            any_nonzero = true;
            break;
        }
    }
    try std.testing.expect(any_nonzero);
}

test "extractGraph produces a valid graph with nodes and edges" {
    var chambers: [ChamberCount]i128 = undefined;
    // Use a deterministic seed pattern
    for (0..ChamberCount) |i| {
        const s: i128 = @intCast(i);
        chambers[i] = @rem(s * 31337, 10000) - 5000;
    }

    const graph = extractGraph(&chambers);

    // Must have at least 3 nodes (floor guarantee)
    try std.testing.expect(graph.node_count >= 3);

    // Root must be valid
    try std.testing.expect(graph.root < graph.node_count);

    // Node count must not exceed max
    try std.testing.expect(graph.node_count <= MaxNodes);

    // All children must be valid indices
    for (0..graph.node_count) |i| {
        for (0..graph.nodes[i].child_count) |c| {
            try std.testing.expect(graph.nodes[i].children[c] < graph.node_count);
        }
    }
}
