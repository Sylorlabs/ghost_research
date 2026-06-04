const std = @import("std");

pub const Percept = struct {
    r0: u64,
    r1: u64,
};

pub const PerceptionEngine = struct {
    allocator: std.mem.Allocator,
    corpus_dir: std.fs.Dir,
    current_file: ?std.fs.File = null,
    reader: ?std.fs.File.Reader = null,
    
    pub fn init(allocator: std.mem.Allocator, path: []const u8) !PerceptionEngine {
        return .{
            .allocator = allocator,
            .corpus_dir = try std.fs.cwd().openDir(path, .{ .iterate = true }),
        };
    }

    pub fn deinit(self: *PerceptionEngine) void {
        if (self.current_file) |f| f.close();
        self.corpus_dir.close();
    }

    /// NextPercept fulfills the 'High-Bandwidth Ingestion' directive.
    /// It reads 16 bytes from the corpus and returns them as a 128-bit state.
    pub fn nextPercept(self: *PerceptionEngine) !?Percept {
        if (self.current_file == null) {
            var it = self.corpus_dir.iterate();
            if (try it.next()) |entry| {
                if (entry.kind == .file) {
                    self.current_file = try self.corpus_dir.openFile(entry.name, .{});
                    self.reader = self.current_file.?.reader();
                } else return try self.nextPercept();
            } else return null; // End of corpus
        }

        var buf: [16]u8 = undefined;
        const bytes_read = try self.reader.?.readAll(&buf);
        
        if (bytes_read < 16) {
            self.current_file.?.close();
            self.current_file = null;
            return try self.nextPercept();
        }

        return Percept{
            .r0 = std.mem.readInt(u64, buf[0..8], .little),
            .r1 = std.mem.readInt(u64, buf[8..16], .little),
        };
    }
};
