#version 430

#define MAX_LAYER_WIDTH 1024

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
	float storedNeuronInput[];
};

uniform int layer;

float sigmoid(float x) {
	return 1/(1+exp(-x));
}

void main() {
	int neuron = int(gl_LocalInvocationID.x);
	LayerData curLayer = layers[layer];
	LayerData pastLayer = layers[layer-1];
	if(neuron >= curLayer.size) return;

	int i = 0;
	float neuronInput = neurons[neuron + curLayer.offset].bias;
	while(i < pastLayer.size) {
		int pastNeuron = i + pastLayer.offset;
		neuronInput += neurons[pastNeuron].weights[neuron]*neuronOutput[pastNeuron];
		i += 1;
	}

	storedNeuronInput[neuron + curLayer.offset] = neuronInput;
	neuronOutput[neuron + curLayer.offset] = sigmoid(neuronInput);
}