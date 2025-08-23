const std = @import("std");
const builtin = @import("builtin");

const ecez = @import("ecez");
const rgui = @import("raygui");
const rl = @import("raylib");

const GameView = @import("GameView.zig");
const SceneEditor = @import("SceneEditor.zig");

const window_title = "dissonance";

const TestComponent = struct {
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

const A = struct {};

pub const components = .{
    SceneEditor.components.EditorInfo,
    TestComponent,
    A,
};

pub const Storage = ecez.CreateStorage(components);

pub fn main() anyerror!void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    var storage = try Storage.init(allocator);

    // Get a random screen res for testing
    const screen_dim = screen_dim_blk: {
        const screen_dims = [_][2]i32{
            .{ 800, 450 },
            .{ 1280, 720 },
            .{ 1400, 1000 },
            .{ 1920, 1080 },
            .{ 2560, 1420 },
        };
        var xoshiro = std.Random.Xoshiro256.init(@intCast(std.time.milliTimestamp()));
        const screen_index = std.Random.intRangeLessThan(xoshiro.random(), u8, 0, screen_dims.len);

        break :screen_dim_blk screen_dims[screen_index];
    };

    const log_level: rl.TraceLogLevel = if (builtin.mode == .Debug) .warning else .err;
    rl.setTraceLogLevel(log_level);

    rl.initWindow(screen_dim[0], screen_dim[1], window_title);
    defer rl.closeWindow(); // Close window and OpenGL context

    // rl.setExitKey(.null); // Dont want accidental quitting app while editing!
    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    var scene_editor: SceneEditor = .init;
    defer scene_editor.deinit(allocator);

    var game_view = try GameView.init();
    defer game_view.deinit();

    _ = try storage.createEntity(.{
        SceneEditor.components.EditorInfo.init("test"),
        TestComponent{},
    });

    for (0..1) |index| {
        var name_buf: ["testXXXXXX".len]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "test{d}", .{index});
        _ = try storage.createEntity(.{SceneEditor.components.EditorInfo.init(name)});
    }

    // Main game loop
    var request_close: bool = false;
    while (!rl.windowShouldClose() and !request_close) { // Detect window close button or ESC key
        rl.beginDrawing();
        defer rl.endDrawing();

        const current_game_view = try scene_editor.draw(allocator, Storage, &storage, &request_close);
        try game_view.rescaleGameView(current_game_view);

        // Start drawing game
        {
            game_view.beginRendering();
            defer game_view.endRendering();

            // !!Game graphics here!!
            rl.drawText("game view", 0, 0, 20, .light_gray);
        }

        game_view.present(rl.Rectangle{
            .x = @floatFromInt(current_game_view[0]),
            .y = @floatFromInt(current_game_view[1]),
            .width = @floatFromInt(current_game_view[2]),
            .height = @floatFromInt(current_game_view[3]),
        });
    }
}
