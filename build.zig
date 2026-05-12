const std = @import("std");

pub fn build(b: *std.Build) void {
    const serve_exe = b.addExecutable(.{
        .name = "serve",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/serve.zig"),
            .optimize = .Debug,
            .target = b.graph.host,
        }),
    });

    const run_serve = b.addRunArtifact(serve_exe);
    run_serve.addArg("--zig-exe-path");
    run_serve.addArg(b.graph.zig_exe);

    if (b.args) |args| {
        run_serve.addArgs(args);
    }

    const serve_step = b.step("serve", "Start a web server to test the game");
    serve_step.dependOn(&run_serve.step);
}
