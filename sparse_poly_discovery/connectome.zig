const std = @import("std");
const hv = @import("hypervector.zig");
const Hypervector = hv.Hypervector;

pub const InsightEntry = extern struct {
    concept_a: Hypervector,
    concept_b: Hypervector,
    novel_hypervector: Hypervector,
    resultant_energy: f32,
};

pub const MemoryMatrix = struct {
    concepts: std.MultiArrayList(Concept),
    
    words: std.StringHashMap(WordConcept),
    
    allocator: std.mem.Allocator,
    
    role_subject: Hypervector,
    role_action: Hypervector,
    role_object: Hypervector,
    
    entropy_mask: Hypervector,
    global_bit_counts: []u32,

    // Ledger fields
    ledger_buffer: []InsightEntry,
    ledger_head: usize,
    ledger_tail: usize,
    ledger_mutex: std.Thread.Mutex,
    ledger_running: std.atomic.Value(bool),
    ledger_thread: ?std.Thread,

    pub const Concept = struct {
        vector: Hypervector,
        salience: f32,
        crystallized: bool,
    };
    
    pub const WordConcept = struct {
        identity: Hypervector,
        context: Hypervector,
        count: u32,
    };


    pub fn init(allocator: std.mem.Allocator) MemoryMatrix {
        var prng = std.Random.DefaultPrng.init(12345);
        return MemoryMatrix{
            .concepts = std.MultiArrayList(Concept){},
            .words = std.StringHashMap(WordConcept).init(allocator),
            .allocator = allocator,
            .role_subject = hv.initRandom(prng.random()),
            .role_action = hv.initRandom(prng.random()),
            .role_object = hv.initRandom(prng.random()),
            .entropy_mask = [_]u64{std.math.maxInt(u64)} ** 128,
            .global_bit_counts = allocator.alloc(u32, 8192) catch unreachable,
            .ledger_buffer = allocator.alloc(InsightEntry, 1024) catch unreachable,
            .ledger_head = 0,
            .ledger_tail = 0,
            .ledger_mutex = std.Thread.Mutex{},
            .ledger_running = std.atomic.Value(bool).init(false),
            .ledger_thread = null,
        };
    }

    pub fn startLedger(self: *MemoryMatrix) !void {
        self.ledger_running.store(true, .seq_cst);
        self.ledger_thread = try std.Thread.spawn(.{}, ledgerWriterThread, .{self});
    }

    pub fn stopLedger(self: *MemoryMatrix) void {
        self.ledger_running.store(false, .seq_cst);
        if (self.ledger_thread) |*t| {
            t.join();
            self.ledger_thread = null;
        }
    }

    fn ledgerWriterThread(self: *MemoryMatrix) void {
        var file = std.fs.cwd().createFile("ledger.bin", .{ .truncate = false }) catch |err| {
            std.debug.print("Ledger thread error creating file: {}\n", .{err});
            return;
        };
        defer file.close();
        file.seekFromEnd(0) catch {};

        while (self.ledger_running.load(.seq_cst)) {
            var items_to_write: [128]InsightEntry = undefined;
            var write_count: usize = 0;

            self.ledger_mutex.lock();
            while (self.ledger_tail != self.ledger_head and write_count < 128) {
                items_to_write[write_count] = self.ledger_buffer[self.ledger_tail];
                self.ledger_tail = (self.ledger_tail + 1) % 1024;
                write_count += 1;
            }
            self.ledger_mutex.unlock();

            if (write_count > 0) {
                const bytes = std.mem.sliceAsBytes(items_to_write[0..write_count]);
                file.writeAll(bytes) catch {};
            } else {
                std.time.sleep(50 * std.time.ns_per_ms);
            }
        }
    }

    pub fn logInsight(self: *MemoryMatrix, entry: InsightEntry) void {
        self.ledger_mutex.lock();
        defer self.ledger_mutex.unlock();
        const next_head = (self.ledger_head + 1) % 1024;
        if (next_head != self.ledger_tail) {
            self.ledger_buffer[self.ledger_head] = entry;
            self.ledger_head = next_head;
        }
    }

    pub fn applyEntropyMask(self: *MemoryMatrix) void {
        const vectors = self.concepts.items(.vector);
        if (vectors.len == 0) return;
        
        // Reset counts
        @memset(self.global_bit_counts, 0);
        
        // Accumulate bit frequencies. Walk only the SET bits via @ctz instead of
        // testing all 64 positions per block — roughly halves the work and drops
        // the per-bit shift+mask branch.
        for (vectors) |v| {
            for (0..128) |block_idx| {
                var word = v[block_idx];
                const base = block_idx * 64;
                while (word != 0) {
                    const t = @ctz(word);
                    self.global_bit_counts[base + t] += 1;
                    word &= word - 1;
                }
            }
        }
        
        const threshold = @as(u32, @intFromFloat(@as(f32, @floatFromInt(vectors.len)) * 0.65));
        var new_mask: Hypervector = [_]u64{0} ** 128;
        
        for (0..128) |block_idx| {
            var block_mask: u64 = 0;
            for (0..64) |bit_idx| {
                const count = self.global_bit_counts[block_idx * 64 + bit_idx];
                if (count <= threshold) {
                    block_mask |= (@as(u64, 1) << @intCast(bit_idx));
                }
            }
            new_mask[block_idx] = block_mask;
        }
        self.entropy_mask = new_mask;
    }

    pub fn deinit(self: *MemoryMatrix) void {
        self.stopLedger();
        self.allocator.free(self.ledger_buffer);
        self.allocator.free(self.global_bit_counts);
        self.concepts.deinit(self.allocator);
        var it = self.words.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.words.deinit();
    }

    pub fn getOrInitWord(self: *MemoryMatrix, word: []const u8) !*WordConcept {
        const result = try self.words.getOrPut(word);
        if (!result.found_existing) {
            const key_copy = try self.allocator.dupe(u8, word);
            result.key_ptr.* = key_copy;
            
            const seed = std.hash.Wyhash.hash(0, key_copy);
            var prng = std.Random.DefaultPrng.init(seed);
            
            result.value_ptr.* = .{
                .identity = hv.initRandom(prng.random()),
                .context = hv.initRandom(prng.random()),
                .count = 1,
            };
            result.value_ptr.context = result.value_ptr.identity;
        }
        return result.value_ptr;
    }

    pub fn addConcept(self: *MemoryMatrix, vector: Hypervector) !void {
        try self.concepts.append(self.allocator, .{ .vector = vector, .salience = 1.0, .crystallized = false });
    }
};

pub fn tokenizeAndGround(matrix: *MemoryMatrix, text: []const u8) !Hypervector {
    var tokens = std.ArrayList([]const u8).init(matrix.allocator);
    defer tokens.deinit();

    var iter = std.mem.tokenizeAny(u8, text, " \t\r\n.,!?;:()[]\"'");
    while (iter.next()) |token| {
        const lower_token = try matrix.allocator.dupe(u8, token);
        for (lower_token, 0..) |c, i| lower_token[i] = std.ascii.toLower(c);
        try tokens.append(lower_token);
    }
    defer {
        for (tokens.items) |t| matrix.allocator.free(t);
    }

    if (tokens.items.len == 0) {
        var prng = std.Random.DefaultPrng.init(0);
        return hv.initRandom(prng.random());
    }

    // Ensure all words exist in dictionary (may trigger map resize)
    for (tokens.items) |t| {
        _ = try matrix.getOrInitWord(t);
    }

    // First, compute the unpermuted sentence-level semantic anchor
    var sentence_bow = matrix.words.getPtr(tokens.items[0]).?.identity;
    for (1..tokens.items.len) |i| {
        sentence_bow = hv.bundle(sentence_bow, matrix.words.getPtr(tokens.items[i]).?.identity, sentence_bow);
    }

    for (0..tokens.items.len) |i| {
        const wc = matrix.words.getPtr(tokens.items[i]).?;
        
        var left_context: ?Hypervector = null;
        var right_context: ?Hypervector = null;
        
        if (i > 0) {
            const left_wc = matrix.words.getPtr(tokens.items[i-1]).?;
            left_context = hv.inversePermute(left_wc.identity, 1);
        }
        if (i + 1 < tokens.items.len) {
            const right_wc = matrix.words.getPtr(tokens.items[i+1]).?;
            right_context = hv.permute(right_wc.identity, 1);
        }
        
        var local_ctx: Hypervector = wc.identity;
        if (left_context != null and right_context != null) {
            local_ctx = hv.bundle(left_context.?, right_context.?, wc.identity);
        } else if (left_context != null) {
            local_ctx = hv.bundle(left_context.?, wc.identity, wc.identity);
        } else if (right_context != null) {
            local_ctx = hv.bundle(right_context.?, wc.identity, wc.identity);
        }
        
        // Deep semantic bond: Bundle the permuted local window with the global sentence anchor
        local_ctx = hv.bundle(local_ctx, sentence_bow, wc.identity);
        
        // Accumulate Contextual Vector using the sentence anchor as the tiebreaker to drive rapid convergence
        wc.context = hv.bundle(wc.context, local_ctx, sentence_bow);
    }

    // Return the majority bundled context of the sentence
    var text_vector = matrix.words.getPtr(tokens.items[0]).?.context;
    for (1..tokens.items.len) |i| {
        const next_word = matrix.words.getPtr(tokens.items[i]).?.context;
        text_vector = hv.bundle(text_vector, next_word, sentence_bow);
    }

    return text_vector;
}

pub const MacroConcept = struct {
    action_a: u8,
    action_b: u8,
    vector: hv.Hypervector,
    crystallized: bool,
};

pub const ActionMatrix = struct {
    macros: [1024]MacroConcept,
    macro_count: usize,
    action_attractor: hv.Hypervector,
    
    pub fn init(rand: std.Random) ActionMatrix {
        return .{
            .macros = undefined,
            .macro_count = 0,
            .action_attractor = hv.initRandom(rand),
        };
    }
    
    pub fn accumulateAttractor(self: *ActionMatrix, state_vec: hv.Hypervector, macro_vec: hv.Hypervector, rand: std.Random) void {
        const binding = hv.bind(state_vec, macro_vec);
        const tiebreaker = hv.initRandom(rand);
        self.action_attractor = hv.bundle(self.action_attractor, binding, tiebreaker);
    }
    
    pub fn compileMacro(self: *ActionMatrix, a: u8, b: u8, vec_a: hv.Hypervector, vec_b: hv.Hypervector) *MacroConcept {
        const macro_vec = hv.bind(hv.permute(vec_a, 1), vec_b);
        if (self.macro_count >= 1024) return &self.macros[0]; // simplistic fallback
        const idx = self.macro_count;
        self.macros[idx] = .{
            .action_a = a,
            .action_b = b,
            .vector = macro_vec,
            .crystallized = false,
        };
        self.macro_count += 1;
        return &self.macros[idx];
    }
};

pub const VMEncoding = struct {
    opcodes: [5]hv.Hypervector,
    
    pub fn init(rand: std.Random) VMEncoding {
        var enc: VMEncoding = undefined;
        for (0..5) |i| enc.opcodes[i] = hv.initRandom(rand);
        return enc;
    }
    
    pub fn unbindProgram(self: *const VMEncoding, program_vector: hv.Hypervector, out_bytecode: []u8) usize {
        var current_vec = program_vector;
        var length: usize = 0;
        
        while (length < out_bytecode.len) {
            var best_op: u8 = 0;
            var best_dist: f32 = 1.0;
            
            for (0..5) |i| {
                const dist = hv.hammingDistance(current_vec, self.opcodes[i]);
                if (dist < best_dist) {
                    best_dist = dist;
                    best_op = @as(u8, @intCast(i));
                }
            }
            
            if (best_dist > 0.40 or best_op == 0) break; // NOP or noise
            
            out_bytecode[length] = best_op;
            length += 1;
            
            current_vec = hv.bind(current_vec, self.opcodes[best_op]);
            current_vec = hv.inversePermute(current_vec, 1);
        }
        return length;
    }
};

pub const MetaClass = enum(u8) {
    STABILITY_TREND = 0,
    OSCILLATION_TREND = 1,
    CHAOS_TREND = 2,
};

pub const Layer1MetaSpace = struct {
    class_vectors: [3]hv.Hypervector,
    
    pub fn init(rand: std.Random) Layer1MetaSpace {
        var space: Layer1MetaSpace = undefined;
        for (0..3) |i| space.class_vectors[i] = hv.initRandom(rand);
        return space;
    }
    
    pub fn compressSensoryHistory(self: *Layer1MetaSpace, history: []const hv.Hypervector, rand: std.Random) hv.Hypervector {
        _ = self;
        var chronicle = hv.initRandom(rand);
        for (0..history.len) |i| {
            const tiebreaker = hv.initRandom(rand);
            const permuted = hv.permute(history[i], i);
            chronicle = hv.bundle(chronicle, permuted, tiebreaker);
        }
        return chronicle;
    }
    
    pub fn classifyChronicle(self: *Layer1MetaSpace, chronicle: hv.Hypervector) MetaClass {
        var best_class: u8 = 0;
        var best_dist: f32 = 1.0;
        
        for (0..3) |i| {
            const dist = hv.hammingDistance(chronicle, self.class_vectors[i]);
            if (dist < best_dist) {
                best_dist = dist;
                best_class = @as(u8, @intCast(i));
            }
        }
        return @as(MetaClass, @enumFromInt(best_class));
    }
};

pub const ExecutiveControlMatrix = struct {
    control_vectors: [3]hv.Hypervector,
    
    pub fn init(vm_enc: *const VMEncoding) ExecutiveControlMatrix {
        var exec: ExecutiveControlMatrix = undefined;
        // STABILITY_TREND (0): NOP (Do nothing)
        exec.control_vectors[0] = vm_enc.opcodes[0];
        
        // OSCILLATION_TREND (1): SET_ALPHA 0 (Freeze learning)
        // [1, 0] -> SET_ALPHA (1), NOP (0) -> alpha = 0 * 0.10 = 0.0
        exec.control_vectors[1] = hv.bind(vm_enc.opcodes[1], hv.permute(vm_enc.opcodes[0], 1));
        
        // CHAOS_TREND (2): SET_THRESHOLD 3 (Widen threshold)
        // [2, 3] -> SET_THRESH (2), MASK_SHIFT (3) -> threshold = 3 * 0.05 = 0.15
        exec.control_vectors[2] = hv.bind(vm_enc.opcodes[2], hv.permute(vm_enc.opcodes[3], 1));
        
        return exec;
    }
};

pub fn evaluateAndDecay(matrix: *MemoryMatrix, target: Hypervector) f32 {
    const vectors = matrix.concepts.items(.vector);
    const saliences = matrix.concepts.items(.salience);
    const crystallized = matrix.concepts.items(.crystallized);
    if (vectors.len == 0) return 1.0;

    var min_dist: f32 = 1.0;
    var best_idx: ?usize = null;

    for (vectors, 0..) |v, i| {
        const dist = hv.hammingDistance(target, v);
        if (dist < min_dist) {
            min_dist = dist;
            best_idx = i;
        }
    }

    const DECAY_RATE: f32 = 0.05; // Drop by 5% per cycle
    const BOOST_RATE: f32 = 0.20;
    const PRUNE_THRESHOLD: f32 = 0.10;

    var i: usize = 0;
    while (i < matrix.concepts.len) {
        if (best_idx != null and i == best_idx.?) {
            if (!crystallized[i]) {
                saliences[i] += BOOST_RATE;
                if (saliences[i] >= 2.0) {
                    saliences[i] = 2.0;
                    crystallized[i] = true;
                }
            }
            i += 1;
        } else {
            if (!crystallized[i]) {
                saliences[i] -= DECAY_RATE;
                if (saliences[i] < PRUNE_THRESHOLD) {
                    // If the element we are swapping in from the end was the best_idx, update best_idx
                    if (best_idx != null and best_idx.? == matrix.concepts.len - 1) {
                        best_idx = i;
                    }
                    matrix.concepts.swapRemove(i);
                } else {
                    i += 1;
                }
            } else {
                i += 1;
            }
        }
    }

    return min_dist;
}

pub fn reflectAndConsolidate(matrix: *MemoryMatrix) void {
    const REDUNDANT_THRESHOLD: f32 = 0.05; // similarity > 0.95 means distance < 0.05
    
    var i: usize = 0;
    while (i < matrix.concepts.len) {
        if (!matrix.concepts.items(.crystallized)[i]) {
            i += 1;
            continue;
        }
        
        var j: usize = i + 1;
        while (j < matrix.concepts.len) {
            if (!matrix.concepts.items(.crystallized)[j]) {
                j += 1;
                continue;
            }
            
            const v1 = matrix.concepts.items(.vector)[i];
            const v2 = matrix.concepts.items(.vector)[j];
            const dist = hv.hammingDistance(v1, v2);
            
            if (dist < REDUNDANT_THRESHOLD) {
                // Merge via bitwise majority-vote bundling using v1 as tiebreaker
                const merged_v = hv.bundle(v1, v2, v1);
                matrix.concepts.items(.vector)[i] = merged_v;
                matrix.concepts.swapRemove(j);
                // Do not increment j, because a new element was swapped into j
            } else {
                j += 1;
            }
        }
        i += 1;
    }
}

pub fn computeSystemEnergy(target: Hypervector, matrix: *const MemoryMatrix) f32 {
    const vectors = matrix.concepts.items(.vector);
    if (vectors.len == 0) return 1.0; // max energy if empty

    var min_energy: f32 = 1.0;
    // Finding the minimum distance maps conceptually to finding local minima in Hopfield energy landscape
    for (vectors) |v| {
        const dist = hv.hammingDistance(target, v);
        if (dist < min_energy) {
            min_energy = dist;
        }
    }
    return min_energy;
}

pub fn attractVectorsPtr(rand: std.Random, a: *Hypervector, b: *const Hypervector, alpha: f32) void {
    const dist = hv.hammingDistance(a.*, b.*);
    
    if (dist < 0.25) {
        // Forcefield Repulsion: bounce back if dangerously close
        const beta: f32 = 0.05;
        for (0..128) |i| {
            var match = ~(a[i] ^ b[i]); // matching bits
            var flip_mask: u64 = 0;
            while (match != 0) {
                const tz = @ctz(match);
                if (rand.float(f32) < beta) {
                    flip_mask |= (@as(u64, 1) << @as(u6, @intCast(tz)));
                }
                match &= match - 1;
            }
            a[i] ^= flip_mask;
        }
    } else {
        // Attraction: pull closer
        for (0..128) |i| {
            var diff = a[i] ^ b[i];
            var flip_mask: u64 = 0;
            while (diff != 0) {
                const tz = @ctz(diff);
                if (rand.float(f32) < alpha) {
                    flip_mask |= (@as(u64, 1) << @as(u6, @intCast(tz)));
                }
                diff &= diff - 1;
            }
            a[i] ^= flip_mask;
        }
    }
}

// CP3: pure attraction — the attraction branch of attractVectorsPtr WITHOUT the
// "repulsion if dist < 0.25" forcefield. dynamics_probe proved this floor caps
// forward-model prediction error at ~0.24 (vs ~0.04 without it). This lets the
// eval harness test whether removing the floor for *rule* learning converts the
// 5.4x prediction-error win into better *control*.
pub fn attractVectorsPtrPure(rand: std.Random, a: *Hypervector, b: *const Hypervector, alpha: f32) void {
    for (0..128) |i| {
        var diff = a[i] ^ b[i];
        var flip_mask: u64 = 0;
        while (diff != 0) {
            const tz = @ctz(diff);
            if (rand.float(f32) < alpha) {
                flip_mask |= (@as(u64, 1) << @as(u6, @intCast(tz)));
            }
            diff &= diff - 1;
        }
        a[i] ^= flip_mask;
    }
}

pub fn attractVectors(matrix: *MemoryMatrix, rand: std.Random, index_a: usize, index_b: usize, alpha: f32) void {
    const vectors = matrix.concepts.items(.vector);
    attractVectorsPtr(rand, &vectors[index_a], &vectors[index_b], alpha);
    attractVectorsPtr(rand, &vectors[index_b], &vectors[index_a], alpha);
}

pub fn verifyGlobalOrthogonality(matrix: *MemoryMatrix) bool {
    var all_vectors = std.ArrayList(Hypervector).init(matrix.allocator);
    defer all_vectors.deinit();

    for (matrix.concepts.items(.vector)) |v| {
        all_vectors.append(v) catch {};
    }
    var it = matrix.words.iterator();
    while (it.next()) |entry| {
        all_vectors.append(entry.value_ptr.context) catch {};
    }

    if (all_vectors.items.len < 2) return true;

    var total_dist: f32 = 0;
    var pairs: usize = 0;

    for (0..all_vectors.items.len) |i| {
        for ((i + 1)..all_vectors.items.len) |j| {
            const dist = hv.hammingDistance(all_vectors.items[i], all_vectors.items[j]);
            if (dist < 0.10) return false;
            total_dist += dist;
            pairs += 1;
        }
    }

    const avg_dist = total_dist / @as(f32, @floatFromInt(pairs));
    if (avg_dist < 0.25) return false;
    
    return true;
}

pub fn bindRule(matrix: *const MemoryMatrix, subject: Hypervector, action: Hypervector, object: Hypervector) Hypervector {
    const b_subj = hv.permute(hv.bind(subject, matrix.role_subject), 1);
    const b_act = hv.permute(hv.bind(action, matrix.role_action), 2);
    const b_obj = hv.permute(hv.bind(object, matrix.role_object), 3);
    return hv.bundle(b_subj, b_act, b_obj);
}

pub fn traceInference(matrix: *const MemoryMatrix, fact: Hypervector, rule: Hypervector) Hypervector {
    // Single-rule object readout. bindRule() stored the object as
    // permute(bind(object, role_object), 3). Rotation commutes with the bitwise
    // majority used by bundle, so inverse-permuting by 3 and unbinding role_object
    // recovers the object filler ABOVE CHANCE (not cleanly — the other two bundled
    // role-terms remain as crosstalk; see tests.zig "VSA role-binding recovers the
    // object above chance"). With a single rule there is nothing to disambiguate,
    // so `fact` is unused here; it stays in the signature for the multi-rule case,
    // where `fact` would cue which stored rule to read.
    _ = fact;
    return hv.bind(hv.inversePermute(rule, 3), matrix.role_object);
}
