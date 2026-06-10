const std = @import("std");

pub const Tokenizer = struct {
    allocator: std.mem.Allocator,
    vocab_to_id: std.StringHashMap(u32),
    id_to_vocab: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator, tokenizer_path: []const u8) !*Tokenizer {
        const self = try allocator.create(Tokenizer);
        
        self.vocab_to_id = std.StringHashMap(u32).init(allocator);
        self.id_to_vocab = std.ArrayList([]const u8).init(allocator);
        
        // Pre-allocate to prevent massive reallocations
        try self.id_to_vocab.ensureTotalCapacity(130000);

        const file = try std.fs.cwd().openFile(tokenizer_path, .{});
        defer file.close();
        
        const file_size = (try file.stat()).size;
        const json_data = try file.readToEndAlloc(allocator, file_size);
        defer allocator.free(json_data);
        
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_data, .{});
        defer parsed.deinit();
        
        const model = parsed.value.object.get("model").?.object;
        const vocab = model.get("vocab").?.object;
        
        // It's crucial we populate id_to_vocab correctly since IDs might not be perfectly sequential
        // Find max ID first
        var max_id: u32 = 0;
        var it = vocab.iterator();
        while (it.next()) |entry| {
            const id = @as(u32, @intCast(entry.value_ptr.*.integer));
            if (id > max_id) max_id = id;
        }
        
        try self.id_to_vocab.resize(max_id + 1);
        @memset(self.id_to_vocab.items, ""); // Empty string for missing tokens
        
        it = vocab.iterator();
        while (it.next()) |entry| {
            const token_str = try allocator.dupe(u8, entry.key_ptr.*);
            const id = @as(u32, @intCast(entry.value_ptr.*.integer));
            
            try self.vocab_to_id.put(token_str, id);
            self.id_to_vocab.items[id] = token_str;
        }
        
        return self;
    }

    pub fn deinit(self: *Tokenizer) void {
        var it = self.vocab_to_id.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.vocab_to_id.deinit();
        self.id_to_vocab.deinit();
        self.allocator.destroy(self);
    }

    pub fn decode(self: *Tokenizer, token_id: u32) []const u8 {
        if (token_id >= self.id_to_vocab.items.len) return "";
        
        const raw_str = self.id_to_vocab.items[token_id];
        
        // DeepSeek/Llama uses byte-level BPE where 'Ġ' (U+0120) represents a space
        // We will do a basic replacement of 'Ġ' with ' ' for standard output
        // Note: For a true BPE decoder, we need to map the byte-level characters back.
        // But for terminal UI, this will get us legible text immediately.
        return raw_str;
    }
    
    // Naive Greedy Encoder (For testing prompts like "whats 1+1")
    pub fn encode(self: *Tokenizer, text: []const u8, out_tokens: *std.ArrayList(u32)) !void {
        var i: usize = 0;
        while (i < text.len) {
            var best_len: usize = 0;
            var best_id: u32 = 0;
            
            // Search for the longest matching substring in our vocabulary
            var test_len = text.len - i;
            while (test_len > 0) : (test_len -= 1) {
                const sub = text[i .. i + test_len];
                if (self.vocab_to_id.get(sub)) |id| {
                    best_len = test_len;
                    best_id = id;
                    break;
                }
            }
            
            if (best_len > 0) {
                try out_tokens.append(best_id);
                i += best_len;
            } else {
                // Unknown character, skip or add unknown token
                i += 1; 
            }
        }
    }
};
