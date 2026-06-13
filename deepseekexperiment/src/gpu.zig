const std = @import("std");

// Import the raw C Vulkan Headers
const c = @cImport({
    @cInclude("vulkan/vulkan.h");
});

pub const GPUAccelerator = struct {
    allocator: std.mem.Allocator,
    
    instance: c.VkInstance,
    physical_device: c.VkPhysicalDevice,
    device: c.VkDevice,
    compute_queue: c.VkQueue,
    command_pool: c.VkCommandPool,
    
    shader_module: c.VkShaderModule,
    pipeline_layout: c.VkPipelineLayout,
    compute_pipeline: c.VkPipeline,
    
    shader_fp32_module: c.VkShaderModule,
    compute_fp32_pipeline: c.VkPipeline,
    
    descriptor_pool: c.VkDescriptorPool,
    descriptor_set_layout: c.VkDescriptorSetLayout,
    descriptor_set: c.VkDescriptorSet,
    
    in_buffer: c.VkBuffer,
    in_memory: c.VkDeviceMemory,
    weight_buffer: c.VkBuffer,
    weight_memory: c.VkDeviceMemory,
    out_buffer: c.VkBuffer,
    out_memory: c.VkDeviceMemory,

    pub fn init(allocator: std.mem.Allocator) !*GPUAccelerator {
        const self = try allocator.create(GPUAccelerator);
        
        // 1. Create Vulkan Instance
        var appInfo = std.mem.zeroes(c.VkApplicationInfo);
        appInfo.sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO;
        appInfo.pApplicationName = "BitForge Compute";
        appInfo.applicationVersion = c.VK_MAKE_VERSION(1, 0, 0);
        appInfo.pEngineName = "GhostEngine";
        appInfo.engineVersion = c.VK_MAKE_VERSION(1, 0, 0);
        appInfo.apiVersion = c.VK_API_VERSION_1_2;

        var createInfo = std.mem.zeroes(c.VkInstanceCreateInfo);
        createInfo.sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
        createInfo.pApplicationInfo = &appInfo;

        var instance: c.VkInstance = null;
        if (c.vkCreateInstance(&createInfo, null, &instance) != c.VK_SUCCESS) {
            return error.VulkanInstanceFailed;
        }

        // 2. Enumerate and Find AMD RX 5700 XT
        var deviceCount: u32 = 0;
        _ = c.vkEnumeratePhysicalDevices(instance, &deviceCount, null);
        if (deviceCount == 0) return error.NoVulkanDevicesFound;
        
        const physicalDevices = try allocator.alloc(c.VkPhysicalDevice, deviceCount);
        defer allocator.free(physicalDevices);
        _ = c.vkEnumeratePhysicalDevices(instance, &deviceCount, physicalDevices.ptr);
        
        const physical_device = physicalDevices[0]; // Assuming GPU 0 is the RX 5700 XT
        
        // 3. Create Logical Device & Queue
        var queuePriority: f32 = 1.0;
        var queueCreateInfo = std.mem.zeroes(c.VkDeviceQueueCreateInfo);
        queueCreateInfo.sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        queueCreateInfo.queueFamilyIndex = 0; // Assuming 0 supports compute
        queueCreateInfo.queueCount = 1;
        queueCreateInfo.pQueuePriorities = &queuePriority;

        var deviceCreateInfo = std.mem.zeroes(c.VkDeviceCreateInfo);
        deviceCreateInfo.sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        deviceCreateInfo.pQueueCreateInfos = &queueCreateInfo;
        deviceCreateInfo.queueCreateInfoCount = 1;

        var device: c.VkDevice = null;
        if (c.vkCreateDevice(physical_device, &deviceCreateInfo, null, &device) != c.VK_SUCCESS) {
            return error.VulkanDeviceFailed;
        }

        var compute_queue: c.VkQueue = null;
        c.vkGetDeviceQueue(device, 0, 0, &compute_queue);

        // 4. Command Pool
        var poolInfo = std.mem.zeroes(c.VkCommandPoolCreateInfo);
        poolInfo.sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
        poolInfo.queueFamilyIndex = 0;
        
        var command_pool: c.VkCommandPool = null;
        if (c.vkCreateCommandPool(device, &poolInfo, null, &command_pool) != c.VK_SUCCESS) {
            return error.VulkanCommandPoolFailed;
        }

        self.* = .{
            .allocator = allocator,
            .instance = instance,
            .physical_device = physical_device,
            .device = device,
            .compute_queue = compute_queue,
            .command_pool = command_pool,
            
            // Uninitialized handles (Require buffer allocations and SPIR-V loading in full scope)
            .shader_module = null,
            .pipeline_layout = null,
            .compute_pipeline = null,
            .shader_fp32_module = null,
            .compute_fp32_pipeline = null,
            .descriptor_pool = null,
            .descriptor_set_layout = null,
            .descriptor_set = null,
            .in_buffer = null,
            .in_memory = null,
            .weight_buffer = null,
            .weight_memory = null,
            .out_buffer = null,
            .out_memory = null,
        };
        
        return self;
    }

    pub fn loadPipeline(self: *GPUAccelerator, shader_path: []const u8) !void {
        const file = try std.fs.cwd().openFile(shader_path, .{});
        defer file.close();
        const stat = try file.stat();
        const code = try self.allocator.alloc(u32, stat.size / 4);
        defer self.allocator.free(code);
        
        _ = try file.readAll(std.mem.sliceAsBytes(code));
        
        var createInfo = std.mem.zeroes(c.VkShaderModuleCreateInfo);
        createInfo.sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
        createInfo.codeSize = stat.size;
        createInfo.pCode = code.ptr;

        if (c.vkCreateShaderModule(self.device, &createInfo, null, &self.shader_module) != c.VK_SUCCESS) {
            return error.VulkanShaderFailed;
        }

        // Create Descriptor Set Layout
        var bindings: [3]c.VkDescriptorSetLayoutBinding = undefined;
        for (0..3) |i| {
            bindings[i] = std.mem.zeroes(c.VkDescriptorSetLayoutBinding);
            bindings[i].binding = @intCast(i);
            bindings[i].descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
            bindings[i].descriptorCount = 1;
            bindings[i].stageFlags = c.VK_SHADER_STAGE_COMPUTE_BIT;
        }

        var layoutInfo = std.mem.zeroes(c.VkDescriptorSetLayoutCreateInfo);
        layoutInfo.sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
        layoutInfo.bindingCount = 3;
        layoutInfo.pBindings = &bindings[0];

        _ = c.vkCreateDescriptorSetLayout(self.device, &layoutInfo, null, &self.descriptor_set_layout);

        // Push Constants
        var pushConstant = std.mem.zeroes(c.VkPushConstantRange);
        pushConstant.stageFlags = c.VK_SHADER_STAGE_COMPUTE_BIT;
        pushConstant.offset = 0;
        pushConstant.size = 8; // two uints (input_dim, output_dim)

        var pipeLayoutInfo = std.mem.zeroes(c.VkPipelineLayoutCreateInfo);
        pipeLayoutInfo.sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
        pipeLayoutInfo.setLayoutCount = 1;
        pipeLayoutInfo.pSetLayouts = &self.descriptor_set_layout;
        pipeLayoutInfo.pushConstantRangeCount = 1;
        pipeLayoutInfo.pPushConstantRanges = &pushConstant;

        _ = c.vkCreatePipelineLayout(self.device, &pipeLayoutInfo, null, &self.pipeline_layout);

        var stageInfo = std.mem.zeroes(c.VkPipelineShaderStageCreateInfo);
        stageInfo.sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        stageInfo.stage = c.VK_SHADER_STAGE_COMPUTE_BIT;
        stageInfo.module = self.shader_module;
        stageInfo.pName = "main";

        var computeInfo = std.mem.zeroes(c.VkComputePipelineCreateInfo);
        computeInfo.sType = c.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
        computeInfo.stage = stageInfo;
        computeInfo.layout = self.pipeline_layout;

        _ = c.vkCreateComputePipelines(self.device, null, 1, &computeInfo, null, &self.compute_pipeline);

        // Load FP32 Pipeline
        const fp32_file = try std.fs.cwd().openFile("src/shaders/compute_fp32.spv", .{});
        defer fp32_file.close();
        const fp32_stat = try fp32_file.stat();
        const fp32_code = try self.allocator.alloc(u32, fp32_stat.size / 4);
        defer self.allocator.free(fp32_code);
        
        _ = try fp32_file.readAll(std.mem.sliceAsBytes(fp32_code));
        
        var fp32_createInfo = std.mem.zeroes(c.VkShaderModuleCreateInfo);
        fp32_createInfo.sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
        fp32_createInfo.codeSize = fp32_stat.size;
        fp32_createInfo.pCode = fp32_code.ptr;

        if (c.vkCreateShaderModule(self.device, &fp32_createInfo, null, &self.shader_fp32_module) != c.VK_SUCCESS) {
            return error.VulkanShaderFailed;
        }

        var fp32_stageInfo = std.mem.zeroes(c.VkPipelineShaderStageCreateInfo);
        fp32_stageInfo.sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        fp32_stageInfo.stage = c.VK_SHADER_STAGE_COMPUTE_BIT;
        fp32_stageInfo.module = self.shader_fp32_module;
        fp32_stageInfo.pName = "main";

        var fp32_computeInfo = std.mem.zeroes(c.VkComputePipelineCreateInfo);
        fp32_computeInfo.sType = c.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
        fp32_computeInfo.stage = fp32_stageInfo;
        fp32_computeInfo.layout = self.pipeline_layout;

        _ = c.vkCreateComputePipelines(self.device, null, 1, &fp32_computeInfo, null, &self.compute_fp32_pipeline);
    }

    pub fn dispatch(self: *GPUAccelerator, in_dim: u32, out_dim: u32, in_vec: []const f32, out_vec: []f32, w_blocks: []const u8) !void {
        // Use predefined max sizes to avoid reallocation
        const in_size: c.VkDeviceSize = in_vec.len * 4;
        const w_size: c.VkDeviceSize = w_blocks.len;
        const out_size: c.VkDeviceSize = out_vec.len * 4;

        if (self.in_buffer == null) {
            const MAX_IN = 8192 * 4;
            const MAX_OUT = 130000 * 4;
            const MAX_W = @as(u64, 4000) * 1024 * 1024; // 4.0 GB for full FP32 vocab weights

            try self.createBuffer(MAX_IN, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, &self.in_buffer, &self.in_memory);
            try self.createBuffer(MAX_W, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, &self.weight_buffer, &self.weight_memory);
            try self.createBuffer(MAX_OUT, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, &self.out_buffer, &self.out_memory);

            // Allocate Descriptor Pool
            var poolSize = std.mem.zeroes(c.VkDescriptorPoolSize);
            poolSize.type = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
            poolSize.descriptorCount = 3;

            var poolInfo = std.mem.zeroes(c.VkDescriptorPoolCreateInfo);
            poolInfo.sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
            poolInfo.poolSizeCount = 1;
            poolInfo.pPoolSizes = &poolSize;
            poolInfo.maxSets = 1;

            _ = c.vkCreateDescriptorPool(self.device, &poolInfo, null, &self.descriptor_pool);

            // Allocate Descriptor Set
            var allocInfo = std.mem.zeroes(c.VkDescriptorSetAllocateInfo);
            allocInfo.sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
            allocInfo.descriptorPool = self.descriptor_pool;
            allocInfo.descriptorSetCount = 1;
            allocInfo.pSetLayouts = &self.descriptor_set_layout;
            
            _ = c.vkAllocateDescriptorSets(self.device, &allocInfo, &self.descriptor_set);

            // Update Descriptor Sets (Using whole size)
            var inInfo = std.mem.zeroes(c.VkDescriptorBufferInfo);
            inInfo.buffer = self.in_buffer;
            inInfo.offset = 0;
            inInfo.range = MAX_IN;

            var wInfo = std.mem.zeroes(c.VkDescriptorBufferInfo);
            wInfo.buffer = self.weight_buffer;
            wInfo.offset = 0;
            wInfo.range = MAX_W;

            var outInfo = std.mem.zeroes(c.VkDescriptorBufferInfo);
            outInfo.buffer = self.out_buffer;
            outInfo.offset = 0;
            outInfo.range = MAX_OUT;

            var writes: [3]c.VkWriteDescriptorSet = undefined;
            for (0..3) |i| {
                writes[i] = std.mem.zeroes(c.VkWriteDescriptorSet);
                writes[i].sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
                writes[i].dstSet = self.descriptor_set;
                writes[i].dstBinding = @intCast(i);
                writes[i].dstArrayElement = 0;
                writes[i].descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
                writes[i].descriptorCount = 1;
            }
            writes[0].pBufferInfo = &inInfo;
            writes[1].pBufferInfo = &wInfo;
            writes[2].pBufferInfo = &outInfo;

            c.vkUpdateDescriptorSets(self.device, 3, &writes[0], 0, null);
        }

        // 2. Upload Data
        var in_data: ?*anyopaque = null;
        _ = c.vkMapMemory(self.device, self.in_memory, 0, in_size, 0, &in_data);
        std.mem.copyForwards(u8, @as([*]u8, @ptrCast(in_data))[0..in_size], std.mem.sliceAsBytes(in_vec));
        c.vkUnmapMemory(self.device, self.in_memory);

        var w_data: ?*anyopaque = null;
        _ = c.vkMapMemory(self.device, self.weight_memory, 0, w_size, 0, &w_data);
        std.mem.copyForwards(u8, @as([*]u8, @ptrCast(w_data))[0..w_size], w_blocks);
        c.vkUnmapMemory(self.device, self.weight_memory);

        // 3. Dispatch Compute
        var cmdAllocInfo = std.mem.zeroes(c.VkCommandBufferAllocateInfo);
        cmdAllocInfo.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
        cmdAllocInfo.commandPool = self.command_pool;
        cmdAllocInfo.level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        cmdAllocInfo.commandBufferCount = 1;

        var commandBuffer: c.VkCommandBuffer = null;
        _ = c.vkAllocateCommandBuffers(self.device, &cmdAllocInfo, &commandBuffer);

        var beginInfo = std.mem.zeroes(c.VkCommandBufferBeginInfo);
        beginInfo.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        beginInfo.flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
        _ = c.vkBeginCommandBuffer(commandBuffer, &beginInfo);

        c.vkCmdBindPipeline(commandBuffer, c.VK_PIPELINE_BIND_POINT_COMPUTE, self.compute_pipeline);
        c.vkCmdBindDescriptorSets(commandBuffer, c.VK_PIPELINE_BIND_POINT_COMPUTE, self.pipeline_layout, 0, 1, &self.descriptor_set, 0, null);
        
        var push_data = [_]u32{ in_dim, out_dim };
        c.vkCmdPushConstants(commandBuffer, self.pipeline_layout, c.VK_SHADER_STAGE_COMPUTE_BIT, 0, 8, &push_data);

        c.vkCmdDispatch(commandBuffer, (out_dim + 63) / 64, 1, 1);
        _ = c.vkEndCommandBuffer(commandBuffer);

        var submitInfo = std.mem.zeroes(c.VkSubmitInfo);
        submitInfo.sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO;
        submitInfo.commandBufferCount = 1;
        submitInfo.pCommandBuffers = &commandBuffer;

        _ = c.vkQueueSubmit(self.compute_queue, 1, &submitInfo, null);
        _ = c.vkQueueWaitIdle(self.compute_queue);
        c.vkFreeCommandBuffers(self.device, self.command_pool, 1, &commandBuffer);

        // Fetch Results
        var mappedOut: ?*anyopaque = null;
        _ = c.vkMapMemory(self.device, self.out_memory, 0, out_size, 0, &mappedOut);
        const mappedOutPtr: [*]f32 = @ptrCast(@alignCast(mappedOut.?));
        @memcpy(out_vec, mappedOutPtr[0..out_vec.len]);
        c.vkUnmapMemory(self.device, self.out_memory);
    }

    pub fn dispatchFp32(self: *GPUAccelerator, in_dim: u32, out_dim: u32, in_vec: []const f32, out_vec: []f32, w_blocks: []const f32) !void {
        // Use predefined max sizes to avoid reallocation
        const in_size: c.VkDeviceSize = in_vec.len * 4;
        const w_size: c.VkDeviceSize = w_blocks.len * 4;
        const out_size: c.VkDeviceSize = out_vec.len * 4;

        if (self.in_buffer == null) {
            return error.BuffersNotInitialized;
        }

        // Upload Input
        var mappedIn: ?*anyopaque = null;
        _ = c.vkMapMemory(self.device, self.in_memory, 0, in_size, 0, &mappedIn);
        const mappedInPtr: [*]f32 = @ptrCast(@alignCast(mappedIn.?));
        @memcpy(mappedInPtr[0..in_vec.len], in_vec);
        c.vkUnmapMemory(self.device, self.in_memory);

        // Upload Weights (FP32 this time)
        var mappedW: ?*anyopaque = null;
        _ = c.vkMapMemory(self.device, self.weight_memory, 0, w_size, 0, &mappedW);
        const mappedWPtr: [*]f32 = @ptrCast(@alignCast(mappedW.?));
        @memcpy(mappedWPtr[0..w_blocks.len], w_blocks);
        c.vkUnmapMemory(self.device, self.weight_memory);

        var allocInfoCMD = std.mem.zeroes(c.VkCommandBufferAllocateInfo);
        allocInfoCMD.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
        allocInfoCMD.commandPool = self.command_pool;
        allocInfoCMD.level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        allocInfoCMD.commandBufferCount = 1;

        var commandBuffer: c.VkCommandBuffer = null;
        _ = c.vkAllocateCommandBuffers(self.device, &allocInfoCMD, &commandBuffer);

        var beginInfo = std.mem.zeroes(c.VkCommandBufferBeginInfo);
        beginInfo.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        beginInfo.flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;

        _ = c.vkBeginCommandBuffer(commandBuffer, &beginInfo);
        c.vkCmdBindPipeline(commandBuffer, c.VK_PIPELINE_BIND_POINT_COMPUTE, self.compute_fp32_pipeline);
        c.vkCmdBindDescriptorSets(commandBuffer, c.VK_PIPELINE_BIND_POINT_COMPUTE, self.pipeline_layout, 0, 1, &self.descriptor_set, 0, null);

        var push_data = [_]u32{ in_dim, out_dim };
        c.vkCmdPushConstants(commandBuffer, self.pipeline_layout, c.VK_SHADER_STAGE_COMPUTE_BIT, 0, 8, &push_data);

        c.vkCmdDispatch(commandBuffer, (out_dim + 255) / 256, 1, 1);
        _ = c.vkEndCommandBuffer(commandBuffer);

        var submitInfo = std.mem.zeroes(c.VkSubmitInfo);
        submitInfo.sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO;
        submitInfo.commandBufferCount = 1;
        submitInfo.pCommandBuffers = &commandBuffer;

        _ = c.vkQueueSubmit(self.compute_queue, 1, &submitInfo, null);
        _ = c.vkQueueWaitIdle(self.compute_queue);

        // Fetch Results
        var mappedOut: ?*anyopaque = null;
        _ = c.vkMapMemory(self.device, self.out_memory, 0, out_size, 0, &mappedOut);
        const mappedOutPtr: [*]f32 = @ptrCast(@alignCast(mappedOut.?));
        @memcpy(out_vec, mappedOutPtr[0..out_vec.len]);
        c.vkUnmapMemory(self.device, self.out_memory);
    }

    // Resident-weight GEMV benchmark: weights live in DEVICE_LOCAL VRAM
    // (uploaded once), command buffer pre-recorded, looped n_iters times.
    // Returns Gw/s (compute + per-call in/out transfer, NO weight re-upload).
    // Self-contained; does not touch the dispatch() buffers used by engine.zig.
    pub fn benchResidentGEMV(self: *GPUAccelerator, in_dim: u32, out_dim: u32, n_iters: usize, n_groups: u32) !f64 {
        const bpr = in_dim / 64;
        const w_bytes: c.VkDeviceSize = @as(u64, out_dim) * bpr * 12; // BitBlock = 12B
        const in_bytes: c.VkDeviceSize = in_dim * 4;
        const out_bytes: c.VkDeviceSize = out_dim * 4;

        var inb: c.VkBuffer = undefined;
        var inm: c.VkDeviceMemory = undefined;
        var wb: c.VkBuffer = undefined;
        var wm: c.VkDeviceMemory = undefined;
        var ob: c.VkBuffer = undefined;
        var om: c.VkDeviceMemory = undefined;
        const HV = c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
        const VRAM = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT | c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
        try self.createBuffer(in_bytes, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, HV, &inb, &inm);
        try self.createBuffer(w_bytes, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, VRAM, &wb, &wm);
        try self.createBuffer(out_bytes, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, HV, &ob, &om);

        var wp: ?*anyopaque = null;
        _ = c.vkMapMemory(self.device, wm, 0, w_bytes, 0, &wp);
        const wbytes_ptr: [*]u8 = @ptrCast(wp.?);
        var seed: u64 = 0x1234;
        var i: usize = 0;
        while (i < w_bytes) : (i += 12) {
            seed = seed *% 0x9E3779B97F4A7C15 +% 1;
            const lo: u32 = @truncate(seed);
            const hi: u32 = @truncate(seed >> 32);
            const sc: f32 = 0.05;
            @memcpy(wbytes_ptr[i .. i + 4], std.mem.asBytes(&lo));
            @memcpy(wbytes_ptr[i + 4 .. i + 8], std.mem.asBytes(&hi));
            @memcpy(wbytes_ptr[i + 8 .. i + 12], std.mem.asBytes(&sc));
        }
        c.vkUnmapMemory(self.device, wm);
        var ip: ?*anyopaque = null;
        _ = c.vkMapMemory(self.device, inm, 0, in_bytes, 0, &ip);
        const ifp: [*]f32 = @ptrCast(@alignCast(ip.?));
        for (0..in_dim) |k| ifp[k] = @floatFromInt(@as(u32, @truncate(k)) % 7);
        c.vkUnmapMemory(self.device, inm);

        var poolSize = std.mem.zeroes(c.VkDescriptorPoolSize);
        poolSize.type = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        poolSize.descriptorCount = 3;
        var poolInfo = std.mem.zeroes(c.VkDescriptorPoolCreateInfo);
        poolInfo.sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
        poolInfo.poolSizeCount = 1;
        poolInfo.pPoolSizes = &poolSize;
        poolInfo.maxSets = 1;
        var pool: c.VkDescriptorPool = undefined;
        _ = c.vkCreateDescriptorPool(self.device, &poolInfo, null, &pool);
        var allocI = std.mem.zeroes(c.VkDescriptorSetAllocateInfo);
        allocI.sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        allocI.descriptorPool = pool;
        allocI.descriptorSetCount = 1;
        allocI.pSetLayouts = &self.descriptor_set_layout;
        var dset: c.VkDescriptorSet = undefined;
        _ = c.vkAllocateDescriptorSets(self.device, &allocI, &dset);
        var bufs = [3]c.VkDescriptorBufferInfo{
            .{ .buffer = inb, .offset = 0, .range = in_bytes },
            .{ .buffer = wb, .offset = 0, .range = w_bytes },
            .{ .buffer = ob, .offset = 0, .range = out_bytes },
        };
        var writes: [3]c.VkWriteDescriptorSet = undefined;
        for (0..3) |j| {
            writes[j] = std.mem.zeroes(c.VkWriteDescriptorSet);
            writes[j].sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
            writes[j].dstSet = dset;
            writes[j].dstBinding = @intCast(j);
            writes[j].descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
            writes[j].descriptorCount = 1;
            writes[j].pBufferInfo = &bufs[j];
        }
        c.vkUpdateDescriptorSets(self.device, 3, &writes[0], 0, null);

        var cmdAllocInfo = std.mem.zeroes(c.VkCommandBufferAllocateInfo);
        cmdAllocInfo.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
        cmdAllocInfo.commandPool = self.command_pool;
        cmdAllocInfo.level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        cmdAllocInfo.commandBufferCount = 1;
        var cmd: c.VkCommandBuffer = null;
        _ = c.vkAllocateCommandBuffers(self.device, &cmdAllocInfo, &cmd);
        var beginInfo = std.mem.zeroes(c.VkCommandBufferBeginInfo);
        beginInfo.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        _ = c.vkBeginCommandBuffer(cmd, &beginInfo);
        c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_COMPUTE, self.compute_pipeline);
        c.vkCmdBindDescriptorSets(cmd, c.VK_PIPELINE_BIND_POINT_COMPUTE, self.pipeline_layout, 0, 1, &dset, 0, null);
        var push = [_]u32{ in_dim, out_dim };
        c.vkCmdPushConstants(cmd, self.pipeline_layout, c.VK_SHADER_STAGE_COMPUTE_BIT, 0, 8, &push);
        c.vkCmdDispatch(cmd, n_groups, 1, 1);
        _ = c.vkEndCommandBuffer(cmd);

        var submit = std.mem.zeroes(c.VkSubmitInfo);
        submit.sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO;
        submit.commandBufferCount = 1;
        submit.pCommandBuffers = &cmd;

        for (0..5) |_| {
            _ = c.vkQueueSubmit(self.compute_queue, 1, &submit, null);
            _ = c.vkQueueWaitIdle(self.compute_queue);
        }
        var timer = try std.time.Timer.start();
        for (0..n_iters) |_| {
            _ = c.vkQueueSubmit(self.compute_queue, 1, &submit, null);
            _ = c.vkQueueWaitIdle(self.compute_queue);
        }
        const sec = @as(f64, @floatFromInt(timer.read())) / 1e9;
        const weights: f64 = @floatFromInt(@as(u64, out_dim) * in_dim * n_iters);
        c.vkFreeCommandBuffers(self.device, self.command_pool, 1, &cmd);
        c.vkDestroyDescriptorPool(self.device, pool, null);
        c.vkDestroyBuffer(self.device, inb, null);
        c.vkDestroyBuffer(self.device, wb, null);
        c.vkDestroyBuffer(self.device, ob, null);
        c.vkFreeMemory(self.device, inm, null);
        c.vkFreeMemory(self.device, wm, null);
        c.vkFreeMemory(self.device, om, null);
        return weights / sec / 1e9;
    }

    // Batched GEMM: B activation vectors, weights resident in VRAM. Returns
    // effective Gw/s = out_dim*in_dim*B / time (each weight serves B tokens).
    pub fn benchResidentGEMM(self: *GPUAccelerator, in_dim: u32, out_dim: u32, batch: u32, n_iters: usize, n_groups: u32) !f64 {
        const bpr = in_dim / 64;
        const w_bytes: c.VkDeviceSize = @as(u64, out_dim) * bpr * 12;
        const in_bytes: c.VkDeviceSize = @as(u64, in_dim) * batch * 4;
        const out_bytes: c.VkDeviceSize = @as(u64, out_dim) * batch * 4;
        var inb: c.VkBuffer = undefined;
        var inm: c.VkDeviceMemory = undefined;
        var wb: c.VkBuffer = undefined;
        var wm: c.VkDeviceMemory = undefined;
        var ob: c.VkBuffer = undefined;
        var om: c.VkDeviceMemory = undefined;
        const HV = c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
        const VRAM = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT | c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
        try self.createBuffer(in_bytes, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, HV, &inb, &inm);
        try self.createBuffer(w_bytes, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, VRAM, &wb, &wm);
        try self.createBuffer(out_bytes, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, HV, &ob, &om);
        var wp: ?*anyopaque = null;
        _ = c.vkMapMemory(self.device, wm, 0, w_bytes, 0, &wp);
        const wbp: [*]u8 = @ptrCast(wp.?);
        var seed: u64 = 0x99;
        var i: usize = 0;
        while (i < w_bytes) : (i += 12) {
            seed = seed *% 0x9E3779B97F4A7C15 +% 1;
            const lo: u32 = @truncate(seed);
            const hi: u32 = @truncate(seed >> 32);
            const sc: f32 = 0.05;
            @memcpy(wbp[i .. i + 4], std.mem.asBytes(&lo));
            @memcpy(wbp[i + 4 .. i + 8], std.mem.asBytes(&hi));
            @memcpy(wbp[i + 8 .. i + 12], std.mem.asBytes(&sc));
        }
        c.vkUnmapMemory(self.device, wm);
        var ip: ?*anyopaque = null;
        _ = c.vkMapMemory(self.device, inm, 0, in_bytes, 0, &ip);
        const ifp: [*]f32 = @ptrCast(@alignCast(ip.?));
        for (0..in_dim * batch) |k| ifp[k] = @floatFromInt(@as(u32, @truncate(k)) % 7);
        c.vkUnmapMemory(self.device, inm);
        var poolSize = std.mem.zeroes(c.VkDescriptorPoolSize);
        poolSize.type = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        poolSize.descriptorCount = 3;
        var poolInfo = std.mem.zeroes(c.VkDescriptorPoolCreateInfo);
        poolInfo.sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
        poolInfo.poolSizeCount = 1;
        poolInfo.pPoolSizes = &poolSize;
        poolInfo.maxSets = 1;
        var pool: c.VkDescriptorPool = undefined;
        _ = c.vkCreateDescriptorPool(self.device, &poolInfo, null, &pool);
        var aI = std.mem.zeroes(c.VkDescriptorSetAllocateInfo);
        aI.sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        aI.descriptorPool = pool;
        aI.descriptorSetCount = 1;
        aI.pSetLayouts = &self.descriptor_set_layout;
        var dset: c.VkDescriptorSet = undefined;
        _ = c.vkAllocateDescriptorSets(self.device, &aI, &dset);
        var bufs = [3]c.VkDescriptorBufferInfo{
            .{ .buffer = inb, .offset = 0, .range = in_bytes },
            .{ .buffer = wb, .offset = 0, .range = w_bytes },
            .{ .buffer = ob, .offset = 0, .range = out_bytes },
        };
        var writes: [3]c.VkWriteDescriptorSet = undefined;
        for (0..3) |j| {
            writes[j] = std.mem.zeroes(c.VkWriteDescriptorSet);
            writes[j].sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
            writes[j].dstSet = dset;
            writes[j].dstBinding = @intCast(j);
            writes[j].descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
            writes[j].descriptorCount = 1;
            writes[j].pBufferInfo = &bufs[j];
        }
        c.vkUpdateDescriptorSets(self.device, 3, &writes[0], 0, null);
        var cI = std.mem.zeroes(c.VkCommandBufferAllocateInfo);
        cI.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
        cI.commandPool = self.command_pool;
        cI.level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        cI.commandBufferCount = 1;
        var cmd: c.VkCommandBuffer = null;
        _ = c.vkAllocateCommandBuffers(self.device, &cI, &cmd);
        var bI = std.mem.zeroes(c.VkCommandBufferBeginInfo);
        bI.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        _ = c.vkBeginCommandBuffer(cmd, &bI);
        c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_COMPUTE, self.compute_pipeline);
        c.vkCmdBindDescriptorSets(cmd, c.VK_PIPELINE_BIND_POINT_COMPUTE, self.pipeline_layout, 0, 1, &dset, 0, null);
        var push = [_]u32{ in_dim, out_dim };
        c.vkCmdPushConstants(cmd, self.pipeline_layout, c.VK_SHADER_STAGE_COMPUTE_BIT, 0, 8, &push);
        c.vkCmdDispatch(cmd, n_groups, 1, 1);
        _ = c.vkEndCommandBuffer(cmd);
        var submit = std.mem.zeroes(c.VkSubmitInfo);
        submit.sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO;
        submit.commandBufferCount = 1;
        submit.pCommandBuffers = &cmd;
        for (0..3) |_| {
            _ = c.vkQueueSubmit(self.compute_queue, 1, &submit, null);
            _ = c.vkQueueWaitIdle(self.compute_queue);
        }
        var timer = try std.time.Timer.start();
        for (0..n_iters) |_| {
            _ = c.vkQueueSubmit(self.compute_queue, 1, &submit, null);
            _ = c.vkQueueWaitIdle(self.compute_queue);
        }
        const sec = @as(f64, @floatFromInt(timer.read())) / 1e9;
        const w: f64 = @floatFromInt(@as(u64, out_dim) * in_dim * batch * n_iters);
        c.vkFreeCommandBuffers(self.device, self.command_pool, 1, &cmd);
        c.vkDestroyDescriptorPool(self.device, pool, null);
        c.vkDestroyBuffer(self.device, inb, null);
        c.vkDestroyBuffer(self.device, wb, null);
        c.vkDestroyBuffer(self.device, ob, null);
        c.vkFreeMemory(self.device, inm, null);
        c.vkFreeMemory(self.device, wm, null);
        c.vkFreeMemory(self.device, om, null);
        return w / sec / 1e9;
    }

    pub fn deinit(self: *GPUAccelerator) void {
        if (self.compute_pipeline != null) c.vkDestroyPipeline(self.device, self.compute_pipeline, null);
        if (self.pipeline_layout != null) c.vkDestroyPipelineLayout(self.device, self.pipeline_layout, null);
        if (self.descriptor_set_layout != null) c.vkDestroyDescriptorSetLayout(self.device, self.descriptor_set_layout, null);
        if (self.shader_module != null) c.vkDestroyShaderModule(self.device, self.shader_module, null);
        c.vkDestroyCommandPool(self.device, self.command_pool, null);
        c.vkDestroyDevice(self.device, null);
        c.vkDestroyInstance(self.instance, null);
        self.allocator.destroy(self);
    }

    fn findMemoryType(self: *GPUAccelerator, typeFilter: u32, properties: c.VkMemoryPropertyFlags) !u32 {
        var memProperties: c.VkPhysicalDeviceMemoryProperties = undefined;
        c.vkGetPhysicalDeviceMemoryProperties(self.physical_device, &memProperties);
        for (0..memProperties.memoryTypeCount) |i| {
            if ((typeFilter & (@as(u32, 1) << @as(u5, @intCast(i)))) != 0 and (memProperties.memoryTypes[i].propertyFlags & properties) == properties) {
                return @as(u32, @intCast(i));
            }
        }
        return error.VulkanMemoryTypeNotFound;
    }

    pub fn createBuffer(self: *GPUAccelerator, size: c.VkDeviceSize, usage: c.VkBufferUsageFlags, properties: c.VkMemoryPropertyFlags, buffer: *c.VkBuffer, bufferMemory: *c.VkDeviceMemory) !void {
        var bufferInfo = std.mem.zeroes(c.VkBufferCreateInfo);
        bufferInfo.sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
        bufferInfo.size = size;
        bufferInfo.usage = usage;
        bufferInfo.sharingMode = c.VK_SHARING_MODE_EXCLUSIVE;

        if (c.vkCreateBuffer(self.device, &bufferInfo, null, buffer) != c.VK_SUCCESS) {
            return error.VulkanCreateBufferFailed;
        }

        var memRequirements: c.VkMemoryRequirements = undefined;
        c.vkGetBufferMemoryRequirements(self.device, buffer.*, &memRequirements);

        var allocInfo = std.mem.zeroes(c.VkMemoryAllocateInfo);
        allocInfo.sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        allocInfo.allocationSize = memRequirements.size;
        allocInfo.memoryTypeIndex = try self.findMemoryType(memRequirements.memoryTypeBits, properties);

        if (c.vkAllocateMemory(self.device, &allocInfo, null, bufferMemory) != c.VK_SUCCESS) {
            return error.VulkanAllocateMemoryFailed;
        }

        _ = c.vkBindBufferMemory(self.device, buffer.*, bufferMemory.*, 0);
    }
};
