const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
	// Standard target options allows the person running `zig build` to choose
	// what target to build for. Here we do not override the defaults, which
	// means any target is allowed, and the default is native. Other options
	// for restricting supported target set are available.
	const target = b.standardTargetOptions(.{});

	// Standard release options allow the person running `zig build` to select
	// between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
	const mode = b.standardReleaseOptions();

	const exe = b.addExecutable("pixanim", "src/main.zig");
	exe.addIncludeDir("include/");
	exe.addCSourceFile("lib/src/glad.c", &[_][]const u8{"-gdwarf-4",});
	switch (target.getOsTag()) {
		.linux => {
			exe.linkSystemLibrary("GL");
			exe.linkSystemLibrary("glfw");
		},
		else => {
			std.log.err("Unsupported target: {}\n", .{ target.getOsTag() });
			return;
		}
	}
	exe.linkLibC();
	exe.setTarget(target);
	exe.setBuildMode(mode);
	exe.install();

	const run_cmd = exe.run();
	run_cmd.step.dependOn(b.getInstallStep());
	if (b.args) |args| {
		run_cmd.addArgs(args);
	}

	const run_step = b.step("run", "Run the app");
	run_step.dependOn(&run_cmd.step);
}
