const std = @import("std");

const ecez = @import("ecez");
const rgui = @import("raygui");
const rl = @import("raylib");

pub const components = @import("scene_editor/components.zig");
const EntityInspector = @import("scene_editor/EntityInspector.zig");
const EntityList = @import("scene_editor/EntityList.zig");
const layout_config = @import("scene_editor/layout_config.zig");
const Toolbar = @import("scene_editor/Toolbar.zig");

const SceneEditor = @This();

pub const init = SceneEditor{
    .toolbar = .init,
    .entity_list = .init,
    .entity_inspector = .init,
    .selected_entity = null,
};

toolbar: Toolbar,
entity_list: EntityList,
entity_inspector: EntityInspector,
selected_entity: ?ecez.Entity,

pub fn draw(
    scene_editor: *SceneEditor,
    allocator: std.mem.Allocator,
    comptime Storage: type,
    storage: *Storage,
    request_close: *bool,
) ![4]u32 {
    const style = rgui.getStyle(.default, .{ .default = .background_color });
    rl.clearBackground(rl.getColor(style));

    if (scene_editor.toolbar.panel_open != .none) {
        rgui.lock();
    }

    // Draw entity list
    if (scene_editor.toolbar.render_entity_list) {
        try scene_editor.entity_list.draw(
            allocator,
            Storage,
            storage,
            &scene_editor.selected_entity,
        );
    }

    // Draw entity inspector
    if (scene_editor.toolbar.render_entity_inspector) {
        try scene_editor.entity_inspector.draw(
            Storage,
            storage,
            &scene_editor.selected_entity,
        );
    }

    if (scene_editor.toolbar.panel_open != .none) {
        rgui.unlock();
    }

    // Draw toolbar
    try scene_editor.toolbar.draw(allocator, Storage, storage, request_close);

    // Draw asset view
    // TODO (show 3D models, audio ...)

    const r_width: u32 = @intCast(rl.getRenderWidth());
    const r_height: u32 = @intCast(rl.getRenderHeight());

    const x: u32 = if (scene_editor.toolbar.render_entity_list) layout_config.EntityList.width else 0;
    const y: u32 = layout_config.Toolbar.height;

    const width_offset: u32 = if (scene_editor.toolbar.render_entity_inspector) layout_config.EntityInspector.width else 0;
    const width: u32 = r_width - (x + width_offset);
    const height: u32 = r_height - y;
    // TODO: proper type
    return [4]u32{
        x,
        y,
        width,
        height,
    };
}

pub fn panelDraw(scene_editor: *SceneEditor, allocator: std.mem.Allocator, comptime Storage: type, storage: *Storage) !void {
    try scene_editor.toolbar.panelDraw(allocator, Storage, storage);
}

pub fn isGamePaused(scene_editor: SceneEditor) bool {
    return scene_editor.toolbar.game_loop_state != .play;
}

pub fn deinit(scene_editor: *SceneEditor, allocator: std.mem.Allocator) void {
    scene_editor.entity_list.deinit(allocator);
    scene_editor.toolbar.deinit(allocator);
}
