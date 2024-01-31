#version 450

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec3 in_color;

layout(location = 0) out vec3 out_color;

layout(set = 0, binding = 0) uniform global_uniform_object {
    mat4 projection;
    mat4 view;
} global_data;

layout(push_constant) uniform push_constants {
    mat4 model;
} object_data;

void main() {
    gl_Position = global_data.projection * global_data.view * object_data.model * vec4(in_position, 1.0);

    out_color = in_color;
}