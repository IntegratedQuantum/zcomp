#version 430

layout(location=0) in vec2 vertex_pos;

layout(location=0) uniform vec2 position;
layout(location=1) uniform vec2 dimension;
layout(location=2) uniform vec2 screen;

void main() {
	gl_Position = vec4(((vertex_pos*dimension + position)/screen*2 - 1)*vec2(1, -1), 1, 1);
}