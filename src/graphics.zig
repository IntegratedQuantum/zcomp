const c = @import("main.zig").c;
const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn fileToString(allocator: Allocator, path: []const u8) ![]u8 {
	const file = try std.fs.cwd().openFile(path, .{});
	return file.readToEndAlloc(allocator, std.math.maxInt(u64));
}

pub const Color = extern struct {
	r: u8,
	g: u8,
	b: u8,

	pub fn put(self: Color, buffer: []u8) []u8 {
		buffer[0] = self.r;
		buffer[1] = self.g;
		buffer[2] = self.b;
		return buffer[0..3];
	}
	pub fn get(buffer: []u8) Color {
		return Color{.r = buffer[0], .g = buffer[1], .b = buffer[2]};
	}
};

var rectVao: c_uint = undefined;
var rectShader: Shader = undefined;
var imageShader: Shader = undefined;
pub fn init() !void {
	c.glGenVertexArrays(1, &rectVao);
	c.glBindVertexArray(rectVao);

	const corners = [_]f32 {
		0, 0,
		0, 1,
		1, 0,
		1, 1,
	};
	const indices = [_]u32 {
		0, 1, 2, 1, 2, 3,
	};
	var vbo: u32 = undefined;
	c.glGenBuffers(1, &vbo);
	c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
	c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(c_long, corners.len * @sizeOf(f32)), &corners, c.GL_STATIC_DRAW);

	c.glEnableVertexAttribArray(0);
	c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, @sizeOf(f32)*2, null);

	c.glGenBuffers(1, &vbo);
	c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, vbo);
	c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, @intCast(c_long, indices.len * @sizeOf(u32)), &indices, c.GL_STATIC_DRAW);

	c.glBindVertexArray(0);

	rectShader = try Shader.create("assets/shaders/rect_vertex.glsl", "assets/shaders/rect_fragment.glsl");
	imageShader = try Shader.create("assets/shaders/image_vertex.glsl", "assets/shaders/image_fragment.glsl");
}

pub fn drawRect(x: i32, y: i32, width: i32, height: i32, color: Color) void {
	rectShader.bind();
	c.glUniform2f(0, @intToFloat(f32, x), @intToFloat(f32, y));
	c.glUniform2f(1, @intToFloat(f32, width), @intToFloat(f32, height));
	c.glUniform2f(2, @intToFloat(f32, @import("main.zig").width), @intToFloat(f32, @import("main.zig").height));
	c.glUniform3f(3, @intToFloat(f32, color.r)/255.0, @intToFloat(f32, color.g)/255.0, @intToFloat(f32, color.b)/255.0);
	c.glBindVertexArray(rectVao);
	c.glDrawElements(c.GL_TRIANGLES, 6, c.GL_UNSIGNED_INT, null);
}

pub fn drawImage(x: i32, y: i32, width: i32, height: i32) void {
	imageShader.bind();
	c.glUniform2f(0, @intToFloat(f32, x), @intToFloat(f32, y));
	c.glUniform2f(1, @intToFloat(f32, width), @intToFloat(f32, height));
	c.glUniform2f(2, @intToFloat(f32, @import("main.zig").width), @intToFloat(f32, @import("main.zig").height));
	c.glBindVertexArray(rectVao);
	c.glDrawElements(c.GL_TRIANGLES, 6, c.GL_UNSIGNED_INT, null);
}

pub const Shader = struct {
	id: u32,
	
	fn addShader(self: *const Shader, filename: []const u8, shader_stage: c_uint) !void {
		var source = try fileToString(std.heap.page_allocator, filename);
		defer std.heap.page_allocator.free(source);
		const ref_buffer = [_] [*c]u8 {@ptrCast([*c]u8, source.ptr)};
		var shader = c.glCreateShader(shader_stage);
		defer c.glDeleteShader(shader);
		
		c.glShaderSource(shader, 1, @ptrCast([*c]const [*c]const u8, &ref_buffer[0]), @ptrCast([*c]const c_int, &source.len));
		
		c.glCompileShader(shader);

		var success = c.GL_FALSE;
		c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &success);
		if(success != c.GL_TRUE) {
			var len: u32 = 0;
			c.glGetShaderiv(shader, c.GL_INFO_LOG_LENGTH, @ptrCast(*c_int, &len));
			var buf: [4096] u8 = undefined;
			c.glGetShaderInfoLog(shader, 4096, @ptrCast(*c_int, &len), &buf);
			std.log.err("Error compiling shader {s}({}):\n{s}\n", .{filename, len, buf[0..len]});
			return anyerror.Error;
		}

		c.glAttachShader(self.id, shader);
	}

	fn compile(self: *const Shader) !void {
		c.glLinkProgram(self.id);

		var success = c.GL_FALSE;
		c.glGetProgramiv(self.id, c.GL_LINK_STATUS, &success);
		if(success != c.GL_TRUE) {
			var len: u32 = undefined;
			c.glGetProgramiv(self.id, c.GL_INFO_LOG_LENGTH, @ptrCast(*c_int, &len));
			var buf: [4096] u8 = undefined;
			c.glGetProgramInfoLog(self.id, 4096, @ptrCast(*c_int, &len), &buf);
			std.log.err("Error Linking Shader program({}):\n{s}\n", .{len, buf});
			return anyerror.Error;
		}
	} 
	
	pub fn create(vertex: []const u8, fragment: []const u8) !Shader {
		var shader = Shader{.id = c.glCreateProgram()};
		try shader.addShader(vertex, c.GL_VERTEX_SHADER);
		try shader.addShader(fragment, c.GL_FRAGMENT_SHADER);
		try shader.compile();
		return shader;
	}

	pub fn bind(self: *Shader) void {
		c.glUseProgram(self.id);
	}
};