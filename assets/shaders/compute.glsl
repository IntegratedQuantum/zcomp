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

void main() {
	uint i = gl_WorkGroupID.x;
	imageStore(destTex, ivec2(particles[i].pos), vec4(0.0, 0.0, 0.0, 0.0));
	particles[i].pos += particles[i].vel;
	if(particles[i].pos.x < 0 || particles[i].pos.x > 512) {
		particles[i].pos.x = clamp(particles[i].pos.x, 0, 512);
		particles[i].vel.x = -particles[i].vel.x;
	}
	if(particles[i].pos.y < 0 || particles[i].pos.y > 512) {
		particles[i].pos.y = clamp(particles[i].pos.y, 0, 512);
		particles[i].vel.y = -particles[i].vel.y;
	}
	for(int j = 0; j < 1024; j++) {
		float distSquare = 0.01 + dot(particles[i].pos - particles[j].pos, particles[i].pos - particles[j].pos);
		if(distSquare < 100) {
			particles[i].vel -= (particles[j].pos - particles[i].pos)/distSquare/100;
		}
	}
	imageStore(destTex, ivec2(particles[i].pos), vec4(1.0, 0.0, 0.0, 0.0));
}