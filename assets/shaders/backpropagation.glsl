#version 430

#define MAX_LAYER_WIDTH 256

layout (local_size_x = MAX_LAYER_WIDTH, local_size_y = 1) in;

struct Neuron {
	float weights[MAX_LAYER_WIDTH];
	float bias;
};

struct LayerData {
	int size;
	int offset;
};

layout(std430, binding = 3) buffer ssbo {
	Neuron neurons[];
};

layout(std430, binding = 4) buffer ssbo2 {
	LayerData layers[];
};

layout(std430, binding = 5) buffer ssbo3 {
	float neuronOutput[];
};

layout(std430, binding = 6) buffer ssbo4 {
	float neuronInput[];
};

uniform int layer;

float sigmoid(float x) {
	return 1/(1+exp(-x));
}

float sigmoid_prime(float z) {
    return sigmoid(z)*(1-sigmoid(z));
}

// Random
float randomF (float seed) {
    return fract(sin(983.234567 * seed));
}

void main() {
	int neuron = int(gl_LocalInvocationID.x);
	LayerData curLayer = layers[layer];
	LayerData nextLayer = layers[layer+1];
	if(neuron >= curLayer.size) return;
	if(nextLayer.size == 0) {
		neuronOutput[neuron + curLayer.offset] = (neuronOutput[neuron] - neuronOutput[neuron + curLayer.offset])*sigmoid_prime(neuronInput[neuron + curLayer.offset]);
		neurons[neuron + curLayer.offset].bias = 0;
	} else {
		float seed = neuronOutput[neuron + curLayer.offset];
		float selfError = 0;
		int i = 0;
		while(i < nextLayer.size) {
			int nextNeuron = i + nextLayer.offset;
			selfError += neuronOutput[nextNeuron]*neurons[neuron + curLayer.offset].weights[i];
			seed = randomF(seed);
			neurons[neuron + curLayer.offset].weights[i] += neuronOutput[neuron + curLayer.offset]*neuronOutput[nextNeuron]*0.05*seed;
			i += 1;
		}
		selfError *= sigmoid_prime(neuronInput[neuron + curLayer.offset]);
		seed = randomF(seed);
		neurons[neuron + curLayer.offset].bias -= selfError*0.05*seed;
		neuronOutput[neuron + curLayer.offset] = selfError;
	}
}