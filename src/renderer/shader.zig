const std = @import("std");
const pool = @import("zpool");
const vk = @import("vk.zig");
const config = @import("../config.zig");

const Renderer = @import("renderer.zig");
const Buffer = @import("buffer.zig");
const BinaryLoader = @import("../loaders/binary_loader.zig");
const ShaderLoader = @import("../loaders/shader_loader.zig");
const Texture = @import("texture.zig");
const Image = @import("image.zig");

const Allocator = std.mem.Allocator;
const Array = std.BoundedArray;

// TODO: keep sampler uniforms separate or index lookup
// TODO: different types of samplers like cube and 3D
// TODO: flags
// TODO: descriptor pool free list
// TODO: generation and needs update

const Shader = @This();

const ShaderPool = pool.Pool(16, 16, Shader, struct {
    shader: Shader,
    reference_count: usize,
    auto_release: bool,
});

pub const Handle = ShaderPool.Handle;

pub const default_name = "phong";
pub var default: Handle = Handle.nil;

var allocator: Allocator = undefined;
var shaders: ShaderPool = undefined;
var lookup: std.StringHashMap(Handle) = undefined;

pub const Scope = enum(u8) {
    global = 0,
    instance = 1,
    local = 2,

    inline fn parse(scope: []const u8) !Scope {
        return std.meta.stringToEnum(Scope, scope) orelse error.UnknownUniformScope;
    }
};

pub const Attribute = struct {
    name: Array(u8, 256),
    data_type: DataType,
    size: u32,

    pub const DataType = enum(u8) {
        int8,
        uint8,
        int16,
        uint16,
        int32,
        uint32,
        float32,
        float32_2,
        float32_3,
        float32_4,

        inline fn getSize(self: DataType) u32 {
            return switch (self) {
                .int8, .uint8 => 1,
                .int16, .uint16 => 2,
                .int32, .uint32, .float32 => 4,
                .float32_2 => 8,
                .float32_3 => 12,
                .float32_4 => 16,
            };
        }

        inline fn toVkFormat(self: DataType) !vk.Format {
            return switch (self) {
                .int8 => .r8_sint,
                .uint8 => .r8_uint,
                .int16 => .r16_sint,
                .uint16 => .r16_uint,
                .int32 => .r32_sint,
                .uint32 => .r32_uint,
                .float32 => .r32_sfloat,
                .float32_2 => .r32g32_sfloat,
                .float32_3 => .r32g32b32_sfloat,
                .float32_4 => .r32g32b32a32_sfloat,
            };
        }

        inline fn parse(data_type: []const u8) !Attribute.DataType {
            return std.meta.stringToEnum(Attribute.DataType, data_type) orelse error.UnknownAttributeDataType;
        }
    };
};

pub const Uniform = struct {
    scope: Scope,
    name: Array(u8, 256),
    data_type: DataType,
    size: u32,
    offset: u32,

    pub const Handle = u8;

    pub const DataType = enum(u8) {
        int8,
        uint8,
        int16,
        uint16,
        int32,
        uint32,
        float32,
        float32_2,
        float32_3,
        float32_4,
        mat4,
        sampler,

        inline fn getSize(self: DataType) u32 {
            return switch (self) {
                .sampler => 0,
                .int8, .uint8 => 1,
                .int16, .uint16 => 2,
                .int32, .uint32, .float32 => 4,
                .float32_2 => 8,
                .float32_3 => 12,
                .float32_4 => 16,
                .mat4 => 64,
            };
        }

        pub inline fn parse(data_type: []const u8) !DataType {
            return std.meta.stringToEnum(DataType, data_type) orelse error.UnknownUniformDataType;
        }
    };
};

pub const ScopeState = struct {
    size: u32 = 0,
    stride: u32 = 0,
    binding_count: u32 = 0,
    uniform_count: u32 = 0,
    uniform_sampler_count: u16 = 0,
};

pub const InstanceState = struct {
    ubo_offset: u64,
    descriptor_sets: Array(vk.DescriptorSet, config.swapchain_max_images),
    textures: Array(Texture.Handle, config.shader_max_instance_textures),
};

// NOTE: index_bits = 10 results in a maximum of 1024 instances
pub const InstancePool = pool.Pool(10, 22, InstanceState, struct {
    instance_state: InstanceState,
});
pub const InstanceHandle = InstancePool.Handle;

name: Array(u8, 256),

attributes: std.ArrayList(Attribute),

uniforms: std.ArrayList(Uniform),
uniform_lookup: std.StringHashMap(Uniform.Handle),

global_scope: ScopeState,
instance_scope: ScopeState,
local_scope: ScopeState,

shader_modules: Array(vk.ShaderModule, config.shader_max_stages),
descriptor_pool: vk.DescriptorPool,
descriptor_set_layouts: Array(vk.DescriptorSetLayout, 2),
pipeline_layout: vk.PipelineLayout,
pipeline: vk.Pipeline,

global_state: InstanceState,
instance_state_pool: InstancePool,

ubo: Buffer,
ubo_ptr: [*]u8,
local_push_constant_buffer: Array(u8, 128),

bound_scope: Scope,
bound_ubo_offset: u64,
bound_instance: InstanceHandle,

pub fn initSystem(ally: Allocator) !void {
    allocator = ally;

    shaders = try ShaderPool.initMaxCapacity(allocator);
    errdefer shaders.deinit();

    lookup = std.StringHashMap(Handle).init(allocator);
    errdefer lookup.deinit();

    try lookup.ensureTotalCapacity(@truncate(shaders.capacity()));

    try createDefault();
}

pub fn deinitSystem() void {
    var it = shaders.liveHandles();
    while (it.next()) |handle| {
        remove(handle);
    }

    lookup.deinit();
    shaders.deinit();
}

pub fn acquire(name: []const u8) !Handle {
    if (lookup.get(name)) |handle| {
        return acquireExisting(handle);
    } else {
        var resource = try ShaderLoader.init(allocator, name);
        defer resource.deinit();

        var shader = try create(resource.config.value);
        errdefer shader.destroy();

        const handle = try shaders.add(.{
            .shader = shader,
            .reference_count = 1,
            .auto_release = resource.config.value.auto_release,
        });
        errdefer shaders.removeAssumeLive(handle);

        const shader_ptr = try get(handle); // NOTE: use name from ptr as key
        try lookup.put(shader_ptr.name.constSlice(), handle);

        std.log.info("Shader: Create '{s}' (1)", .{name});

        return handle;
    }
}

pub fn reload(name: []const u8) !void {
    _ = name; // autofix
    // TODO: implement reload
}

fn createDefault() !void {
    default = try acquire(default_name);

    // var shader = try default.get();
    // shader.generation = null; // NOTE: default shader must have null generation
}

// handle
pub fn acquireExisting(handle: Handle) !Handle {
    if (eql(handle, default)) {
        return default;
    }

    const shader = try get(handle);
    const reference_count = shaders.getColumnPtrAssumeLive(handle, .reference_count);

    reference_count.* +|= 1;

    std.log.info("Shader: Acquire '{s}' ({})", .{ shader.name.slice(), reference_count.* });

    return handle;
}

pub fn release(handle: Handle) void {
    if (eql(handle, default)) {
        return;
    }

    if (getIfExists(handle)) |shader| {
        const reference_count = shaders.getColumnPtrAssumeLive(handle, .reference_count);
        const auto_release = shaders.getColumnAssumeLive(handle, .auto_release);

        if (reference_count.* == 0) {
            std.log.warn("Shader: Release with ref count 0!", .{});
            return;
        }

        reference_count.* -|= 1;

        if (auto_release and reference_count.* == 0) {
            remove(handle);
        } else {
            std.log.info("Shader: Release '{s}' ({})", .{ shader.name.slice(), reference_count.* });
        }
    } else {
        std.log.warn("Shader: Release invalid handle!", .{});
    }
}

pub inline fn eql(left: Handle, right: Handle) bool {
    return left.id == right.id;
}

pub inline fn isNilOrDefault(handle: Handle) bool {
    return eql(handle, Handle.nil) or eql(handle, default);
}

pub inline fn exists(handle: Handle) bool {
    return shaders.isLiveHandle(handle);
}

pub inline fn get(handle: Handle) !*Shader {
    return try shaders.getColumnPtr(handle, .shader);
}

pub inline fn getIfExists(handle: Handle) ?*Shader {
    return shaders.getColumnPtrIfLive(handle, .shader);
}

pub inline fn getOrDefault(handle: Handle) *Shader {
    return shaders.getColumnPtrIfLive(handle, .shader) //
    orelse shaders.getColumnPtrAssumeLive(default, .shader);
}

pub fn remove(handle: Handle) void {
    if (getIfExists(handle)) |shader| {
        std.log.info("Shader: Remove '{s}'", .{shader.name.slice()});

        _ = lookup.remove(shader.name.slice());
        shaders.removeAssumeLive(handle);

        shader.destroy();
    }
}

pub fn createInstance(handle: Handle) !InstanceHandle {
    var shader = try get(handle);

    var instance_state = InstanceState{
        .ubo_offset = 0,
        .descriptor_sets = try Array(vk.DescriptorSet, config.swapchain_max_images).init(0),
        .textures = try Array(Texture.Handle, config.shader_max_instance_textures).init(0),
    };

    // allocate instance descriptor sets
    const instance_ubo_layout = shader.descriptor_set_layouts.get(@intFromEnum(Shader.Scope.instance));
    var instance_ubo_layouts = try Array(vk.DescriptorSetLayout, config.swapchain_max_images).init(0);
    try instance_ubo_layouts.appendNTimes(instance_ubo_layout, Renderer.swapchain.images.len);

    const instance_ubo_descriptor_set_alloc_info = vk.DescriptorSetAllocateInfo{
        .descriptor_pool = shader.descriptor_pool,
        .descriptor_set_count = instance_ubo_layouts.len,
        .p_set_layouts = instance_ubo_layouts.slice().ptr,
    };

    try instance_state.descriptor_sets.resize(instance_ubo_layouts.len);

    try Renderer.device_api.allocateDescriptorSets(
        Renderer.device,
        &instance_ubo_descriptor_set_alloc_info,
        instance_state.descriptor_sets.slice().ptr,
    );

    errdefer {
        Renderer.device_api.freeDescriptorSets(
            Renderer.device,
            shader.descriptor_pool,
            instance_state.descriptor_sets.len,
            instance_state.descriptor_sets.slice().ptr,
        ) catch unreachable;
        instance_state.descriptor_sets.len = 0;
    }

    // allocate instance ubo range
    instance_state.ubo_offset = try shader.ubo.alloc(shader.instance_scope.stride);
    errdefer shader.ubo.free(instance_state.ubo_offset, shader.instance_scope.stride) catch unreachable;

    // clear textures to default texture handle
    try instance_state.textures.resize(0);
    try instance_state.textures.appendNTimes(Texture.default, shader.instance_scope.uniform_sampler_count);

    // add instance to pool
    const instance_handle = try shader.instance_state_pool.add(.{
        .instance_state = instance_state,
    });

    return instance_handle;
}

pub fn destroyInstance(handle: Handle, instance_handle: InstanceHandle) void {
    if (getIfExists(handle)) |shader| {
        if (shader.instance_state_pool.getColumnPtrIfLive(instance_handle, .instance_state)) |instance_state| {
            shader.instance_state_pool.removeAssumeLive(instance_handle);

            shader.ubo.free(instance_state.ubo_offset, shader.instance_scope.stride) catch unreachable;

            Renderer.device_api.freeDescriptorSets(
                Renderer.device,
                shader.descriptor_pool,
                instance_state.descriptor_sets.len,
                instance_state.descriptor_sets.slice().ptr,
            ) catch unreachable;
            instance_state.descriptor_sets.len = 0;

            instance_state.* = undefined;
        }
    }
}

pub fn bind(handle: Handle) !void {
    const shader = try get(handle);

    Renderer.device_api.cmdBindPipeline(Renderer.getCurrentCommandBuffer().handle, .graphics, shader.pipeline);
}

pub fn bindGlobal(handle: Handle) !void {
    var shader = try get(handle);

    shader.bound_scope = .global;
    shader.bound_instance = InstanceHandle.nil;
    shader.bound_ubo_offset = shader.global_state.ubo_offset;
}

pub fn bindInstance(handle: Handle, instance_handle: InstanceHandle) !void {
    var shader = try get(handle);

    if (shader.instance_state_pool.getColumnPtrIfLive(instance_handle, .instance_state)) |instance_state| {
        shader.bound_scope = .instance;
        shader.bound_instance = instance_handle;
        shader.bound_ubo_offset = instance_state.ubo_offset;
    } else return error.InvalidShaderInstanceHandle;
}

pub fn bindLocal(handle: Handle) !void {
    var shader = try get(handle);

    shader.bound_scope = .local;
    shader.bound_instance = InstanceHandle.nil;
}

pub fn getUniformHandle(handle: Handle, name: []const u8) !Uniform.Handle {
    var shader = try get(handle);

    return shader.uniform_lookup.get(name) orelse error.UniformNotFound;
}

pub fn setUniform(handle: Handle, uniform: anytype, value: anytype) !void {
    var shader = try get(handle);

    const uniform_handle = if (@TypeOf(uniform) == Uniform.Handle)
        uniform
    else if (@typeInfo(@TypeOf(uniform)) == .Pointer and std.meta.Elem(@TypeOf(uniform)) == u8)
        try getUniformHandle(handle, uniform)
    else
        return error.InvalidUniformType;

    const p_uniform = &shader.uniforms.items[uniform_handle];

    if (p_uniform.data_type == .sampler) {
        if (@TypeOf(value) != Texture.Handle) {
            return error.InvalidSamplerValue;
        }

        switch (p_uniform.scope) {
            .global => {
                shader.global_state.textures.slice()[p_uniform.offset] = value;
            },
            .instance => {
                var instance_state = try shader.instance_state_pool.getColumnPtr(shader.bound_instance, .instance_state);

                instance_state.textures.slice()[p_uniform.offset] = value;
            },
            .local => return error.CannotSetLocalSamplers,
        }
    } else {
        switch (p_uniform.scope) {
            .global, .instance => {
                const ubo_offset_ptr = @as([*]u8, @ptrFromInt(
                    @intFromPtr(shader.ubo_ptr) + shader.bound_ubo_offset + p_uniform.offset,
                ));

                @memcpy(ubo_offset_ptr, &std.mem.toBytes(value));
            },
            .local => {
                const local_offset_ptr: [*]u8 = @ptrFromInt(
                    @intFromPtr(shader.local_push_constant_buffer.slice().ptr) + p_uniform.offset,
                );

                @memcpy(local_offset_ptr, &std.mem.toBytes(value));
            },
        }
    }
}

pub fn applyGlobal(handle: Handle) !void {
    var shader = try get(handle);

    const image_index = Renderer.swapchain.image_index;
    const command_buffer = Renderer.getCurrentCommandBuffer();
    const descriptor_set = shader.global_state.descriptor_sets.get(image_index);

    var descriptor_writes = try Array(vk.WriteDescriptorSet, 2).init(0);

    var dst_binding: u32 = 0;

    // TODO: this buffer_info never changes so it can be set just once
    // descriptor 0 - uniform buffer
    const buffer_info = vk.DescriptorBufferInfo{
        .buffer = shader.ubo.handle,
        .offset = shader.global_state.ubo_offset,
        .range = shader.global_scope.stride,
    };

    try descriptor_writes.append(vk.WriteDescriptorSet{
        .dst_set = descriptor_set,
        .dst_binding = dst_binding,
        .dst_array_element = 0,
        .descriptor_type = .uniform_buffer,
        .descriptor_count = 1,
        .p_buffer_info = @ptrCast(&buffer_info),
        .p_image_info = undefined,
        .p_texel_buffer_view = undefined,
    });

    dst_binding += 1;

    // TODO: only do descriptor writes for samplers that actually changed
    // descriptor 1 - samplers
    if (shader.global_scope.uniform_sampler_count > 0) {
        var image_infos = try Array(vk.DescriptorImageInfo, config.shader_max_instance_textures).init(0);

        for (0..shader.global_scope.uniform_sampler_count) |sampler_index| {
            const texture_handle = shader.global_state.textures.slice()[sampler_index];
            const texture = Texture.getOrDefault(texture_handle);
            const image = Image.getOrDefault(texture.image);

            try image_infos.append(vk.DescriptorImageInfo{
                .image_layout = .shader_read_only_optimal,
                .image_view = image.view,
                .sampler = texture.sampler,
            });
        }

        try descriptor_writes.append(vk.WriteDescriptorSet{
            .dst_set = descriptor_set,
            .dst_binding = dst_binding,
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = shader.global_scope.uniform_sampler_count,
            .dst_array_element = 0,
            .p_buffer_info = undefined,
            .p_image_info = image_infos.slice().ptr,
            .p_texel_buffer_view = undefined,
        });
    }

    if (descriptor_writes.len > 0) {
        Renderer.device_api.updateDescriptorSets(
            Renderer.device,
            descriptor_writes.len,
            descriptor_writes.slice().ptr,
            0,
            null,
        );
    }

    Renderer.device_api.cmdBindDescriptorSets(
        command_buffer.handle,
        .graphics,
        shader.pipeline_layout,
        0,
        1,
        @ptrCast(&descriptor_set),
        0,
        null,
    );
}

pub fn applyInstance(handle: Handle) !void {
    var shader = try get(handle);

    const image_index = Renderer.swapchain.image_index;
    const command_buffer = Renderer.getCurrentCommandBuffer();
    const instance_state = try shader.instance_state_pool.getColumnPtr(shader.bound_instance, .instance_state);
    const descriptor_set = instance_state.descriptor_sets.get(image_index);

    var descriptor_writes = try Array(vk.WriteDescriptorSet, 2).init(0);

    var dst_binding: u32 = 0;

    // TODO: this buffer_info never changes so it can be set just once per instance
    // descriptor 0 - uniform buffer
    const buffer_info = vk.DescriptorBufferInfo{
        .buffer = shader.ubo.handle,
        .offset = instance_state.ubo_offset,
        .range = shader.instance_scope.stride,
    };

    try descriptor_writes.append(vk.WriteDescriptorSet{
        .dst_set = descriptor_set,
        .dst_binding = dst_binding,
        .dst_array_element = 0,
        .descriptor_type = .uniform_buffer,
        .descriptor_count = 1,
        .p_buffer_info = @ptrCast(&buffer_info),
        .p_image_info = undefined,
        .p_texel_buffer_view = undefined,
    });

    dst_binding += 1;

    // TODO: only do descriptor writes for samplers that actually changed
    // descriptor 1 - samplers
    if (shader.instance_scope.uniform_sampler_count > 0) {
        var image_infos = try Array(vk.DescriptorImageInfo, config.shader_max_instance_textures).init(0);

        for (0..shader.instance_scope.uniform_sampler_count) |sampler_index| {
            const texture_handle = instance_state.textures.slice()[sampler_index];
            const texture = Texture.getOrDefault(texture_handle);
            const image = Image.getOrDefault(texture.image);

            try image_infos.append(vk.DescriptorImageInfo{
                .image_layout = .shader_read_only_optimal,
                .image_view = image.view,
                .sampler = texture.sampler,
            });
        }

        try descriptor_writes.append(vk.WriteDescriptorSet{
            .dst_set = descriptor_set,
            .dst_binding = dst_binding,
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = shader.instance_scope.uniform_sampler_count,
            .dst_array_element = 0,
            .p_buffer_info = undefined,
            .p_image_info = image_infos.slice().ptr,
            .p_texel_buffer_view = undefined,
        });
    }

    if (descriptor_writes.len > 0) {
        Renderer.device_api.updateDescriptorSets(
            Renderer.device,
            descriptor_writes.len,
            descriptor_writes.slice().ptr,
            0,
            null,
        );
    }

    Renderer.device_api.cmdBindDescriptorSets(
        command_buffer.handle,
        .graphics,
        shader.pipeline_layout,
        1,
        1,
        @ptrCast(&descriptor_set),
        0,
        null,
    );
}

pub fn applyLocal(handle: Handle) !void {
    var shader = try get(handle);

    Renderer.device_api.cmdPushConstants(
        Renderer.getCurrentCommandBuffer().handle,
        shader.pipeline_layout,
        .{ .vertex_bit = true, .fragment_bit = true },
        0,
        128,
        shader.local_push_constant_buffer.slice().ptr,
    );
}

// utils
fn create(shader_config: Config) !Shader {
    var self: Shader = undefined;

    // initialize everything so we can only do an errdefer self.deinit();
    self.attributes.capacity = 0;

    self.uniforms.capacity = 0;
    self.uniform_lookup.unmanaged.metadata = null;

    self.global_scope = ScopeState{};
    self.local_scope = ScopeState{};
    self.instance_scope = ScopeState{};

    self.shader_modules.len = 0;
    self.descriptor_set_layouts.len = 0;
    self.descriptor_pool = .null_handle;
    self.pipeline_layout = .null_handle;
    self.pipeline = .null_handle;

    self.global_state = InstanceState{
        .ubo_offset = 0,
        .descriptor_sets = try Array(vk.DescriptorSet, config.swapchain_max_images).init(0),
        .textures = try Array(Texture.Handle, config.shader_max_instance_textures).init(0),
    };
    self.instance_state_pool._storage.capacity = 0;

    self.ubo.handle = .null_handle;
    self.local_push_constant_buffer = try Array(u8, 128).init(128);

    self.bound_scope = .global;
    self.bound_ubo_offset = 0;
    self.bound_instance = InstanceHandle.nil;

    errdefer self.destroy();

    self.name = try Array(u8, 256).fromSlice(shader_config.name);

    // parse attributes and uniforms from config
    self.attributes = try std.ArrayList(Attribute).initCapacity(allocator, 8);

    try self.addAttributes(shader_config.attributes);

    self.uniforms = try std.ArrayList(Uniform).initCapacity(allocator, 8);
    self.uniform_lookup = std.StringHashMap(Uniform.Handle).init(allocator);

    // NOTE: this also sets scope states
    try self.addUniforms(shader_config.uniforms);

    // create shader stages
    var shader_stages = try Array(vk.PipelineShaderStageCreateInfo, config.shader_max_stages).init(0);

    try self.shader_modules.resize(0);

    for (shader_config.stages) |stage| {
        const module = try createShaderModule(stage.path);
        try self.shader_modules.append(module);

        try shader_stages.append(vk.PipelineShaderStageCreateInfo{
            .flags = .{},
            .stage = try parseVkShaderStageFlags(stage.stage_type),
            .module = module,
            .p_name = "main",
            .p_specialization_info = null,
        });
    }

    // create vertex input state
    var attribute_descriptions = try Array(vk.VertexInputAttributeDescription, config.shader_max_attributes).init(0);

    var offset: u32 = 0;
    for (self.attributes.items, 0..) |attribute, location| {
        try attribute_descriptions.append(vk.VertexInputAttributeDescription{
            .binding = 0,
            .location = @intCast(location),
            .format = try attribute.data_type.toVkFormat(),
            .offset = offset,
        });

        offset += attribute.size;
    }

    const vertex_input_state = vk.PipelineVertexInputStateCreateInfo{
        .flags = .{},
        .vertex_binding_description_count = 1,
        .p_vertex_binding_descriptions = @ptrCast(&vk.VertexInputBindingDescription{
            .binding = 0,
            .stride = offset,
            .input_rate = .vertex,
        }),
        .vertex_attribute_description_count = attribute_descriptions.len,
        .p_vertex_attribute_descriptions = attribute_descriptions.slice().ptr,
    };

    try self.descriptor_set_layouts.resize(0);

    // create global descriptor set layouts
    var global_bindings = try Array(vk.DescriptorSetLayoutBinding, 2).init(0);

    try global_bindings.append(
        vk.DescriptorSetLayoutBinding{
            .binding = 0,
            .descriptor_count = 1,
            .descriptor_type = .uniform_buffer,
            .p_immutable_samplers = null,
            .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
        },
    );

    if (self.global_scope.uniform_sampler_count > 0) {
        try global_bindings.append(
            vk.DescriptorSetLayoutBinding{
                .binding = 1,
                .descriptor_count = self.global_scope.uniform_sampler_count,
                .descriptor_type = .combined_image_sampler,
                .p_immutable_samplers = null,
                .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
            },
        );
    }

    try self.descriptor_set_layouts.append(try Renderer.device_api.createDescriptorSetLayout(
        Renderer.device,
        &vk.DescriptorSetLayoutCreateInfo{
            .binding_count = global_bindings.len,
            .p_bindings = global_bindings.slice().ptr,
        },
        null,
    ));

    self.global_scope.binding_count = global_bindings.len;

    // create instance descriptor set layouts
    if (self.instance_scope.uniform_count + self.instance_scope.uniform_sampler_count > 0) {
        var instance_bindings = try Array(vk.DescriptorSetLayoutBinding, 2).init(0);

        try instance_bindings.append(
            vk.DescriptorSetLayoutBinding{
                .binding = 0,
                .descriptor_count = 1,
                .descriptor_type = .uniform_buffer,
                .p_immutable_samplers = null,
                .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
            },
        );

        if (self.instance_scope.uniform_sampler_count > 0) {
            try instance_bindings.append(
                vk.DescriptorSetLayoutBinding{
                    .binding = 1,
                    .descriptor_count = self.instance_scope.uniform_sampler_count,
                    .descriptor_type = .combined_image_sampler,
                    .p_immutable_samplers = null,
                    .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
                },
            );
        }

        try self.descriptor_set_layouts.append(try Renderer.device_api.createDescriptorSetLayout(
            Renderer.device,
            &vk.DescriptorSetLayoutCreateInfo{
                .binding_count = instance_bindings.len,
                .p_bindings = instance_bindings.slice().ptr,
            },
            null,
        ));

        self.instance_scope.binding_count = instance_bindings.len;
    }

    // create local push constant range
    const push_constant_range = vk.PushConstantRange{
        .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
        .offset = 0,
        .size = 128,
    };

    // create pipeline layout
    self.pipeline_layout = try Renderer.device_api.createPipelineLayout(Renderer.device, &.{
        .flags = .{},
        .set_layout_count = self.descriptor_set_layouts.len,
        .p_set_layouts = self.descriptor_set_layouts.slice().ptr,
        .push_constant_range_count = 1,
        .p_push_constant_ranges = @ptrCast(&push_constant_range),
    }, null);

    // create other pipeline state
    const input_assembly_state = vk.PipelineInputAssemblyStateCreateInfo{
        .flags = .{},
        .topology = .triangle_list,
        .primitive_restart_enable = vk.FALSE,
    };

    const rasterization_state = vk.PipelineRasterizationStateCreateInfo{
        .flags = .{},
        .depth_clamp_enable = vk.FALSE,
        .rasterizer_discard_enable = vk.FALSE,
        .polygon_mode = .fill,
        .cull_mode = .{ .back_bit = true },
        .front_face = .counter_clockwise,
        .depth_bias_enable = vk.FALSE,
        .depth_bias_constant_factor = 0,
        .depth_bias_clamp = 0,
        .depth_bias_slope_factor = 0,
        .line_width = 1,
    };

    const multisample_state = vk.PipelineMultisampleStateCreateInfo{
        .flags = .{},
        .rasterization_samples = .{ .@"1_bit" = true },
        .sample_shading_enable = vk.FALSE,
        .min_sample_shading = 1,
        .p_sample_mask = null,
        .alpha_to_coverage_enable = vk.FALSE,
        .alpha_to_one_enable = vk.FALSE,
    };

    const depth_stencil_state = vk.PipelineDepthStencilStateCreateInfo{
        .flags = .{},
        .depth_test_enable = vk.TRUE,
        .depth_write_enable = vk.TRUE,
        .depth_compare_op = .less,
        .depth_bounds_test_enable = vk.FALSE,
        .stencil_test_enable = vk.FALSE,
        .front = undefined,
        .back = undefined,
        .min_depth_bounds = 0,
        .max_depth_bounds = 0,
    };

    const color_blend_attachment_state = vk.PipelineColorBlendAttachmentState{
        .blend_enable = vk.TRUE,
        .src_color_blend_factor = .src_alpha,
        .dst_color_blend_factor = .one_minus_src_alpha,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .src_alpha,
        .dst_alpha_blend_factor = .one_minus_src_alpha,
        .alpha_blend_op = .add,
        .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
    };

    const color_blend_state = vk.PipelineColorBlendStateCreateInfo{
        .flags = .{},
        .logic_op_enable = vk.FALSE,
        .logic_op = .copy,
        .attachment_count = 1,
        .p_attachments = @ptrCast(&color_blend_attachment_state),
        .blend_constants = [_]f32{ 0, 0, 0, 0 },
    };

    const viewport_state = vk.PipelineViewportStateCreateInfo{
        .flags = .{},
        .viewport_count = 1,
        .p_viewports = undefined,
        .scissor_count = 1,
        .p_scissors = undefined,
    };

    const dynamic_state_props = [_]vk.DynamicState{ .viewport, .scissor, .line_width };
    const dynamic_state = vk.PipelineDynamicStateCreateInfo{
        .flags = .{},
        .dynamic_state_count = dynamic_state_props.len,
        .p_dynamic_states = &dynamic_state_props,
    };

    // create pipeline
    const pipeline_create_info = vk.GraphicsPipelineCreateInfo{
        .flags = .{},
        .stage_count = shader_stages.len,
        .p_stages = shader_stages.slice().ptr,
        .p_viewport_state = &viewport_state,
        .p_vertex_input_state = &vertex_input_state,
        .p_input_assembly_state = &input_assembly_state,
        .p_tessellation_state = null,
        .p_rasterization_state = &rasterization_state,
        .p_multisample_state = &multisample_state,
        .p_depth_stencil_state = &depth_stencil_state,
        .p_color_blend_state = &color_blend_state,
        .p_dynamic_state = &dynamic_state,
        .layout = self.pipeline_layout,
        .render_pass = try parseVkRenderPass(shader_config.render_pass_name),
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    };

    _ = try Renderer.device_api.createGraphicsPipelines(
        Renderer.device,
        .null_handle,
        1,
        @ptrCast(&pipeline_create_info),
        null,
        @ptrCast(&self.pipeline),
    );

    // create descriptor pool
    const descriptor_pool_sizes = [_]vk.DescriptorPoolSize{
        vk.DescriptorPoolSize{ .type = .uniform_buffer, .descriptor_count = 1024 },
        vk.DescriptorPoolSize{ .type = .combined_image_sampler, .descriptor_count = 4096 },
    };

    self.descriptor_pool = try Renderer.device_api.createDescriptorPool(
        Renderer.device,
        &vk.DescriptorPoolCreateInfo{
            .flags = .{ .free_descriptor_set_bit = true },
            .pool_size_count = descriptor_pool_sizes.len,
            .p_pool_sizes = &descriptor_pool_sizes,
            .max_sets = config.shader_max_descriptor_sets_allocate,
        },
        null,
    );

    // create and map ubo
    const ubo_alignment: u32 = @intCast(Renderer.physical_device.properties.limits.min_uniform_buffer_offset_alignment);

    self.global_scope.stride = std.mem.alignForward(u32, self.global_scope.size, ubo_alignment);
    self.instance_scope.stride = std.mem.alignForward(u32, self.instance_scope.size, ubo_alignment);

    const ubo_size = self.global_scope.stride + (self.instance_scope.stride * config.shader_max_instances);

    self.ubo = try Buffer.init(
        allocator,
        ubo_size,
        .{ .transfer_dst_bit = true, .uniform_buffer_bit = true },
        .{
            .device_local_bit = Renderer.physical_device.supports_local_host_visible,
            .host_visible_bit = true,
            .host_coherent_bit = true,
        },
        .{ .managed = true, .bind_on_create = true },
    );

    self.ubo_ptr = try self.ubo.lock(0, vk.WHOLE_SIZE, .{});

    // allocate global descriptor sets
    const global_ubo_layout = self.descriptor_set_layouts.get(@intFromEnum(Shader.Scope.global));
    var global_ubo_layouts = try Array(vk.DescriptorSetLayout, config.swapchain_max_images).init(0);
    try global_ubo_layouts.appendNTimes(global_ubo_layout, Renderer.swapchain.images.len);

    const global_ubo_descriptor_set_alloc_info = vk.DescriptorSetAllocateInfo{
        .descriptor_pool = self.descriptor_pool,
        .descriptor_set_count = global_ubo_layouts.len,
        .p_set_layouts = global_ubo_layouts.slice().ptr,
    };

    try self.global_state.descriptor_sets.resize(global_ubo_layouts.len);

    try Renderer.device_api.allocateDescriptorSets(
        Renderer.device,
        &global_ubo_descriptor_set_alloc_info,
        self.global_state.descriptor_sets.slice().ptr,
    );

    // alloc global ubo range
    self.global_state.ubo_offset = try self.ubo.alloc(self.global_scope.stride);

    // clear textures to default texture handle
    try self.global_state.textures.resize(0);
    try self.global_state.textures.appendNTimes(Texture.default, self.global_scope.uniform_sampler_count);

    // create instance state pool
    self.instance_state_pool = try InstancePool.initMaxCapacity(allocator);

    return self;
}

fn destroy(self: *Shader) void {
    if (self.instance_state_pool.capacity() > 0) {
        self.instance_state_pool.deinit();
    }

    if (self.global_state.descriptor_sets.len > 0) {
        Renderer.device_api.freeDescriptorSets(
            Renderer.device,
            self.descriptor_pool,
            self.global_state.descriptor_sets.len,
            self.global_state.descriptor_sets.slice().ptr,
        ) catch unreachable;
        self.global_state.descriptor_sets.len = 0;
    }

    if (self.ubo.handle != .null_handle) {
        self.ubo.deinit();
    }

    if (self.descriptor_pool != .null_handle) {
        Renderer.device_api.destroyDescriptorPool(Renderer.device, self.descriptor_pool, null);
    }

    if (self.pipeline != .null_handle) {
        Renderer.device_api.destroyPipeline(Renderer.device, self.pipeline, null);
    }

    if (self.pipeline_layout != .null_handle) {
        Renderer.device_api.destroyPipelineLayout(Renderer.device, self.pipeline_layout, null);
    }

    for (self.descriptor_set_layouts.slice()) |descriptor_set_layout| {
        if (descriptor_set_layout != .null_handle) {
            Renderer.device_api.destroyDescriptorSetLayout(Renderer.device, descriptor_set_layout, null);
        }
    }
    self.descriptor_set_layouts.len = 0;

    for (self.shader_modules.slice()) |module| {
        if (module != .null_handle) {
            Renderer.device_api.destroyShaderModule(Renderer.device, module, null);
        }
    }
    self.shader_modules.len = 0;

    if (self.uniform_lookup.unmanaged.metadata != null) {
        var it = self.uniform_lookup.keyIterator();
        while (it.next()) |key| {
            allocator.free(key.*);
        }

        self.uniform_lookup.deinit();
    }

    if (self.uniforms.capacity > 0) {
        self.uniforms.deinit();
    }

    if (self.attributes.capacity > 0) {
        self.attributes.deinit();
    }

    self.* = undefined;
}

fn addAttributes(self: *Shader, attribute_configs: []const AttributeConfig) !void {
    for (attribute_configs) |attribute_config| {
        const attribute_data_type = try Attribute.DataType.parse(attribute_config.data_type);
        const attribute_size = attribute_data_type.getSize();

        try self.attributes.append(Attribute{
            .name = try Array(u8, 256).fromSlice(attribute_config.name),
            .data_type = attribute_data_type,
            .size = attribute_size,
        });
    }
}

fn addUniforms(self: *Shader, uniform_configs: []const UniformConfig) !void {
    for (uniform_configs) |uniform_config| {
        const scope = try Scope.parse(uniform_config.scope);

        var scope_config = switch (scope) {
            .global => &self.global_scope,
            .instance => &self.instance_scope,
            .local => &self.local_scope,
        };

        const uniform_handle: Uniform.Handle = @truncate(self.uniforms.items.len);
        const uniform_data_type = try Uniform.DataType.parse(uniform_config.data_type);
        const uniform_size = uniform_data_type.getSize();
        const is_sampler = uniform_data_type == .sampler;

        try self.uniforms.append(Uniform{
            .scope = scope,
            .name = try Array(u8, 256).fromSlice(uniform_config.name),
            .data_type = uniform_data_type,
            .size = uniform_size,
            .offset = if (is_sampler) scope_config.uniform_sampler_count else scope_config.stride,
        });

        // NOTE: dupe the name as pointers inside ArrayList are not stable
        try self.uniform_lookup.put(try allocator.dupe(u8, uniform_config.name), uniform_handle);

        if (is_sampler) {
            if (scope == .local) {
                return error.LocalSamplersNotSupported;
            }
            scope_config.uniform_sampler_count += 1;
        } else {
            scope_config.uniform_count += 1;
            scope_config.size += uniform_size;
            scope_config.stride += if (scope == .local) std.mem.alignForward(u32, uniform_size, 4) else uniform_size;
        }
    }

    if (self.local_scope.stride > 128) {
        return error.LocalScopeOverflow;
    }
}

fn createShaderModule(path: []const u8) !vk.ShaderModule {
    var binary_resource = try BinaryLoader.init(allocator, path);
    defer binary_resource.deinit();

    return try Renderer.device_api.createShaderModule(
        Renderer.device,
        &vk.ShaderModuleCreateInfo{
            .flags = .{},
            .code_size = binary_resource.bytes.len,
            .p_code = @ptrCast(@alignCast(binary_resource.bytes.ptr)),
        },
        null,
    );
}

// parse from config
inline fn parseVkShaderStageFlags(stage_type: []const u8) !vk.ShaderStageFlags {
    if (std.mem.eql(u8, stage_type, "vertex")) return .{ .vertex_bit = true };
    if (std.mem.eql(u8, stage_type, "fragment")) return .{ .fragment_bit = true };

    return error.UnknownShaderStage;
}

inline fn parseVkRenderPass(render_pass_name: []const u8) !vk.RenderPass {
    if (std.mem.eql(u8, render_pass_name, "world")) return Renderer.world_render_pass.handle;
    if (std.mem.eql(u8, render_pass_name, "ui")) return Renderer.ui_render_pass.handle;

    return error.UnknownRenderPass;
}

// config
pub const Config = struct {
    name: []const u8 = "new_shader",
    render_pass_name: []const u8 = "world",
    auto_release: bool = true,
    stages: []const StageConfig,
    attributes: []const AttributeConfig,
    uniforms: []const UniformConfig,
};

pub const StageConfig = struct {
    stage_type: []const u8,
    path: []const u8,
};

pub const AttributeConfig = struct {
    name: []const u8,
    data_type: []const u8,
};

pub const UniformConfig = struct {
    scope: []const u8,
    name: []const u8,
    data_type: []const u8,
};
