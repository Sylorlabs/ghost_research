const std = @import("std");
const codebook = @import("ghost_codebook");
const vsa = @import("vsa");
const flame = @import("flame");

// Maps keywords to specific concept primitives
const KeywordMap = struct {
    word: []const u8,
    concept: codebook.Concept,
};

const ground_map = [_]KeywordMap{
    .{ .word = "u32", .concept = .Type_u32 },
    .{ .word = "array", .concept = .Type_u8_Array },
    .{ .word = "u8", .concept = .Type_u8_Array },
    .{ .word = "function", .concept = .FnDecl },
    .{ .word = "return", .concept = .ReturnStmt },
    .{ .word = "returns", .concept = .ReturnStmt },
    .{ .word = "add", .concept = .Op_Add },
    .{ .word = "multiply", .concept = .Op_Mul },
    .{ .word = "assign", .concept = .VarAssign },
};

pub const Grounding = struct {
    pub fn scanAndExtract(allocator: std.mem.Allocator, intent: []const u8) ![]codebook.Concept {
        var active_concepts = std.ArrayList(codebook.Concept).init(allocator);
        defer active_concepts.deinit();

        // Very basic tokenizer: split by spaces and punctuation
        var it = std.mem.tokenizeAny(u8, intent, " ,.;:!?()[]{}\"'\n\t");
        while (it.next()) |token| {
            // Case-insensitive match
            var lower_token_buf: [128]u8 = undefined;
            const lower_token = std.ascii.lowerString(&lower_token_buf, token);

            for (ground_map) |entry| {
                if (std.mem.eql(u8, lower_token, entry.word)) {
                    // Check if already added to avoid duplicates
                    var found = false;
                    for (active_concepts.items) |c| {
                        if (c == entry.concept) found = true;
                    }
                    if (!found) {
                        try active_concepts.append(entry.concept);
                    }
                }
            }
        }

        return active_concepts.toOwnedSlice();
    }

    pub fn injectTension(state: *flame.FlameState, concepts: []const codebook.Concept) void {
        if (concepts.len == 0) return;

        for (concepts) |c| {
            const hv = codebook.Codebook.getConceptGeometry(c).identity;
            const magnitude: i64 = 5_000_000;

            for (0..flame.ChamberCount) |i| {
                const pos_a = i * 2;
                const pos_b = i * 2 + 1;

                const bit_a = (hv.data[pos_a / 64] >> @as(u6, @intCast(pos_a % 64))) & 1;
                const bit_b = (hv.data[pos_b / 64] >> @as(u6, @intCast(pos_b % 64))) & 1;

                var low: i64 = @truncate(state.chamber[i]);
                var high: i64 = @as(i64, @truncate(state.chamber[i] >> 64));

                if (bit_a == 1) {
                    low +|= magnitude;
                } else {
                    low -|= magnitude;
                }

                if (bit_b == 1) {
                    high +|= magnitude;
                } else {
                    high -|= magnitude;
                }

                const u_low: u64 = @bitCast(low);
                const u_high: u64 = @bitCast(high);
                const combined: u128 = (@as(u128, u_high) << 64) | @as(u128, u_low);
                state.chamber[i] = @bitCast(combined);
            }
        }
    }

    pub fn injectTargetedHeat(state: *flame.FlameState, concepts: []const codebook.Concept) void {
        if (concepts.len == 0) return;

        var max_tension: i64 = 0;
        for (state.chamber) |val| {
            const low: i64 = @truncate(val);
            const high: i64 = @as(i64, @truncate(val >> 64));
            
            const abs_low = if (low < 0) -low else low;
            const abs_high = if (high < 0) -high else high;
            
            if (abs_low > max_tension) max_tension = abs_low;
            if (abs_high > max_tension) max_tension = abs_high;
        }

        if (max_tension < 100_000) max_tension = 100_000;
        const magnitude: i64 = @divTrunc(max_tension * 15, 100);

        for (concepts) |c| {
            const hv = codebook.Codebook.getConceptGeometry(c).identity;
            
            for (0..flame.ChamberCount) |i| {
                const pos_a = i * 2;
                const pos_b = i * 2 + 1;

                const bit_a = (hv.data[pos_a / 64] >> @as(u6, @intCast(pos_a % 64))) & 1;
                const bit_b = (hv.data[pos_b / 64] >> @as(u6, @intCast(pos_b % 64))) & 1;

                var low: i64 = @truncate(state.chamber[i]);
                var high: i64 = @as(i64, @truncate(state.chamber[i] >> 64));

                if (bit_a == 1) {
                    low +|= magnitude;
                } else {
                    low -|= magnitude;
                }

                if (bit_b == 1) {
                    high +|= magnitude;
                } else {
                    high -|= magnitude;
                }

                const u_low: u64 = @bitCast(low);
                const u_high: u64 = @bitCast(high);
                const combined: u128 = (@as(u128, u_high) << 64) | @as(u128, u_low);
                state.chamber[i] = @bitCast(combined);
            }
        }
    }

    pub fn pinConcepts(state: *flame.FlameState, concepts: []const codebook.Concept) void {
        if (concepts.len == 0) return;

        var max_tension: i64 = 0;
        for (state.chamber) |val| {
            const low: i64 = @truncate(val);
            const high: i64 = @as(i64, @truncate(val >> 64));
            
            const abs_low = if (low < 0) -low else low;
            const abs_high = if (high < 0) -high else high;
            
            if (abs_low > max_tension) max_tension = abs_low;
            if (abs_high > max_tension) max_tension = abs_high;
        }

        if (max_tension < 100_000) max_tension = 100_000;
        const magnitude: i64 = @divTrunc(max_tension * 15, 100);

        for (concepts) |c| {
            const hv = codebook.Codebook.getConceptGeometry(c).identity;
            
            for (0..flame.ChamberCount) |i| {
                const pos_a = i * 2;
                const pos_b = i * 2 + 1;

                const bit_a = (hv.data[pos_a / 64] >> @as(u6, @intCast(pos_a % 64))) & 1;
                const bit_b = (hv.data[pos_b / 64] >> @as(u6, @intCast(pos_b % 64))) & 1;

                var low: i64 = @truncate(state.chamber[i]);
                var high: i64 = @as(i64, @truncate(state.chamber[i] >> 64));
                var updated = false;

                if (bit_a == 1) {
                    low = magnitude;
                    state.locked_low[i] = true;
                    updated = true;
                }
                if (bit_b == 1) {
                    high = magnitude;
                    state.locked_high[i] = true;
                    updated = true;
                }

                if (updated) {
                    const u_low: u64 = @bitCast(low);
                    const u_high: u64 = @bitCast(high);
                    const combined: u128 = (@as(u128, u_high) << 64) | @as(u128, u_low);
                    state.chamber[i] = @bitCast(combined);
                }
            }
        }
    }
};
