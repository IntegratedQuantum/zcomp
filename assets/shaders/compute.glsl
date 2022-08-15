#version 430

uniform float roll;
uniform writeonly image2D destTex;
layout (local_size_x = 1, local_size_y = 1) in;

struct Particle {
	vec2 pos, vel;
};

layout(std430, binding = 3) buffer ssbo {
	Particle particles[4096];
};

layout(std430, binding = 4) buffer ssbo2 {
	Particle particlesOut[4096];
};

void main() {
	uint i = gl_WorkGroupID.x;
	Particle part = particles[i];
	imageStore(destTex, ivec2(part.pos), vec4(0.0, 0.0, 0.0, 0.0));
	if(part.pos.x < 0 || part.pos.x > 512) {
		part.pos.x = clamp(part.pos.x, 0, 512);
		part.vel.x = -part.vel.x;
	}
	if(part.pos.y < 0 || part.pos.y > 512) {
		part.pos.y = clamp(part.pos.y, 0, 512);
		part.vel.y = -part.vel.y;
	}
	part.vel *= 0.99;
	for(int j = 0; j < 4096; j++) {
		float distSquare = 0.01 + dot(particles[j].pos - part.pos, particles[j].pos - part.pos);
		if(distSquare < 10000) {
			part.vel -= (particles[j].pos - part.pos)/distSquare/1000*(1/distSquare*10 - 1/20.0);
		}
	}
	part.pos += part.vel;
	particlesOut[i] = part;
	imageStore(destTex, ivec2(part.pos), vec4(1.0, 0.0, 0.0, 0.0));
}