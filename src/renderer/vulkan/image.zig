const std = @import("std");
const vk = @import("vk.zig");
const Context = @import("context.zig").Context;
const Allocator = std.mem.Allocator;

pub const Image = struct {
    const Self = @This();

    handle: vk.Image,
    memory: vk.DeviceMemory,
    view: ?vk.ImageView = null,
    width: u32,
    height: u32,
    depth: u32,

    pub fn init(
        context: *const Context,
        options: struct {
            width: u32,
            height: u32,
            depth: u32 = 1,
            image_type: vk.ImageType = .@"2d",
            flags: vk.ImageCreateFlags = .{},
            mip_levels: u32 = 4,
            array_layers: u32 = 1,
            samples: vk.SampleCountFlags = .{ .@"1_bit" = true },
            format: vk.Format = .b8g8r8a8_srgb,
            tiling: vk.ImageTiling = .optimal,
            usage: vk.ImageUsageFlags = .{ .color_attachment_bit = true },
            sharing_mode: vk.SharingMode = .exclusive,
            queue_family_index_count: u32 = 0,
            p_queue_family_indices: ?[*]const u32 = null,
            initial_layout: vk.ImageLayout = .undefined,
            memory_flags: vk.MemoryPropertyFlags = .{ .device_local_bit = true },
            init_view: bool = false,
            view_type: vk.ImageViewType = .@"2d",
            view_aspect_flags: vk.ImageAspectFlags = .{ .color_bit = true },
        },
    ) !Self {
        var self: Self = undefined;

        self.width = options.width;
        self.height = options.height;
        self.depth = options.depth;

        const device_api = context.device_api;
        const device = context.device;

        self.handle = try device_api.createImage(device, &vk.ImageCreateInfo{
            .flags = options.flags,
            .image_type = options.image_type,
            .format = options.format,
            .extent = .{
                .width = options.width,
                .height = options.height,
                .depth = options.depth,
            },
            .mip_levels = options.mip_levels,
            .array_layers = options.array_layers,
            .samples = options.samples,
            .tiling = options.tiling,
            .usage = options.usage,
            .sharing_mode = options.sharing_mode,
            .queue_family_index_count = options.queue_family_index_count,
            .p_queue_family_indices = options.p_queue_family_indices,
            .initial_layout = options.initial_layout,
        }, null);
        errdefer device_api.destroyImage(device, self.handle, null);

        const memory_requirements = device_api.getImageMemoryRequirements(device, self.handle);

        self.memory = try context.allocate(memory_requirements, options.memory_flags);
        errdefer device_api.freeMemory(device, self.memory, null);

        try device_api.bindImageMemory(device, self.handle, self.memory, 0);

        if (options.init_view) {
            try self.initView(context, options.view_type, options.format, options.view_aspect_flags);
        }
        errdefer self.deinitView(context);

        return self;
    }

    pub fn deinit(self: *Self, context: *const Context) void {
        const device_api = context.device_api;
        const device = context.device;

        self.deinitView(context);

        device_api.destroyImage(device, self.handle, null);
        device_api.freeMemory(device, self.memory, null);
    }

    fn initView(
        self: *Self,
        context: *const Context,
        view_type: vk.ImageViewType,
        format: vk.Format,
        aspect_flags: vk.ImageAspectFlags,
    ) !void {
        self.view = try context.device_api.createImageView(context.device, &vk.ImageViewCreateInfo{
            .image = self.handle,
            .view_type = view_type,
            .format = format,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{
                .aspect_mask = aspect_flags,
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }, null);
    }

    fn deinitView(self: *Self, context: *const Context) void {
        if (self.view) |view| {
            context.device_api.destroyImageView(context.device, view, null);
            self.view = null;
        }
    }
};
