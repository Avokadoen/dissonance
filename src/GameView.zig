const std = @import("std");

const rgui = @import("raygui");
const rl = @import("raylib");

const GameView = @This();

render: rl.RenderTexture,

pub fn init() !GameView {
    const r_width = rl.getRenderWidth();
    const r_height = rl.getRenderHeight();
    const render = try rl.loadRenderTexture(r_width, r_height);
    errdefer rl.unloadRenderTexture(render);

    return GameView{
        .render = render,
    };
}

pub fn deinit(game_view: GameView) void {
    rl.unloadRenderTexture(game_view.render);
}

pub fn rescaleGameView(game_view: *GameView, current_view: [4]u32) !void {
    if (game_view.render.texture.width == current_view[2] and game_view.render.texture.height == current_view[3]) {
        return;
    }

    rl.unloadRenderTexture(game_view.render);
    game_view.render = try rl.loadRenderTexture(@intCast(current_view[2]), @intCast(current_view[3]));
}

pub fn beginRendering(game_view: *GameView) void {
    rl.beginTextureMode(game_view.render);

    // TODO: not needed when rendering fully
    const background_color_value = rgui.getStyle(.default, .{ .default = .background_color });
    const background_color = rl.getColor(@intCast(background_color_value));
    rl.clearBackground(background_color);
}

pub fn endRendering(game_view: *GameView) void {
    _ = game_view;
    rl.endTextureMode();
}

pub fn present(game_view: *GameView, current_view: rl.Rectangle) void {
    rl.drawTextureRec(
        game_view.render.texture,
        rl.Rectangle{
            .x = 0,
            .y = 0,
            .width = current_view.width,
            // NOTE: Render texture must be y-flipped due to default OpenGL coordinates (left-bottom)
            .height = -current_view.height,
        },
        rl.Vector2{
            .x = current_view.x,
            .y = current_view.y,
        },
        rl.Color.white,
    );
}
