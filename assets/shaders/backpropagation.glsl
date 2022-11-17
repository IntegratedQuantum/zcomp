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
	float neuronInput[];
};

uniform int layer;

float sigmoid(float x) {
	return 1/(1+exp(-x));
}

float sigmoid_prime(float z) {
    return sigmoid(z)*(1-sigmoid(z));
}

/*def backprop(self, x, y):
        """Return a tuple ``(nabla_b, nabla_w)`` representing the
        gradient for the cost function C_x.  ``nabla_b`` and
        ``nabla_w`` are layer-by-layer lists of numpy arrays, similar
        to ``self.biases`` and ``self.weights``."""
        nabla_b = [np.zeros(b.shape) for b in self.biases]
        nabla_w = [np.zeros(w.shape) for w in self.weights]
        # feedforward
        activation = x
        activations = [x] # list to store all the activations, layer by layer
        zs = [] # list to store all the z vectors, layer by layer
        for b, w in zip(self.biases, self.weights):
            z = np.dot(w, activation)+b
            zs.append(z)
            activation = sigmoid(z)
            activations.append(activation)
        # backward pass
        delta = self.cost_derivative(activations[-1], y) * \
            sigmoid_prime(zs[-1])
        nabla_b[-1] = delta
        nabla_w[-1] = np.dot(delta, activations[-2].transpose())
        # Note that the variable l in the loop below is used a little
        # differently to the notation in Chapter 2 of the book.  Here,
        # l = 1 means the last layer of neurons, l = 2 is the
        # second-last layer, and so on.  It's a renumbering of the
        # scheme in the book, used here to take advantage of the fact
        # that Python can use negative indices in lists.
        for l in xrange(2, self.num_layers):
            z = zs[-l]
            sp = sigmoid_prime(z)
            delta = np.dot(self.weights[-l+1].transpose(), delta) * sp
            nabla_b[-l] = delta
            nabla_w[-l] = np.dot(delta, activations[-l-1].transpose())
        return (nabla_b, nabla_w)*/

void main() {
	int neuron = int(gl_LocalInvocationID.x);
	LayerData curLayer = layers[layer];
	LayerData nextLayer = layers[layer+1];
	if(neuron >= curLayer.size) return;
	if(nextLayer.size == 0) {
		neuronOutput[neuron + curLayer.offset] = (neuronOutput[neuron] - neuronOutput[neuron + curLayer.offset])*sigmoid_prime(neuronInput[neuron + curLayer.offset]);
		neurons[neuron + curLayer.offset].bias = 0;
	} else {
		float selfError = 0;
		int i = 0;
		while(i < nextLayer.size) {
			int nextNeuron = i + nextLayer.offset;
			selfError += neuronOutput[nextNeuron]*neurons[neuron + curLayer.offset].weights[i];
			neurons[neuron + curLayer.offset].weights[i] += neuronOutput[nextNeuron]*0.1;
			i += 1;
		}
		selfError *= sigmoid_prime(neuronInput[neuron + curLayer.offset]);
		neuronOutput[neuron + curLayer.offset] = selfError;
		neurons[neuron + curLayer.offset].bias += selfError*0.1;
	}
}