const std = @import("std");
// const rl = @import("raylib-zig/build.zig");
const rayc = @import("raylib-c/src/build.zig");

pub fn build(b: *std.Build) !void {
    try build_with_zigbuild(b);
}
pub fn build_with_zigbuild(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const options = rayc.Options{.raygui = true};
    const raylib = rayc.addRaylib(b, target, optimize, options);
    b.installArtifact(raylib); // add it to ./zig-out/lib

    
    const game_only = b.option(bool, "game_only", "only build game.zig") orelse false;
    const game_lib = b.addSharedLibrary(.{
        .name = "game",
        .root_source_file = .{ .path = "src/game.zig" },
        .target = target,
        .optimize = optimize,
        .version = .{ .major = 1, .minor = 0, .patch = 0 },
    });
    game_lib.linkLibrary(raylib);
    game_lib.linkLibC();
    game_lib.addIncludePath(.{ .path = "raylib-c/src" });
    b.installArtifact(game_lib);
    if (game_only) {
        return;
    }
    // const raycroot = "raylib-c/";
    // lib.installHeader(raycroot ++ "src/raylib.h", "raylib.h");
    // lib.installHeader(raycroot ++ "src/raymath.h", "raymath.h");
    // lib.installHeader(raycroot ++ "src/rlgl.h", "rlgl.h");

    // b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "raylib-building",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibrary(raylib);
    exe.addIncludePath(.{ .path = "raylib-c/src" });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run raylib-buildings with zig-build");
    run_step.dependOn(&run_cmd.step);
}
pub fn build_with_c(b: *std.Build) !void {
    // first build raylib with make and then run this procedure
    // build raylib in raylib-c with `make CC="zig cc" PLATFORM=PLATFORM_DESKTOP`
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // _ = b;
    // @compileLog(rayc.srcdir ++ "/external/glfw/include");
    // const options = rayc.Options{};
    // const raylib = rayc.addRaylib(b, target, optimize, options);
    // _ = raylib;

    const exe = b.addExecutable(.{
        .name = "raylib-demo",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.linkSystemLibrary("c");
    exe.addIncludePath(.{ .path = "raylib-c/src" });
    exe.addLibraryPath(.{ .path = "raylib-c/src" });

    exe.linkSystemLibrary("raylib");
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

pub fn build_with_system_raylib(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "raylib-demo",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    // exe.addObjectFile(.{ .path = "lib/libraylib.a" });
    // exe.addObjectFile(.{ .path = "rcore.o" });
    // exe.addObjectFile(.{ .path = "rtextures.o" });
    // exe.addObjectFile(.{ .path = "rtext.o" });
    // exe.addIncludePath(.{ .path = "include" });
    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("raylib");

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run raylib-demo");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
