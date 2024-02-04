#version 450

layout(location = 0) in vec3 in_color;

layout(location = 0) out vec4 out_color;

layout(set = 1, binding = 0) uniform local_uniform_object {
    vec4 diffuse_color;
} object_data;

void main() {
    out_color = object_data.diffuse_color;
}