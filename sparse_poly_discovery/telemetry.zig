const std = @import("std");

pub const MatrixStatePacket = struct {
    prediction_error: f32,
    latest_action: u8,
    system_energy: f32,
    failed_state: bool,
    active_macro_tools: u32,
    vm_bytecode: [8]u8,
    vm_bytecode_len: u8,
    meta_class: u8,
};

pub const TelemetryServer = struct {
    server: std.net.Server,
    thread: ?std.Thread,
    running: std.atomic.Value(bool),
    current_packet: std.Thread.Mutex,
    latest_packet: ?MatrixStatePacket,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !*TelemetryServer {
        const address = try std.net.Address.parseIp("127.0.0.1", 8080);
        const server = try address.listen(.{ .reuse_address = true });
        
        const self = try allocator.create(TelemetryServer);
        self.server = server;
        self.thread = null;
        self.running = std.atomic.Value(bool).init(false);
        self.current_packet = std.Thread.Mutex{};
        self.latest_packet = null;
        self.allocator = allocator;
        return self;
    }

    pub fn deinit(self: *TelemetryServer) void {
        self.stop();
        self.server.deinit();
        self.allocator.destroy(self);
    }

    pub fn pushPacket(self: *TelemetryServer, packet: MatrixStatePacket) void {
        self.current_packet.lock();
        // Free old strings if needed (we'll assume the packet owns the strings and we copy them, but to keep it simple we can just copy max 32 bytes or rely on static strings).
        // Since words from the connectome are stored permanently, we can safely just store the slices!
        self.latest_packet = packet;
        self.current_packet.unlock();
    }

    pub fn start(self: *TelemetryServer) !void {
        self.running.store(true, .seq_cst);
        self.thread = try std.Thread.spawn(.{}, serverThread, .{self});
    }

    pub fn stop(self: *TelemetryServer) void {
        self.running.store(false, .seq_cst);
        // Force unblock accept by connecting to it
        if (std.net.tcpConnectToAddress(self.server.listen_address)) |conn| {
            conn.close();
        } else |_| {}
        
        if (self.thread) |*t| {
            t.join();
            self.thread = null;
        }
    }

    fn serverThread(self: *TelemetryServer) void {
        while (self.running.load(.seq_cst)) {
            const conn = self.server.accept() catch |err| {
                if (err == error.SocketNotListening) break;
                continue;
            };
            
            if (!self.running.load(.seq_cst)) {
                conn.stream.close();
                break;
            }

            self.handleConnection(conn.stream) catch |err| {
                std.debug.print("[Telemetry] Connection error: {}\n", .{err});
            };
            conn.stream.close();
        }
    }

    fn handleConnection(self: *TelemetryServer, stream: std.net.Stream) !void {
        var buf: [4096]u8 = undefined;
        const bytes_read = try stream.read(&buf);
        const req = buf[0..bytes_read];
        
        if (std.mem.indexOf(u8, req, "Upgrade: websocket") == null) {
            return;
        }

        const key_start_label = "Sec-WebSocket-Key: ";
        const key_idx = std.mem.indexOf(u8, req, key_start_label) orelse return;
        const key_end_idx = std.mem.indexOfPos(u8, req, key_idx, "\r\n") orelse return;
        const ws_key = req[key_idx + key_start_label.len .. key_end_idx];

        var magic_buf: [256]u8 = undefined;
        const magic_str = try std.fmt.bufPrint(&magic_buf, "{s}258EAFA5-E914-47DA-95CA-C5AB0DC85B11", .{ws_key});
        
        var sha1 = std.crypto.hash.Sha1.init(.{});
        sha1.update(magic_str);
        const hash = sha1.finalResult();
        
        var accept_key: [128]u8 = undefined;
        const b64_encoder = std.base64.standard.Encoder;
        const encoded_len = b64_encoder.calcSize(hash.len);
        _ = b64_encoder.encode(accept_key[0..encoded_len], &hash);
        
        const response_fmt = 
            "HTTP/1.1 101 Switching Protocols\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Accept: {s}\r\n\r\n";
            
        try stream.writer().print(response_fmt, .{accept_key[0..encoded_len]});

        // Continuously send packets
        while (self.running.load(.seq_cst)) {
            std.time.sleep(100 * std.time.ns_per_ms);
            
            self.current_packet.lock();
            const packet_opt = self.latest_packet;
            self.current_packet.unlock();

            if (packet_opt) |packet| {
                var json_buf = std.ArrayList(u8).init(self.allocator);
                defer json_buf.deinit();
                try std.json.stringify(packet, .{}, json_buf.writer());
                
                try writeWsFrame(stream.writer(), json_buf.items);
            }
        }
    }

    fn writeWsFrame(writer: anytype, payload: []const u8) !void {
        try writer.writeByte(0x81); // FIN + Text
        if (payload.len < 126) {
            try writer.writeByte(@intCast(payload.len));
        } else if (payload.len <= 65535) {
            try writer.writeByte(126);
            try writer.writeInt(u16, @intCast(payload.len), .big);
        } else {
            return error.PayloadTooLarge;
        }
        try writer.writeAll(payload);
    }
};
