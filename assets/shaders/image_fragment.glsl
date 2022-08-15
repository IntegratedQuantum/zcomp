#version 430

out vec4 outColor;

in vec2 textureCoords;

layout(binding=0) uniform sampler2D image;
layout(binding=1) uniform sampler1D palette;

void main() {
	outColor = texture(palette, texture(image, textureCoords).r);
}