#version 450

layout(location = 0) in struct dto{
 vec2 texcoord;
 vec4 color;
} in_dto;

layout(set = 1, binding = 0) uniform local_uniform_object {
    vec4 diffuse_color;
};

layout(set = 1, binding = 1) uniform sampler2D diffuse_texture;

layout(location = 0) out vec4 out_color;

void main() {
    out_color = diffuse_color * texture(diffuse_texture, in_dto.texcoord); //* in_dto.color
}