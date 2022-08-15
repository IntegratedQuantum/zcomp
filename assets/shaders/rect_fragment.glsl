#version 430

out vec4 outColor;

layout(location=3) uniform vec3 color;

void main() {
	outColor = vec4(color, 1);
}