#version 450

layout(location = 0) in struct dto{
 vec2 texcoord;
 vec4 color;
} in_dto;

layout(set = 1, binding = 0) uniform local_uniform_object {
    vec4 diffuse_color;
} object_data;

layout(set = 1, binding = 1) uniform sampler2D diffuse_sampler;

layout(location = 0) out vec4 out_color;

void main() {
    out_color = object_data.diffuse_color * in_dto.color * texture(diffuse_sampler, in_dto.texcoord);
}