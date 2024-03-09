#version 450

layout(location = 0) in vec2 in_position;
layout(location = 1) in vec2 in_texcoord;
layout(location = 2) in vec4 in_color;

layout(set = 0, binding = 0) uniform global_uniform_object {
    mat4 projection;
    mat4 view;
} global_data;

layout(push_constant) uniform push_constants {
    mat4 model;
} object_data;

layout(location = 0) out struct dto { 
    vec2 texcoord;
    vec4 color;
} out_dto;

void main() {
    out_dto.texcoord = in_texcoord;
    out_dto.color = in_color;

    gl_Position = global_data.projection * global_data.view * object_data.model * vec4(in_position, 0.0, 1.0);
}