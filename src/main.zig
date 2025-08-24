const std = @import("std");
const builtin = @import("builtin");

const ecez = @import("ecez");
const rgui = @import("raygui");
const rl = @import("raylib");
const tracy = @import("ztracy");

const Box2DRT = @import("Box2DRT.zig");
const GameView = @import("GameView.zig");
const SceneEditor = @import("SceneEditor.zig");
const dark_style = @import("styling/dark.zig");

const window_title = "dissonance";

pub const TestComponent = struct {
    cocky_want_boing_boing: bool = true,
    killy_count: u32 = 69,
    cool_factor: f64 = 100,
    friends: [3]u32 = [_]u32{ 2, 3, 4 },
    floaty_friends: [2]f16 = [_]f16{ 4.3, 3.2 },
    rect_dis_nuts: rl.Rectangle = .{
        .x = 22,
        .y = 33,
        .height = 2,
        .width = 1,
    },
    person: enum { alpha, beta, cuck } = .cuck,
    mood: enum { happy, sad } = .happy,
};

pub const A = struct {};

pub const Spinny = struct {
    ring_offset: f64 = 0,
    radius: f32 = 100,
};

pub const Position = struct {
    value: rl.Vector2,
};

pub const components = .{
    SceneEditor.components.EntityInfo,
    TestComponent,
    A,
    Spinny,
    Position,
    Box2DRT.components.BoxCollider,
    Box2DRT.components.Position,
    Box2DRT.components.Rotation,
    Box2DRT.components.DynamicTag,
    Box2DRT.components.StaticTag,
};

pub const UpdateEventArgument = struct {
    total_time: f64,
    delta_time: f32,
    frame_dim: rl.Vector2,
    box2d_rt: Box2DRT,
};

pub const systems = struct {
    const UpdateSpinnyQuery = ecez.Query(
        struct {
            pos: *Position,
            spinny: *const Spinny,
        },
        .{},
        .{},
    );
    pub fn updateSpinny(spinny_query: *UpdateSpinnyQuery, event_arg: UpdateEventArgument) void {
        while (spinny_query.next()) |spin| {
            const circle_x: f32 = @floatCast(std.math.sin(event_arg.total_time + spin.spinny.ring_offset));
            const cicler_y: f32 = @floatCast(std.math.cos(event_arg.total_time + spin.spinny.ring_offset));

            spin.pos.value = rl.Vector2{
                .x = circle_x * spin.spinny.radius + (event_arg.frame_dim.x * 0.5 - 100),
                .y = cicler_y * spin.spinny.radius + (event_arg.frame_dim.y * 0.5 - 100),
            };
        }
    }
};

pub const Storage = ecez.CreateStorage(components);

pub const Box2DSystems = Box2DRT.CreateSystems(Storage);

pub const Scheduler = ecez.CreateScheduler(.{
    ecez.Event(
        "update",
        .{
            Box2DSystems.doBox2DStep,
            Box2DSystems.propagateBox2DPosition,
            Box2DSystems.propagateBox2DRotation,
            systems.updateSpinny,
        },
        .{},
    ),
});

pub fn main() anyerror!void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var box2d_rt = Box2DRT.init(.{});
    defer box2d_rt.deinit();

    var storage = try Storage.init(allocator);
    defer storage.deinit();

    var scheduler = try Scheduler.init(.{
        .pool_allocator = allocator,
        .query_submit_allocator = allocator,
        .thread_count = null,
    });
    defer scheduler.deinit();

    // Get a random screen res for testing
    const screen_dim = [2]i32{ 1280, 720 };

    const log_level: rl.TraceLogLevel = if (builtin.mode == .Debug) .warning else .err;
    rl.setTraceLogLevel(log_level);

    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(
        screen_dim[0],
        screen_dim[1],
        window_title,
    );
    defer rl.closeWindow(); // Close window and OpenGL context

    // HACK: seems there is a bug in raylib with initalizaing the window.
    // Rendering and events are not synced on where things are place. By resizing
    // the windows AFTER init it seems to work fine however.
    rl.setWindowState(.{ .window_maximized = true });

    // rl.setExitKey(.null); // Dont want accidental quitting app while editing!
    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    try dark_style.loadStyleDark();

    var scene_editor: SceneEditor = .init;
    defer scene_editor.deinit(allocator);

    var game_view = try GameView.init();
    defer game_view.deinit();

    // Main game loop

    var total_time: f64 = 0;
    var request_close: bool = false;

    var current_game_view = [4]u32{
        0,
        0,
        @intCast(rl.getRenderWidth()),
        @intCast(rl.getRenderHeight()),
    };
    while (!rl.windowShouldClose() and !request_close) { // Detect window close button or ESC key
        tracy.FrameMark();

        const delta_time = rl.getFrameTime();

        if (scene_editor.isGamePaused() == false) {
            const game_update_zone = tracy.ZoneN(@src(), "game_update");
            defer game_update_zone.End();

            total_time += delta_time;

            try scheduler.dispatchEvent(&storage, .update, UpdateEventArgument{
                .delta_time = delta_time,
                .total_time = total_time,
                .frame_dim = rl.Vector2{
                    .x = @floatFromInt(current_game_view[2]),
                    .y = @floatFromInt(current_game_view[3]),
                },
                .box2d_rt = box2d_rt,
            });
            scheduler.waitEvent(.update);
        }

        // Start drawing game
        {
            const game_update_zone = tracy.ZoneN(@src(), "game_draw");
            defer game_update_zone.End();

            game_view.beginRendering();
            defer game_view.endRendering();

            // !!Game graphics here!!
            const SpinnyDrawQuery = ecez.Query(
                struct {
                    pos: Position,
                },
                .{Spinny},
                .{},
            );
            var spinny_iter = try SpinnyDrawQuery.submit(allocator, &storage);
            defer spinny_iter.deinit(allocator);
            while (spinny_iter.next()) |spinny| {
                rl.drawText(
                    "game view",
                    @intFromFloat(spinny.pos.value.x),
                    @intFromFloat(spinny.pos.value.y),
                    20,
                    .light_gray,
                );
            }
        }

        game_view.present(rl.Rectangle{
            .x = @floatFromInt(current_game_view[0]),
            .y = @floatFromInt(current_game_view[1]),
            .width = @floatFromInt(current_game_view[2]),
            .height = @floatFromInt(current_game_view[3]),
        });

        rl.beginDrawing();
        defer rl.endDrawing();

        current_game_view = try scene_editor.draw(
            allocator,
            Storage,
            &storage,
            box2d_rt,
            &request_close,
        );
        try game_view.rescaleGameView(current_game_view);

        try scene_editor.panelDraw(allocator, Storage, &storage);
    }
}

/// Can be used to update a ezby file to understand the new component layout
/// We need to maintain both the old and new component layout for the transition however
pub fn migrateEzby(
    comptime ComponentA: type,
    comptime ComponentB: type,
    storage: *Storage,
    allocator: std.mem.Allocator,
    comptime convert_a_to_b_fn: fn (a: ComponentA) ComponentB,
) !void {
    const ComponentAQuery = ecez.Query(struct {
        handle: ecez.Entity,
        a: ComponentA,
    }, .{}, .{});
    var a_iter = try ComponentAQuery.submit(allocator, storage);
    while (a_iter.next()) |entity_a| {
        const b = convert_a_to_b_fn(entity_a.a);
        storage.setComponenty(entity_a.handle, b);
    }
}
