const std = @import("std");
const Thread = std.Thread;
// const Pool = Thread.Pool;
const Semaphore = Thread.Semaphore;
const ray = @cImport({
    @cInclude("raylib.h");
    // @cInclude("raymath.h");
    @cInclude("rlgl.h");
});

const screen_w = 1092;
const screen_h = 603;

const GameStatePtr = *anyopaque;

var gameInit: *const fn () GameStatePtr = undefined;
var gameReload: *const fn (GameStatePtr) void = undefined;
var gameUnload: *const fn (GameStatePtr) void = undefined;
var gameTick: *const fn (GameStatePtr) void = undefined;
var gameDraw: *const fn (GameStatePtr) void = undefined;

const CompileState = enum {
    not_compiling,
    compiling,
    finished_compiling,
};
var compile_state = CompileState.not_compiling;
var compiling_thread: ?Thread = null;
var semaphore: Semaphore = Semaphore{};

pub fn dynMain() !void {
    const allocator = std.heap.c_allocator;
    loadGameDll() catch @panic("Failed in first load");
    const game_state = gameInit();
    ray.InitWindow(screen_w, screen_h, "Zig Hot-Reload");
    ray.SetTargetFPS(60);
    while (!ray.WindowShouldClose()) {
        // semaphore and thread compilation
        if (ray.IsKeyPressed(ray.KEY_F5)) {
            if (compiling_thread) |_| {
                std.debug.print("thread is here trying to compile\n", .{});
                compile_state = .compiling;
                semaphore.post();
                // compile_state.compiling = true;
            } else {
                std.debug.print("new thread initialized\n", .{});
                semaphore.post();
                compiling_thread = try Thread.spawn(.{}, semaCompile, .{allocator});
                compiling_thread.?.detach();
            }
        }
        gameTick(game_state);
        ray.BeginDrawing();
        gameDraw(game_state);
        if (compile_state == .compiling) {
            ray.DrawText("Compiling", 10, 50, 20, ray.RED);
        }
        ray.EndDrawing();
        // reload game after compiling.
        if (compile_state == .finished_compiling) {
            compile_state = .not_compiling;
            unloadGameDll(game_state) catch @panic("POOL: failed to unload the game");
            loadGameDll() catch @panic("POOL: Failed loading async");
            gameReload(game_state);
        }
    }
    ray.CloseWindow();
}

fn unloadGameDll(game_state: GameStatePtr) !void {
    if (game_dyn_lib) |*dyn_lib| {
        gameUnload(game_state);
        dyn_lib.close();
        game_dyn_lib = null;
    } else {
        return error.AlreadyUnloaded;
    }
}

var game_dyn_lib: ?std.DynLib = null;
fn loadGameDll() !void {
    if (game_dyn_lib != null) return error.AlreadyLoaded;

    // const libName = "game.dll";
    const builtin = @import("builtin");
    const libName = switch (builtin.os.tag) {
        .linux => "libgame.so",
        .windows => "game.dll",
        else => "libgame.so",
    };
    var dyn_lib = std.DynLib.open("zig-out/lib/" ++ libName) catch {
        return error.OpenFail;
    };
    game_dyn_lib = dyn_lib;
    gameInit = dyn_lib.lookup(@TypeOf(gameInit), "gameInit") orelse return error.LookUpFail;
    gameReload = dyn_lib.lookup(@TypeOf(gameReload), "gameReload") orelse return error.LookUpFail;
    gameUnload = dyn_lib.lookup(@TypeOf(gameUnload), "gameUnload") orelse return error.LookUpFail;
    gameTick = dyn_lib.lookup(@TypeOf(gameTick), "gameTick") orelse return error.LookUpFail;
    gameDraw = dyn_lib.lookup(@TypeOf(gameDraw), "gameDraw") orelse return error.LookUpFail;
    std.debug.print("----------------Loaded game.dll/libgame.so----------------\n", .{});
}

fn recompileGameDll(allocator: std.mem.Allocator) !void {
    const process_args = [_][]const u8{ "zig", "build", "-Dgame_only=true" };
    var build_process = std.ChildProcess.init(&process_args, allocator);
    try build_process.spawn();

    const term = try build_process.wait();
    switch (term) {
        .Exited => |exited| {
            if (exited == 2) return error.RecompileFail;
        },
        else => return,
    }
}

/// semaphore and thread
fn semaCompile(allocator: std.mem.Allocator) void {
    while (true) {
        semaphore.wait();
        std.debug.print("compiling..........\n", .{});
        recompileGameDll(allocator) catch {
            // std.debug.print("failing compiling >_<\n", .{});
            // compile_state = .failed;
            continue;
        };
        compile_state = .finished_compiling;
        std.debug.print("Finished compiling.....\n", .{});
    }
}
fn poolCompile(allocator: std.mem.Allocator, game_state: *anyopaque) void {
    _ = game_state;
    std.debug.print("POOL: Compiling......\n", .{});

    recompileGameDll(allocator) catch {
        @panic("POOL: Failing compiling async game.dll");
    };
    std.debug.print("POOL: Finished compiling....\n", .{});
    compile_state = .finished_compiling;
}
/// for simple thread compiling. no mutex or waitgroup or atomics
fn asyncCompile(allocator: std.mem.Allocator, game_state: *anyopaque, compiling_flag: *bool) !void {
    while (true) {
        if (compiling_flag.*) {
            std.debug.print("Compiling......\n", .{});

            defer compiling_flag.* = false;
            recompileGameDll(allocator) catch {
                @panic("Failing compiling async game.dll");
            };
            unloadGameDll() catch return error.asyncunloadgame;
            loadGameDll() catch @panic("Failed loading async");
            gameReload(game_state);
            std.debug.print("Finished compiling....\n", .{});
        }
    }
}
