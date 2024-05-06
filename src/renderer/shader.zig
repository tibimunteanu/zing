const std = @import("std");
const config = @import("../config.zig");

// TODO: make this an union(enum) and dispatch based on a global variable rather than a compile time constant
const ShaderBackend = switch (config.renderer_backend_type) {
    .vulkan => @import("vulkan/vulkan_shader.zig"),
};

const Allocator = std.mem.Allocator;
pub const InstanceHandle = ShaderBackend.InstanceHandle;
pub const UniformHandle = u8;

const Shader = @This();

allocator: Allocator,
name: std.BoundedArray(u8, 256),

uniforms: std.ArrayList(Uniform),
uniform_lookup: std.StringHashMap(UniformHandle),

backend: ShaderBackend,

pub fn init(allocator: Allocator, shader_config: Config) !Shader {
    var self: Shader = undefined;
    self.allocator = allocator;

    self.name = try std.BoundedArray(u8, 256).fromSlice(shader_config.name);

    self.uniforms = try std.ArrayList(Uniform).initCapacity(allocator, 8);
    errdefer self.uniforms.deinit();

    self.uniform_lookup = std.StringHashMap(UniformHandle).init(allocator);
    errdefer self.uniform_lookup.deinit();

    try self.addUniforms(.global, shader_config.global_uniforms);
    try self.addUniforms(.instance, shader_config.instance_uniforms);
    try self.addUniforms(.local, shader_config.local_uniforms);

    self.backend = try ShaderBackend.init(allocator, &self, shader_config);

    return self;
}

pub fn deinit(self: *Shader) void {
    var it = self.uniform_lookup.keyIterator();
    while (it.next()) |key| {
        self.allocator.free(key.*);
    }

    self.uniform_lookup.deinit();
    self.uniforms.deinit();

    self.backend.deinit();

    self.* = undefined;
}

pub fn initInstance(self: *Shader) !InstanceHandle {
    return try self.backend.initInstance();
}

pub fn deinitInstance(self: *Shader, handle: InstanceHandle) void {
    self.backend.deinitInstance(handle);
}

pub fn bind(self: *const Shader) void {
    self.backend.bind();
}

pub fn bindGlobal(self: *Shader) void {
    self.backend.bindGlobal();
}

pub fn bindInstance(self: *Shader, handle: InstanceHandle) !void {
    try self.backend.bindInstance(handle);
}

pub fn getUniformHandle(self: *Shader, name: []const u8) !UniformHandle {
    return self.uniform_lookup.get(name) orelse error.UniformNotFound;
}

pub fn setUniform(self: *Shader, uniform: anytype, value: anytype) !void {
    const uniform_handle = if (@TypeOf(uniform) == UniformHandle)
        uniform
    else if (@typeInfo(@TypeOf(uniform)) == .Pointer and std.meta.Elem(@TypeOf(uniform)) == u8)
        try self.getUniformHandle(uniform)
    else
        unreachable;

    try self.backend.setUniform(&self.uniforms.items[uniform_handle], value);
}

// utils
fn addUniforms(self: *Shader, scope: Scope, uniform_configs: []const UniformConfig) !void {
    var offset: u32 = 0;
    var texture_index: u16 = 0;

    for (uniform_configs) |uniform_config| {
        const uniform_handle: UniformHandle = @truncate(self.uniforms.items.len);
        const uniform_data_type = try getDataType(uniform_config.data_type);
        const uniform_size = getDataTypeSize(uniform_data_type);

        try self.uniforms.append(Shader.Uniform{
            .scope = scope,
            .name = try std.BoundedArray(u8, 256).fromSlice(uniform_config.name),
            .data_type = uniform_data_type,
            .size = uniform_size,
            .offset = offset,
            .texture_index = if (uniform_data_type == .sampler) texture_index else 0,
        });

        try self.uniform_lookup.put(try self.allocator.dupe(u8, uniform_config.name), uniform_handle);

        offset += if (scope == .local) std.mem.alignForward(u32, uniform_size, 4) else uniform_size;
        if (uniform_data_type == .sampler) texture_index += 1;
    }
}

inline fn getDataType(data_type: []const u8) !UniformDataType {
    return std.meta.stringToEnum(UniformDataType, data_type) orelse error.UnknownDataType;
}

inline fn getDataTypeSize(data_type: UniformDataType) u32 {
    return switch (data_type) {
        .sampler => 0,
        .int8, .uint8 => 1,
        .int16, .uint16 => 2,
        .int32, .uint32, .float32 => 4,
        .float32_2 => 8,
        .float32_3 => 12,
        .float32_4 => 16,
        .mat_4 => 64,
    };
}

pub const Scope = enum(u8) {
    global = 0,
    instance = 1,
    local = 2,
};

pub const UniformDataType = enum(u8) {
    sampler,
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
    mat_4,
};

pub const Uniform = struct {
    scope: Scope,
    name: std.BoundedArray(u8, 256),
    data_type: UniformDataType,
    size: u32,
    offset: u32,
    texture_index: u16,
};

// config
pub const Config = struct {
    name: []const u8 = "new_shader",
    render_pass_name: []const u8 = "world",
    stages: []const StageConfig,
    attributes: []const AttributeConfig,
    global_uniforms: []const UniformConfig,
    instance_uniforms: []const UniformConfig,
    local_uniforms: []const UniformConfig,
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
    name: []const u8,
    data_type: []const u8,
};