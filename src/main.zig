const std = @import("std");
const builtin = @import("builtin");

const graphics = @import("graphics.zig");

pub const c = @cImport ({
	@cInclude("glad/glad.h");
	@cInclude("GLFW/glfw3.h");
});

pub const width: u31 = 240;
pub const height: u31 = 135;

var ssbo: [4]c_uint = undefined;

const Color = graphics.Color;

const allocator = std.heap.page_allocator;

fn scroll_callback(_: ?*c.GLFWwindow, _: f64, yOffset: f64) callconv(.C) void {
	std.log.info("{}\n", .{yOffset});
}

fn window_size_callback(_: ?*c.GLFWwindow, newWidth: c_int, newHeight: c_int) callconv(.C) void {
	_ = newHeight;
	_ = newWidth;
}

fn key_callback(_: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
	std.log.info("{} {} {} {}\n", .{key, scancode, action, mods});
}

fn genComputeProg(path: []const u8) c_uint {
	// Creating the compute shader, and the program object containing the shader
	const progHandle = c.glCreateProgram();
	const cs = c.glCreateShader(c.GL_COMPUTE_SHADER);
	var source = graphics.fileToString(std.heap.page_allocator, path) catch unreachable;
	defer std.heap.page_allocator.free(source);
	const ref_buffer = [_] [*c]u8 {@ptrCast([*c]u8, source.ptr)};
	
	c.glShaderSource(cs, 1, @ptrCast([*c]const [*c]const u8, &ref_buffer[0]), @ptrCast([*c]const c_int, &source.len));

	c.glCompileShader(cs);
	var rvalue: c_int = undefined;
	c.glGetShaderiv(cs, c.GL_COMPILE_STATUS, &rvalue);
	if (rvalue == 0) {
		std.log.err("Error in compiling the compute shader\n", .{});
		var log: [10240]u8 = undefined;
		var length: c_int = undefined;
		c.glGetShaderInfoLog(cs, 10239, &length, &log);
		std.log.err("Compiler log:\n{s}\n", .{log});
		std.os.exit(40);
	}
	c.glAttachShader(progHandle, cs);

	c.glLinkProgram(progHandle);
	c.glGetProgramiv(progHandle, c.GL_LINK_STATUS, &rvalue);
	if (rvalue == 0) {
		std.log.err("Error in linking the compute shader\n", .{});
		var log: [10240]u8 = undefined;
		var length: c_int = undefined;
		c.glGetProgramInfoLog(progHandle, 10239, &length, &log);
		std.log.err("Linker log:\n{s}\n", .{log});
		std.os.exit(41);
	}   
	c.glUseProgram(progHandle);
	
	c.glUniform1i(c.glGetUniformLocation(progHandle, "destTex"), 0);
	return progHandle;
}

fn genRenderProg() c_uint {
	const progHandle = c.glCreateProgram();
	const vp = c.glCreateShader(c.GL_VERTEX_SHADER);
	const fp = c.glCreateShader(c.GL_FRAGMENT_SHADER);

	const vpSrc = [_][*]const u8{
		"#version 430\n",
		\\	uniform ivec2 posOffset;
		\\	uniform ivec2 dim;
		\\	uniform int offset;
		\\layout(location=0) in vec2 pos;
		\\ out vec2 texCoord;
		\\ void main() {
		\\	 texCoord = pos*0.5f + 0.5f;
		\\	 if(offset == 0) gl_Position = vec4(pos * vec2(0.5, 1) - vec2(0.5, 0), 0.0, 1.0);
		\\	 else gl_Position = vec4(pos * vec2(0.5, 1) + vec2(0.5, 0), 0.0, 1.0);
		\\ }
	};

	const fpSrc = [_][*]const u8{
		"#version 430\n",
		\\	uniform ivec2 pos;
		\\	uniform ivec2 dim;
		\\	uniform int offset;
		\\	in vec2 texCoord;
		\\	out vec4 color;
		\\	layout(std430, binding = 5) buffer ssbo3 {
		\\		float neuronOutput[];
		\\	};
		\\	void main() {
		\\		int index = int(texCoord.x*dim.x) + int(texCoord.y*dim.y)*dim.x;
		\\		float state = neuronOutput[offset + index];
		\\		if (isnan(state))
		\\			color = vec4(1, 0, 0, 1);
		\\		else
		\\			color = vec4(0, state, 0, 1);
		\\	}
	};

	c.glShaderSource(vp, 2, &vpSrc, null);
	c.glShaderSource(fp, 2, &fpSrc, null);

	c.glCompileShader(vp);
	var rvalue: c_int = undefined;
	c.glGetShaderiv(vp, c.GL_COMPILE_STATUS, &rvalue);
	if (rvalue == 0) {
		std.log.err("Error in compiling vp\n", .{});
		var log: [10240]u8 = undefined;
		var length: c_int = undefined;
		c.glGetShaderInfoLog(vp, 10239, &length, &log);
		std.log.err("Compiler log:\n{s}\n", .{log});
		std.os.exit(30);
	}
	c.glAttachShader(progHandle, vp);

	c.glCompileShader(fp);
	c.glGetShaderiv(fp, c.GL_COMPILE_STATUS, &rvalue);
	if (rvalue == 0) {
		std.log.err("Error in compiling fp\n", .{});
		var log: [10240]u8 = undefined;
		var length: c_int = undefined;
		c.glGetShaderInfoLog(fp, 10239, &length, &log);
		std.log.err("Compiler log:\n{s}\n", .{log});
		std.os.exit(31);
	}
	c.glAttachShader(progHandle, fp);

	c.glBindFragDataLocation(progHandle, 0, "color");
	c.glLinkProgram(progHandle);

	c.glGetProgramiv(progHandle, c.GL_LINK_STATUS, &rvalue);
	if (rvalue == 0) {
		std.log.err("Error in linking vp\n", .{});
		std.os.exit(32);
	}   
	
	c.glUseProgram(progHandle);
	c.glUniform1i(c.glGetUniformLocation(progHandle, "srcTex"), 0);

	var vertArray: c_uint = undefined;
	c.glGenVertexArrays(1, &vertArray);
	c.glBindVertexArray(vertArray);

	var posBuf: c_uint = undefined;
	c.glGenBuffers(1, &posBuf);
	c.glBindBuffer(c.GL_ARRAY_BUFFER, posBuf);
	var data = [_]f32{
		-1.0, -1.0,
		-1.0, 1.0,
		1.0, -1.0,
		1.0, 1.0
	};
	c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(f32)*8, &data, c.GL_STREAM_DRAW);
	var posPtr: c_uint = 0;
	c.glVertexAttribPointer(posPtr, 2, c.GL_FLOAT, c.GL_FALSE, 0, null);
	c.glEnableVertexAttribArray(posPtr);

	return progHandle;
}

const LayerData = extern struct {
	size: i32,
	offset: i32,
};

const Neuron = extern struct {
	weights: [1024]f32,
	bias: f32,
};

const layers = [_]i32 {32*32, 8*8, 8, 8*8, 32*32};
const multiplier: u64 = 0x5DEECE66D;
const addend: u64 = 0xB;
const mask: u64 = (1 << 48) - 1;
pub fn next(_seed: u64) u64 {
	return _seed*%multiplier +% addend  &  mask;
}
var imageData: []f32 = undefined;
var seed: u64 = (6738962906 ^ multiplier) & mask;

fn genSSBO() !void {
	var metaData: [layers.len+1]LayerData = undefined;
	var offset: i32 = 0;
	for(layers) |_, i| {
		metaData[i].size = layers[i];
		metaData[i].offset = offset;
		offset += layers[i];
	}
	metaData[layers.len].size = 0;
	metaData[layers.len].offset = 0;
	var data: []Neuron = try std.heap.page_allocator.alloc(Neuron, @intCast(usize, offset));
	defer std.heap.page_allocator.free(data);

	imageData = try std.heap.page_allocator.alloc(f32, @intCast(usize, offset));
	const neuronInput = try std.heap.page_allocator.alloc(f32, @intCast(usize, offset));
	defer std.heap.page_allocator.free(neuronInput);
	std.log.info("Len: {}", .{imageData.len});
	for(data) |*neuron| {
		const range: u64 = 0xffff;
		seed = next(seed);
		neuron.bias = @intToFloat(f32, seed & range) / @intToFloat(f32, range) - 0.5;
		for(neuron.weights) |*weight| {
			seed = next(seed);
			weight.* = (@intToFloat(f32, seed & range) / @intToFloat(f32, range) - 0.5)/16;
		}
	}
	c.glGenBuffers(4, &ssbo);
	c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, ssbo[0]);
	c.glBufferData(c.GL_SHADER_STORAGE_BUFFER, @intCast(c_long, data.len*@sizeOf(Neuron)), data.ptr, c.GL_STATIC_DRAW); //sizeof(data) only works for statically sized C/C++ arrays.
	c.glBindBufferBase(c.GL_SHADER_STORAGE_BUFFER, 3, ssbo[0]);
	c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, ssbo[1]);
	c.glBufferData(c.GL_SHADER_STORAGE_BUFFER, @intCast(c_long, metaData.len*@sizeOf(LayerData)), &metaData, c.GL_STATIC_DRAW); //sizeof(data) only works for statically sized C/C++ arrays.
	c.glBindBufferBase(c.GL_SHADER_STORAGE_BUFFER, 4, ssbo[1]);
	c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, ssbo[2]);
	c.glBufferData(c.GL_SHADER_STORAGE_BUFFER, @intCast(c_long, imageData.len*@sizeOf(f32)), imageData.ptr, c.GL_STATIC_DRAW); //sizeof(data) only works for statically sized C/C++ arrays.
	c.glBindBufferBase(c.GL_SHADER_STORAGE_BUFFER, 5, ssbo[2]);
	c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, ssbo[3]);
	c.glBufferData(c.GL_SHADER_STORAGE_BUFFER, @intCast(c_long, neuronInput.len*@sizeOf(f32)), neuronInput.ptr, c.GL_STATIC_DRAW); //sizeof(data) only works for statically sized C/C++ arrays.
	c.glBindBufferBase(c.GL_SHADER_STORAGE_BUFFER, 6, ssbo[3]);
	c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, 0); // unbind
}

fn genImage() void {
	const range: u64 = 31;
	seed = next(seed);
	var rectX: u64 = seed>>16 & range;
	seed = next(seed);
	var rectY: u64 = seed>>16 & range;
	seed = next(seed);
	var rectWidth: u64 = seed>>16 & range;
	seed = next(seed);
	var rectHeight: u64 = seed>>16 & range;
	var x: u32 = 0;
	while(x < 32): (x += 1) {
		var y: u32 = 0;
		while(y < 32): (y += 1) {
			if(x >= rectX and x < rectX + rectWidth and y >= rectY and y < rectY + rectHeight) {
				imageData[x + y*32] = 1;
			} else {
				imageData[x + y*32] = 0;
			}
		}
	}
	c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, ssbo[2]);
	c.glBufferData(c.GL_SHADER_STORAGE_BUFFER, @intCast(c_long, imageData.len*@sizeOf(f32)), imageData.ptr, c.GL_STATIC_DRAW);
	c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, 0); // unbind
}

pub fn main() anyerror!void {
	var window: *c.GLFWwindow = undefined;

	if(c.glfwInit() == 0) {
		return error.GLFWFailed;
	}

	window = c.glfwCreateWindow(@intCast(c_int, 8*width), @intCast(c_int, 8*height), "pixanim", null, null) orelse return error.GLFWFailed;

	c.glfwMakeContextCurrent(window);
	c.glfwSwapInterval(0);
	if(c.gladLoadGL() == 0) {
		return error.GLADFailed;
	}

	_ = c.glfwSetWindowSizeCallback(window, window_size_callback);
	_ = c.glfwSetKeyCallback(window, key_callback);
	_ = c.glfwSetScrollCallback(window, scroll_callback);

	try graphics.init();

	var lastTime = std.time.nanoTimestamp();

	const renderHandle = genRenderProg();
	const computeHandle = genComputeProg("assets/shaders/compute.glsl");
	const backpropHandle = genComputeProg("assets/shaders/backpropagation.glsl");
	try genSSBO();
	var frame: u31 = 0;
	while(c.glfwWindowShouldClose(window) == 0) {
		var deltaTime = std.time.nanoTimestamp() - lastTime;
		lastTime += deltaTime;
		const glError = c.glGetError();
		if(glError != 0) {
			std.log.err("Encountered gl error {}", .{glError});
			std.os.exit(1);
		}
		std.log.info("{}\n", .{deltaTime});
		c.glfwPollEvents();
		c.glViewport(0, 0, @intCast(c_int, 8*width), @intCast(c_int, 8*height));

		frame += 1;
		genImage();
		c.glUseProgram(computeHandle);
		for(layers) |_, i| {
			if(i != 0) {
				c.glUniform1i(c.glGetUniformLocation(computeHandle, "layer"), @intCast(c_int, i));
				c.glDispatchCompute(1, 1, 1);
				c.glMemoryBarrier(c.GL_SHADER_STORAGE_BARRIER_BIT);
			}
		}

		c.glUseProgram(renderHandle);
		c.glUniform2i(c.glGetUniformLocation(renderHandle, "dim"), 32, 32);
		c.glUniform2i(c.glGetUniformLocation(renderHandle, "posOffset"), 0, 0);
		c.glUniform1i(c.glGetUniformLocation(renderHandle, "offset"), 0);
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
		c.glUniform1i(c.glGetUniformLocation(renderHandle, "offset"), @intCast(c_int, imageData.len - 1024 - 136));
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);

		c.glfwSwapBuffers(window);
		c.glFinish();
		c.glClear(c.GL_COLOR_BUFFER_BIT);

		c.glUseProgram(backpropHandle);
		var i: i32 = layers.len - 1;
		while(i >= 0) : (i -= 1) {
			c.glUniform1i(c.glGetUniformLocation(backpropHandle, "layer"), @intCast(c_int, i));
			c.glDispatchCompute(1, 1, 1);
			c.glMemoryBarrier(c.GL_SHADER_STORAGE_BARRIER_BIT);
		}
	}

	c.glfwTerminate();
}
