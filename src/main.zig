const std = @import("std");
const builtin = @import("builtin");

const ecez = @import("ecez");
const rgui = @import("raygui");
const rl = @import("raylib");
const ztracy = @import("ztracy");

const Box2DRT = @import("Box2DRT.zig");
const GameView = @import("GameView.zig");
const SceneEditor = @import("SceneEditor.zig");
const dark_style = @import("styling/dark.zig");
const UpdateEventArgument = @import("common.zig").UpdateEventArgument;

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

pub const components = .{
    SceneEditor.components.EntityInfo,
    TestComponent,
    Box2DRT.components.BoxCollider,
    Box2DRT.components.Position,
    Box2DRT.components.Rotation,
    Box2DRT.components.DynamicTag,
    Box2DRT.components.StaticTag,
};

pub const systems = struct {};

pub const Storage = ecez.CreateStorage(components);

pub const Scheduler = ecez.CreateScheduler(.{
    ecez.Event(
        "update",
        .{
            Box2DRT.systems.doBox2DStep,
            Box2DRT.systems.propagateBox2DPosition,
            Box2DRT.systems.propagateBox2DRotation,
        },
        .{},
    ),
    ecez.Event(
        "draw",
        .{
            coliderDraw,
        },
        .{
            .run_on_main_thread = true,
        },
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

    rl.setExitKey(.null); // Dont want accidental quitting app while editing!
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

    var player_position: rl.Vector2 = .{ .x = screen_dim[0] / 2, .y = screen_dim[0] / 2 };

    while (!rl.windowShouldClose() and !request_close) { // Detect window close button or ESC key
        ztracy.FrameMark();

        const delta_time = rl.getFrameTime();
        player_position = playerMovement(player_position);
        if (scene_editor.isGamePaused() == false) {
            const game_update_zone = ztracy.ZoneN(@src(), "game_update");
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
            const game_update_zone = ztracy.ZoneN(@src(), "game_draw");
            defer game_update_zone.End();

            game_view.beginRendering();
            defer game_view.endRendering();

            // !!Game graphics here!!
            try scheduler.dispatchEvent(&storage, .draw, .{});
        }

        game_view.present(rl.Rectangle{
            .x = @floatFromInt(current_game_view[0]),
            .y = @floatFromInt(current_game_view[1]),
            .width = @floatFromInt(current_game_view[2]),
            .height = @floatFromInt(current_game_view[3]),
        });

        rl.drawCircleV(player_position, 20, .gold);

        rl.beginDrawing();
        defer rl.endDrawing();

        current_game_view = try scene_editor.draw(
            allocator,
            Storage,
            &storage,
            &box2d_rt,
            &request_close,
        );
        try game_view.rescaleGameView(current_game_view);

        try scene_editor.panelDraw(allocator, Storage, &storage, &box2d_rt);
    }
}

pub const ColliderDrawQuery = ecez.Query(
    struct {
        rotation: *const Box2DRT.components.Rotation,
        box: *const Box2DRT.components.BoxCollider,
        position: *const Box2DRT.components.Position,
    },
    .{},
    .{},
);
pub fn coliderDraw(collider_query: *ColliderDrawQuery) void {
    const zone = ztracy.ZoneN(@src(), @src().fn_name);
    defer zone.End();

    while (collider_query.next()) |entity| {
        const rectangle = rl.Rectangle{
            .x = entity.position.value.x,
            .y = entity.position.value.y,
            .width = entity.box.extent.x,
            .height = entity.box.extent.y,
        };
        rl.drawRectanglePro(
            rectangle,
            .zero(),
            entity.rotation.degrees,
            .{ .r = 255, .g = 0, .b = 0, .a = 150 },
        );
    }
}

pub fn playerMovement(player_pos: rl.Vector2) rl.Vector2 {
    var x = player_pos.x;
    var y = player_pos.y;

    if (rl.isKeyDown(.right)) {
        x += 3;
    }
    if (rl.isKeyDown(.left)) {
        x -= 3;
    }
    if (rl.isKeyDown(.up)) {
        y -= 3;
    }
    if (rl.isKeyDown(.down)) {
        y += 3;
    }
    return rl.Vector2{ .x = x, .y = y };
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
