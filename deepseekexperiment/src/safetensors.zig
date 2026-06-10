const std = @import("std");
const posix = std.posix;

pub const Tensor = struct {
    dtype: []const u8,
    shape: []usize,
    data_offsets: [2]usize,
    data: []const u8,
};

pub const SafetensorsFile = struct {
    allocator: std.mem.Allocator,
    file: std.fs.File,
    mmap_data: []align(4096) const u8,
    metadata: std.json.Parsed(std.json.Value),
    tensors: std.StringHashMap(Tensor),

    pub fn load(allocator: std.mem.Allocator, path: []const u8) !*SafetensorsFile {
        const file = try std.fs.cwd().openFile(path, .{});
        errdefer file.close();

        const stat = try file.stat();
        
        // Memory map the file (Read Only)
        const mmap_data = try posix.mmap(
            null,
            stat.size,
            posix.PROT.READ,
            .{ .TYPE = .SHARED },
            file.handle,
            0,
        );
        errdefer posix.munmap(mmap_data);

        // Safetensors format: First 8 bytes are the length of the JSON header (little endian u64)
        if (mmap_data.len < 8) return error.FileTooSmall;
        const header_len = std.mem.readInt(u64, mmap_data[0..8], .little);
        
        if (mmap_data.len < 8 + header_len) return error.InvalidHeaderLength;
        const header_bytes = mmap_data[8 .. 8 + header_len];

        // Parse JSON
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, header_bytes, .{});
        errdefer parsed.deinit();

        var tensors = std.StringHashMap(Tensor).init(allocator);
        
        const root_obj = parsed.value.object;
        var it = root_obj.iterator();
        while (it.next()) |entry| {
            if (std.mem.eql(u8, entry.key_ptr.*, "__metadata__")) continue;
            
            const obj = entry.value_ptr.object;
            const dtype = obj.get("dtype").?.string;
            
            const shape_array = obj.get("shape").?.array;
            const shape = try allocator.alloc(usize, shape_array.items.len);
            for (shape_array.items, 0..) |item, i| {
                shape[i] = @intCast(item.integer);
            }
            
            const offsets = obj.get("data_offsets").?.array;
            const start_off = @as(usize, @intCast(offsets.items[0].integer));
            const end_off = @as(usize, @intCast(offsets.items[1].integer));
            
            const tensor_data = mmap_data[8 + header_len + start_off .. 8 + header_len + end_off];
            
            try tensors.put(entry.key_ptr.*, Tensor{
                .dtype = dtype,
                .shape = shape,
                .data_offsets = .{ start_off, end_off },
                .data = tensor_data,
            });
        }

        const st = try allocator.create(SafetensorsFile);
        st.* = .{
            .allocator = allocator,
            .file = file,
            .mmap_data = mmap_data,
            .metadata = parsed,
            .tensors = tensors,
        };
        return st;
    }

    pub fn deinit(self: *SafetensorsFile) void {
        var it = self.tensors.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.shape);
        }
        self.tensors.deinit();
        self.metadata.deinit();
        posix.munmap(self.mmap_data);
        self.file.close();
        self.allocator.destroy(self);
    }
};
