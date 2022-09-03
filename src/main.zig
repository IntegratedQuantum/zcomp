const std = @import("std");
const builtin = @import("builtin");

const graphics = @import("graphics.zig");

pub const c = @cImport ({
	@cInclude("glad/glad.h");
	@cInclude("GLFW/glfw3.h");
});

pub var width: u31 = 1920;
pub var height: u31 = 1080;

pub const imageWidth: u31 = 512;
pub const imageHeight: u31 = 512;
pub const numParticles: u31 = 4096;

var ssbo: [2]c_uint = undefined;

const Color = graphics.Color;

const allocator = std.heap.page_allocator;

fn scroll_callback(_: ?*c.GLFWwindow, _: f64, yOffset: f64) callconv(.C) void {
	std.log.info("{}\n", .{yOffset});
}

fn window_size_callback(_: ?*c.GLFWwindow, newWidth: c_int, newHeight: c_int) callconv(.C) void {
	width = @intCast(u31, newWidth);
	height = @intCast(u31, newHeight);
}

fn key_callback(_: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
	std.log.info("{} {} {} {}\n", .{key, scancode, action, mods});
}

fn genComputeProg() c_uint {
	// Creating the compute shader, and the program object containing the shader
	const progHandle = c.glCreateProgram();
	const cs = c.glCreateShader(c.GL_COMPUTE_SHADER);
	var source = graphics.fileToString(std.heap.page_allocator, "assets/shaders/compute.glsl") catch unreachable;
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
		\\layout(location=0) in vec2 pos;
		\\ out vec2 texCoord;
		\\ void main() {
		\\	 texCoord = pos*0.5f + 0.5f;
		\\	 gl_Position = vec4(pos.x, pos.y, 0.0, 1.0);
		\\ }
	};

	const fpSrc = [_][*]const u8{
		"#version 430\n",
		\\uniform sampler2D srcTex;
		\\ in vec2 texCoord;
		\\ out vec4 color;
		\\ void main() {
		\\	 float c = texture(srcTex, texCoord).x;
		\\	 color = vec4(c, c, c, 1.0);
		\\ }
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

fn genTexture() c_uint {
	// We create a single float channel 512^2 texture
	var texHandle: c_uint = undefined;
	c.glGenTextures(1, &texHandle);

	c.glActiveTexture(c.GL_TEXTURE0);
	c.glBindTexture(c.GL_TEXTURE_2D, texHandle);
	c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
	c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
	c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_R32F, imageWidth, imageHeight, 0, c.GL_RED, c.GL_FLOAT, null);

	// Because we're also using this tex as an image (in order to write to it),
	// we bind it to an image unit as well
	c.glBindImageTexture(0, texHandle, 0, c.GL_FALSE, 0, c.GL_WRITE_ONLY, c.GL_R32F);
	return texHandle;
}

fn genSSBO() void {
	var random: f32 = 1;
	var data: [numParticles*4]f32 = [_]f32{0} ** (numParticles*4);
	for(data) |_, i| {
		random -= 1.8;
		random = random*random;
		random -= 1.8;
		random = random*random;
		random -= 1.8;
		random = random*random;
		random -= 1.8;
		random = random*random;
		random -= 1.8;
		random = random*random;
		random -= 1.8;
		random = random*random;
		random -= 1.8;
		random = random*random;
		random -= 1.8;
		random = random*random;
		random -= 1.8;
		random = random*random;
		random -= 1.8;
		random = random*random;
		random -= 1.8;
		random = random*random;
		if((i & 3) <= 1) {
			data[i] = random*@intToFloat(f32, imageWidth)/4;
		} else {
			data[i] = random;
		}
	}
	c.glGenBuffers(2, &ssbo);
	c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, ssbo[0]);
	c.glBufferData(c.GL_SHADER_STORAGE_BUFFER, data.len*4, &data, c.GL_STATIC_DRAW); //sizeof(data) only works for statically sized C/C++ arrays.
	c.glBindBufferBase(c.GL_SHADER_STORAGE_BUFFER, 3, ssbo[0]);
	c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, ssbo[1]);
	c.glBufferData(c.GL_SHADER_STORAGE_BUFFER, data.len*4, &data, c.GL_STATIC_DRAW); //sizeof(data) only works for statically sized C/C++ arrays.
	c.glBindBufferBase(c.GL_SHADER_STORAGE_BUFFER, 4, ssbo[1]);
	c.glBindBuffer(c.GL_SHADER_STORAGE_BUFFER, 0); // unbind
}

pub fn main() anyerror!void {
	var window: *c.GLFWwindow = undefined;

	if(c.glfwInit() == 0) {
		return error.GLFWFailed;
	}

	window = c.glfwCreateWindow(@intCast(c_int, width), @intCast(c_int, height), "pixanim", null, null) orelse return error.GLFWFailed;

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

	const texHandle = genTexture();
	_ = texHandle;
	const renderHandle = genRenderProg();
	const computeHandle = genComputeProg();
	genSSBO();
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
		c.glViewport(0, 0, @intCast(c_int, width), @intCast(c_int, height));

		frame += 1;
		c.glBindBufferBase(c.GL_SHADER_STORAGE_BUFFER, 3, ssbo[frame & 1]);
		c.glBindBufferBase(c.GL_SHADER_STORAGE_BUFFER, 4, ssbo[(frame ^ 1) & 1]);
		c.glUseProgram(computeHandle);
		c.glUniform1f(c.glGetUniformLocation(computeHandle, "roll"), @intToFloat(f32, @divFloor(lastTime, 1000000) & 65535)/100.0);
		c.glDispatchCompute(numParticles, 1, 1);

		c.glUseProgram(renderHandle);
		c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);

		c.glfwSwapBuffers(window);
		c.glClear(c.GL_COLOR_BUFFER_BIT);
	}

	c.glfwTerminate();
}
