const std = @import("std");
const math = std.math;
const assert = std.debug.assert;

const RingBuffer = @import("ring_buffer.zig").RingBuffer;
const PriorityQueue = @import("priority_queue.zig").PriorityQueue;
// switch formatter on /off by changing the the value of the next line
// zig fmt: off
const c = @cImport({
    @cInclude("raylib.h");
    @cInclude("raygui.h");
    @cInclude("raymath.h");
    @cInclude("rlgl.h");
});
// const c = @import("raylib");
// zig fmt: on
const GameState = struct {
    debug: bool = true,
    allocator: std.mem.Allocator,
    camera: c.Camera2D,
    time: f32 = 0,
    animation_time: f32 = 0,
    last_click: ?c.Vector2,

    root_pos: c.Vector2,
    last_value: u8 = 1,
    nodes: std.ArrayList(Node),
    tree: PriorityQueue(u8),
    arrows: std.ArrayList([2]c.Vector2),
    animations: RingBuffer(MotionQueue),
    animation: ?Animation = null,
};
fn addSwapAnimation(animations: *RingBuffer(MotionQueue), n1: usize, n2: usize) void {
    animations.append(MotionQueue{ .swap_node = [2]NodeIndex{ n1, n2 } }) catch return;
}
const Node = struct {
    pos: c.Vector2,
    value: u8,
    r: f32, // radius
};
const NodeIndex = usize;
const Animation = struct {
    duration: f32 = 0,
    motion: Motion,
};
pub const MotionType = enum {
    straight_node,
    swap_node,
    create_node,
    stretch_arrow,
};
const Motion = union(MotionType) {
    straight_node: AnimationStraightLine,
    swap_node: [2]AnimationStraightLine,
    create_node: AnimationInflate,
    stretch_arrow: AnimationStrech,
};
pub const MotionQueue = union(MotionType) {
    straight_node: struct { n: NodeIndex, end: c.Vector2 },
    swap_node: [2]NodeIndex,
    create_node: NodeIndex,
    stretch_arrow: struct { start_node: NodeIndex, end_node: NodeIndex, arrow_index: usize },
};
const AnimationStraightLine = struct {
    start: c.Vector2,
    end: c.Vector2,
    node_index: NodeIndex = 0,
};
const AnimationInflate = struct {
    node_index: NodeIndex = 0,
    r: f32,
};
const AnimationStrech = struct {
    arrow_index: usize = 0,
    end: c.Vector2,
};
const left_arrow_direction: c.Vector2 = c.Vector2{ .x = -50, .y = 50 };
const right_arrow_direction: c.Vector2 = c.Vector2{ .x = 50, .y = 50 };
const screen_w = 1000;
const screen_h = 600;
var rand: std.Random = undefined;

fn lessThanFn(lhs: u8, rhs: u8) bool {
    return lhs < rhs;
}

export fn gameInit() *anyopaque {
    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = @intCast(std.time.timestamp());
        std.posix.getrandom(std.mem.asBytes(&seed)) catch unreachable;
        break :blk seed;
    });
    rand = prng.random();
    const allocator = std.heap.c_allocator;
    const game_state = allocator.create(GameState) catch @panic("Out of memory.");
    game_state.* = GameState{
        .allocator = allocator,
        .camera = .{ .zoom = 1 },
        .last_click = null,
        .root_pos = c.Vector2{ .x = 0, .y = 0 },
        .nodes = std.ArrayList(Node).init(allocator),
        .arrows = std.ArrayList([2]c.Vector2).init(allocator),
        .tree = undefined,
        .animations = RingBuffer(MotionQueue).init(allocator, 64) catch {
            return game_state;
        },
    };
    // TODO(Salim): extract the addSwapAnimation into a callback struct
    game_state.tree = PriorityQueue(u8).init(allocator, lessThanFn, &game_state.animations, addSwapAnimation);

    return game_state;
}
export fn gameDraw(game_state_ptr: *anyopaque) void {
    const game_state: *GameState = @ptrCast(@alignCast(game_state_ptr));

    c.ClearBackground(c.DARKBLUE);
    c.BeginMode2D(game_state.camera);
    defer c.EndMode2D();
    {
        c.rlPushMatrix();
        defer c.rlPopMatrix();
        c.rlTranslatef(screen_w / 2, screen_h / 2, 0);
        // TODO(Salim): modify state of nodes so the draw can be more dynamic to make room on each level for new nodes
        drawTree(game_state);
    }
    // debugging //////////////////////////////////////////////////////////////
    // Create zero terminated string with the time and radius.
    drawDebuggingInfo(game_state);
}
fn handleAddBall(game_state: *GameState) error{ OutOfMemory, Full }!void {
    if (0 != c.GuiButton(c.Rectangle{ .x = 100, .y = 50, .width = 135, .height = 40 }, "Add Node")) {
        const new_index = game_state.nodes.items.len;
        // const new_value = rand.intRangeAtMost(u8, 0, game_state.last_value + 1);
        // std.debug.print("new value {}\n", .{new_value});

        const new_value: u8 = @intCast((@as(u64, game_state.last_value) * 35 + 1) % 37);
        defer game_state.last_value += 1;
        // r will be animated
        const new_node = Node{ .value = new_value, .r = 0, .pos = getNodePos(game_state, new_index) };
        game_state.nodes.append(new_node) catch |err| {
            std.debug.print("couldn't append new node, got error {}\n", .{err});
            return err;
        };
        errdefer _ = game_state.nodes.pop();

        game_state.animations.append(MotionQueue{ .create_node = new_index }) catch |err| {
            std.debug.print("couldn't append to animations, got error {}\n", .{err});
            return err;
        };

        errdefer _ = game_state.animations.popOrNull();
        if (new_index > 0) {
            const parent_index = (new_index - 1) / 2;
            var arrow = calcArrow(game_state.nodes.items[parent_index], new_node);
            const arrow_index = game_state.arrows.items.len;
            arrow[1] = arrow[0];
            game_state.arrows.append(arrow) catch |err| {
                std.debug.print("couldn't append new arrow, got error {}\n", .{err});
                return err;
            };
            errdefer _ = game_state.arrows.pop();
            game_state.animations.append(MotionQueue{ .stretch_arrow = .{
                .start_node = parent_index,
                .end_node = new_index,
                .arrow_index = arrow_index,
            } }) catch |err| {
                std.debug.print("couldn't make arrow animation, got error {}\n", .{err});
                return err;
            };
            errdefer _ = game_state.animations.popOrNull();
        }
        game_state.tree.insert(new_value) catch |err| {
            std.debug.print("couldn't append to tree, got error {}\n", .{err});
            return err;
        };
    }
}
export fn gameTick(game_state_ptr: *anyopaque) void {
    var game_state: *GameState = @ptrCast(@alignCast(game_state_ptr));
    game_state.time += c.GetFrameTime();
    if (c.IsKeyPressed(c.KEY_F6)) {
        game_state.debug = !game_state.debug;
    }
    if (c.IsKeyPressed(c.KEY_F1)) {
        game_state.animations.append(MotionQueue{ .swap_node = [2]NodeIndex{ 0, 1 } }) catch {
            std.debug.print("couldn't append swap animation\n", .{});
        };
        std.debug.print("appended swap animation\n", .{});
    }
    handleAddBall(game_state) catch return;

    // scroll window
    var camera = &game_state.camera;
    if (c.IsMouseButtonDown(c.MOUSE_BUTTON_LEFT)) {
        var delta = c.GetMouseDelta();
        delta = c.Vector2Scale(delta, -1 / camera.zoom);
        camera.target = c.Vector2Add(camera.target, delta);
        game_state.last_click = c.GetScreenToWorld2D(c.GetMousePosition(), camera.*);
    }
    // pull out animations
    if (game_state.animation) |animation| {
        game_state.animation_time += c.GetFrameTime();
        switch (animation.motion) {
            Motion.straight_node => |anim| {
                const pos = c.Vector2Lerp(anim.start, anim.end, game_state.animation_time / animation.duration);
                game_state.nodes.items[anim.node_index].pos = pos;
            },
            Motion.swap_node => |anim| {
                for (0..2) |i| {
                    const pos = c.Vector2Lerp(anim[i].start, anim[i].end, game_state.animation_time / animation.duration);
                    game_state.nodes.items[anim[i].node_index].pos = pos;
                }
            },
            Motion.create_node => |anim| {
                const r_new = anim.r * (game_state.animation_time / animation.duration);
                game_state.nodes.items[anim.node_index].r = r_new;
            },
            Motion.stretch_arrow => |anim| {
                const arrow: *[2]c.Vector2 = &game_state.arrows.items[anim.arrow_index];
                const tip_new = c.Vector2Lerp(arrow[0], anim.end, game_state.animation_time / animation.duration);
                arrow[1] = tip_new;
            },
        }
        if (game_state.animation_time > animation.duration) {
            game_state.animation_time = 0;
            switch (animation.motion) {
                Motion.swap_node => |anim| {
                    const j1 = anim[0].node_index;
                    const j2 = anim[1].node_index;
                    const tmp = game_state.nodes.items[j1];
                    game_state.nodes.items[j1] = game_state.nodes.items[j2];
                    game_state.nodes.items[j2] = tmp;
                },
                else => {},
            }
            game_state.animation = null;
        }
    }
    if (game_state.animation == null) {
        if (game_state.animations.popOrNull()) |motion| {
            game_state.animation = createAnimation(game_state, motion);
        }
    }
}
/// assumes the size is less than usize
fn getNodePos(game_state: *GameState, new_index: NodeIndex) c.Vector2 {
    // compute depth of new_index
    // sum of powers of two are the indices of the left most node in each level
    var depth: usize = 0;
    var sum_powers_two: usize = 0;
    var powers_two: usize = 1;
    while (sum_powers_two + powers_two <= new_index) {
        sum_powers_two += powers_two;
        powers_two *= 2;
        depth += 1;
    }
    const offset: usize = new_index - sum_powers_two;
    const horizontal_direction = c.Vector2Subtract(right_arrow_direction, left_arrow_direction);

    const left_component = c.Vector2Scale(left_arrow_direction, @floatFromInt(depth));
    const horizontal_component = c.Vector2Scale(horizontal_direction, @floatFromInt(offset));

    const vec = c.Vector2Add(left_component, horizontal_component);
    const pos = c.Vector2Add(vec, game_state.root_pos);
    return pos;
}
fn calcArrow(src: Node, dst: Node) [2]c.Vector2 {
    const distance: f32 = c.Vector2Distance(src.pos, dst.pos);
    // assert(src.r != 0 and dst.r != 0);
    assert(distance > src.r + dst.r);

    const start_pos_lerp: f32 = src.r / distance;
    const start_pos = c.Vector2Lerp(src.pos, dst.pos, start_pos_lerp);
    const end_pos_lerp: f32 = dst.r / distance;
    const end_pos = c.Vector2Lerp(dst.pos, src.pos, end_pos_lerp);

    return [2]c.Vector2{ start_pos, end_pos };
}

fn drawConnection(src: c.Vector2, dst: c.Vector2) void {
    // const distance: f32 = c.Vector2Distance(src, dst.pos);
    // assert(src.r != 0 and dst.r != 0);
    // assert(distance > src.r + dst.r);

    // const start_pos_lerp: f32 = src.r / distance;
    // const start_pos = c.Vector2Lerp(src.pos, dst.pos, start_pos_lerp);
    // const end_pos_lerp: f32 = dst.r / distance;
    // const end_pos = c.Vector2Lerp(dst.pos, src.pos, end_pos_lerp);
    const start_pos = src;
    const end_pos = dst;
    const triangle_base_point = c.Vector2Lerp(end_pos, start_pos, 0.2);
    const diff = c.Vector2Scale(c.Vector2Subtract(end_pos, triangle_base_point), 0.5);
    const perpendicular = c.Vector2{ .x = -diff.y, .y = diff.x };

    const triangle_p1 = c.Vector2Add(triangle_base_point, perpendicular);
    const triangle_p2 = c.Vector2Subtract(triangle_base_point, perpendicular);

    c.DrawLineV(start_pos, end_pos, c.BLACK);
    c.DrawTriangle(end_pos, triangle_p2, triangle_p1, c.BLACK);
}

fn drawTree(game_state: *GameState) void {
    var buff: [2:0]u8 = undefined;
    buff[2] = 0;
    for (game_state.nodes.items) |n| {
        c.DrawCircleV(n.pos, n.r, c.RED);
        buff[0] = @as(u8, @intCast(@divFloor(n.value, 10))) + '0';
        buff[1] = @as(u8, @intCast(n.value % 10)) + '0';
        c.DrawText(buff[0..], @as(c_int, @intFromFloat(n.pos.x)) - 10, @as(c_int, @intFromFloat(n.pos.y)) - 10, 20, c.GREEN);
    }
    for (game_state.arrows.items) |arrow| {
        drawConnection(arrow[0], arrow[1]);
    }
}

fn drawDebuggingInfo(game_state: *GameState) void {
    {
        var buf: [256]u8 = undefined;
        const slice = std.fmt.bufPrintZ(
            &buf,
            "FPS: {d}",
            .{c.GetFPS()},
        ) catch "error";
        {
            c.rlPushMatrix();
            defer c.rlPopMatrix();
            const top_left_pos = c.GetScreenToWorld2D(.{ .x = 0, .y = 0 }, game_state.camera);
            c.rlTranslatef(top_left_pos.x, top_left_pos.y, 0);
            c.DrawText(slice, 10, 10, 20, c.LIME);
        }
    }
    if (game_state.debug) {
        var buf: [500]u8 = undefined;
        const mouse_world_pos = c.GetScreenToWorld2D(c.GetMousePosition(), game_state.camera);
        const x_pos: c_int = @intFromFloat(mouse_world_pos.x);
        const y_pos: c_int = @intFromFloat(mouse_world_pos.y);
        const slice = std.fmt.bufPrintZ(&buf, "x:{}, y:{}", .{ x_pos, y_pos }) catch "error";
        {
            c.rlPushMatrix();
            defer c.rlPopMatrix();
            const bottom_left_pos = c.GetScreenToWorld2D(.{ .x = 0, .y = screen_h }, game_state.camera);
            c.rlTranslatef(bottom_left_pos.x, bottom_left_pos.y, 0);
            c.DrawText(slice, 10, -45, 30, c.GREEN);
        }
    }
}

fn animateMoveNode(game_state: *GameState, node_index: usize, duration: f32, final_pos: c.Vector2) Animation {
    return Animation{ .duration = duration, .motion = Motion{ .straight_node = .{
        .start = game_state.nodes.items[node_index].pos,
        .end = final_pos,
        .node_index = node_index,
    } } };
}
fn animateSwapNodes(game_state: *GameState, node1_index: usize, node2_index: usize, duration: f32) Animation {
    const n1 = game_state.nodes.items[node1_index].pos;
    const n2 = game_state.nodes.items[node2_index].pos;
    return Animation{ .duration = duration, .motion = Motion{
        .swap_node = [2]AnimationStraightLine{
            .{ .start = n1, .end = n2, .node_index = node1_index },
            .{ .start = n2, .end = n1, .node_index = node2_index },
        },
    } };
}
fn createAnimation(game_state: *GameState, motion: MotionQueue) Animation {
    switch (motion) {
        MotionType.swap_node => |nodes| {
            return animateSwapNodes(game_state, nodes[0], nodes[1], 1);
        },
        MotionType.straight_node => |value| {
            return animateMoveNode(game_state, value.n, 1, value.end);
        },
        MotionType.create_node => |value| {
            return Animation{ .duration = 1, .motion = Motion{ .create_node = AnimationInflate{ .node_index = value, .r = 10 } } };
        },
        MotionType.stretch_arrow => |value| {
            return Animation{ .duration = 1, .motion = Motion{ .stretch_arrow = AnimationStrech{
                .arrow_index = value.arrow_index,
                .end = calcArrow(game_state.nodes.items[value.start_node], game_state.nodes.items[value.end_node])[1],
            } } };
        },
    }
}
// OLD code for learning //////////////////////////////////////////////////////
fn drawGrid(slices: u16, spacing: u16) void {
    c.rlBegin(c.RL_LINES);
    defer c.rlEnd();
    var i: u8 = 0;

    c.rlColor3f(0.5, 0.5, 0.5);
    while (i <= slices) : (i += 1) {
        // rlVertex2i for int x y
        //             rlVertex3f((float)i*spacing, 0.0f, (float)-halfSlices*spacing);
        //             rlVertex3f((float)i*spacing, 0.0f, (float)halfSlices*spacing);

        //             rlVertex3f((float)-halfSlices*spacing, 0.0f, (float)i*spacing);
        //             rlVertex3f((float)halfSlices*spacing, 0.0f, (float)i*spacing);
        c.rlVertex2i(@as(c_int, @intCast(i * spacing)), 0);
        c.rlVertex2i(@as(c_int, @intCast(i * spacing)), @as(c_int, @intCast(slices * spacing)));

        c.rlVertex2i(0, @as(c_int, @intCast(i * spacing)));
        c.rlVertex2i(@as(c_int, @intCast(slices * spacing)), @as(c_int, @intCast(i * spacing)));
    }
}

export fn gameReload(game_state_ptr: *anyopaque) void {
    var game_state: *GameState = @ptrCast(@alignCast(game_state_ptr));
    game_state.time = 179;
}

export fn gameUnload(game_state_ptr: *anyopaque) void {
    // TODO(Salim): Consider deallocating game state and creating a new one to handle issue when structure format changes
    _ = game_state_ptr;
}
