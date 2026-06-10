const std = @import("std");
const engine = @import("engine.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    try stdout.print("\n", .{});
    try stdout.print("===================================================\n", .{});
    try stdout.print("      BITFORGE GHOST ENGINE: INTERACTIVE CLI       \n", .{});
    try stdout.print("===================================================\n", .{});
    try stdout.print("[*] Booting 100GB Logic Core into Memory...\n", .{});

    // Initialize the engine (MMAPs the logic cores, boots tokenizer, sets up KV cache)
    var ghost = try engine.GhostEngine.init(alloc);
    defer ghost.deinit();

    try stdout.print("[*] Engine Online. Type 'exit' or 'quit' to terminate.\n", .{});
    try stdout.print("===================================================\n\n", .{});

    const logits = try alloc.alloc(f32, ghost.vocab_size);
    defer alloc.free(logits);
    
    var input_buffer: [4096]u8 = undefined;

    while (true) {
        try stdout.print("User> ", .{});
        
        // 1. Get user input
        const user_input = try stdin.readUntilDelimiterOrEof(&input_buffer, '\n');
        if (user_input == null) break;
        
        const text = std.mem.trim(u8, user_input.?, " \r\n\t");
        if (text.len == 0) continue;
        if (std.mem.eql(u8, text, "exit") or std.mem.eql(u8, text, "quit")) break;

        // 2. Tokenize the prompt
        var tokens = std.ArrayList(u32).init(alloc);
        defer tokens.deinit();
        try ghost.tk_ctx.encode(text, &tokens);
        
        try stdout.print("\nGhost> ", .{});

        // 3. Pre-fill Phase (Process prompt tokens into the KV cache)
        for (tokens.items, 0..) |tok, i| {
            try ghost.forward(tok, i, logits);
        }

        // 4. Generation Loop Phase
        var current_pos = tokens.items.len;
        const max_generation = 1000;
        const EOS_TOKEN = 128001; // Standard DeepSeek/Llama-3 EOS token ID
        
        // Sample the first generated token
        std.debug.print("Logits: {any}\n", .{logits[0..5]});
        var next_token = try ghost.gen_sampler.sample(logits, 0.7, 50, 0.95);

        while (next_token != EOS_TOKEN and current_pos < max_generation) {
            // Decode and print the token instantly (Streaming)
            const word = ghost.tk_ctx.decode(next_token);
            
            // Clean up BPE space characters (Ġ) for readability
            var clean_word = word;
            if (std.mem.startsWith(u8, word, "Ġ")) {
                try stdout.print(" ", .{});
                clean_word = word[2..]; // Ġ is often 2 bytes in UTF-8
            }
            try stdout.print("{s}", .{clean_word});
            
            // Forward pass for the next token
            try ghost.forward(next_token, current_pos, logits);
            
            // Sample the next token
            next_token = try ghost.gen_sampler.sample(logits, 0.7, 50, 0.95);
            current_pos += 1;
        }

        try stdout.print("\n\n", .{});
    }

    try stdout.print("\n[*] Engine Terminated.\n", .{});
}
