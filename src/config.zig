pub const max_path_length: u32 = 2048;
pub const max_swapchain_image_count = 8;
pub const target_frame_seconds: f32 = 1.0 / 60.0;

pub const shader_max_instance_count = 1024;
pub const shader_max_stages = 2;
pub const shader_max_bindings = 2;
pub const shader_max_global_textures = 31;
pub const shader_max_instance_textures = 31;
pub const shader_max_attributes = 16;
pub const shader_max_uniforms = 128;
pub const shader_max_push_const_ranges = 32;
pub const shader_descriptor_allocate_max_sets = 1024;

pub const renderer_backend_type = RendererBackendType.vulkan;

pub const RendererBackendType = enum {
    vulkan,
};
