const std = @import("std");

const ecez = @import("ecez");
const DrawError = ecez.ezby.DeserializeError;
const rgui = @import("raygui");
const rl = @import("raylib");

const layout_config = @import("layout_config.zig");

const Toolbar = @This();

pub const init = Toolbar{
    .panel_str = undefined,
    .panel_open = .none,
    .load_op = .overwrite,
    .load_op_edit_mode = false,
    .render_entity_list = true,
    .render_entity_inspector = true,
    .game_loop_state = .stop,
    .game_loop_ezby_bytes = null,
};

pub const GameloopState = enum {
    stop,
    play,
    pause,
};

const Panel = enum {
    none,
    save,
    load,
};

panel_str: [128]u8,
panel_open: Panel,
load_op: ecez.ezby.DeserializeOp,
load_op_edit_mode: bool,

render_entity_list: bool,
render_entity_inspector: bool,

game_loop_state: GameloopState,
game_loop_ezby_bytes: ?[]const u8,

pub fn deinit(toolbar: *Toolbar, allocator: std.mem.Allocator) void {
    if (toolbar.game_loop_ezby_bytes) |ezby_bytes| {
        allocator.free(ezby_bytes);
    }
}

pub fn draw(
    toolbar: *Toolbar,
    allocator: std.mem.Allocator,
    comptime Storage: type,
    storage: *Storage,
    request_close: *bool,
) !void {
    if (toolbar.panel_open != .none) {
        rgui.lock();
    }

    const r_width: f32 = @floatFromInt(rl.getRenderWidth());

    const panel_bounds = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = r_width,
        .height = layout_config.Toolbar.height,
    };
    _ = rgui.panel(panel_bounds, null);

    var button_bounds = rl.Rectangle{
        .x = layout_config.Toolbar.button_padding,
        .y = layout_config.Toolbar.button_padding,
        .width = layout_config.Toolbar.button_dim,
        .height = layout_config.Toolbar.button_dim,
    };

    rgui.enableTooltip();
    defer rgui.disableTooltip();

    rgui.setTooltip("Save scene to file");
    const save_scene = std.fmt.comptimePrint("#{d}#", .{@intFromEnum(layout_config.Toolbar.file_save_icon)});
    if (rgui.button(button_bounds, save_scene)) {
        toolbar.panel_str = [_]u8{0} ** toolbar.panel_str.len;
        toolbar.panel_open = .save;
    }
    button_bounds.x += layout_config.Toolbar.button_dim + layout_config.Toolbar.button_padding;

    rgui.setTooltip("Load scene from file");
    const load_scene = std.fmt.comptimePrint("#{d}#", .{@intFromEnum(layout_config.Toolbar.file_load_icon)});
    if (rgui.button(button_bounds, load_scene)) {
        toolbar.panel_str = [_]u8{0} ** toolbar.panel_str.len;
        toolbar.panel_open = .load;
        toolbar.load_op = .overwrite;
        toolbar.load_op_edit_mode = false;
    }

    button_bounds.x = (r_width * 0.5) - ((layout_config.Toolbar.button_dim + layout_config.Toolbar.button_padding) * 2);
    const play_pause_tooltip = if (toolbar.game_loop_state == .play) "Pause" else "Play";
    rgui.setTooltip(play_pause_tooltip);
    button_bounds.x += (layout_config.Toolbar.button_dim + layout_config.Toolbar.button_padding);

    const play = std.fmt.comptimePrint("#{d}#", .{@intFromEnum(rgui.IconName.player_play)});
    const pause = std.fmt.comptimePrint("#{d}#", .{@intFromEnum(rgui.IconName.player_pause)});
    const play_pause = if (toolbar.game_loop_state == .play) pause else play;
    if (rgui.button(button_bounds, play_pause)) {
        switch (toolbar.game_loop_state) {
            .play => toolbar.game_loop_state = .pause,
            .pause => toolbar.game_loop_state = .play,
            .stop => {
                std.debug.assert(toolbar.game_loop_ezby_bytes == null);
                toolbar.game_loop_ezby_bytes = try saveScene("play_backup.ezby", allocator, Storage, storage);

                toolbar.game_loop_state = .play;
            },
        }
    }

    rgui.setTooltip("Stop");
    button_bounds.x += layout_config.Toolbar.button_dim + layout_config.Toolbar.button_padding;
    const stop = std.fmt.comptimePrint("#{d}#", .{@intFromEnum(rgui.IconName.player_stop)});
    if (rgui.button(button_bounds, stop)) {
        switch (toolbar.game_loop_state) {
            .play, .pause => {
                // Load serialized storage state
                if (toolbar.game_loop_ezby_bytes) |ezby_bytes| {
                    try ecez.ezby.deserialize(Storage, .overwrite, storage, ezby_bytes);
                    toolbar.game_loop_ezby_bytes = null;
                    allocator.free(ezby_bytes);
                }

                toolbar.game_loop_state = .stop;
            },
            .stop => {},
        }
    }

    rgui.setTooltip("Close app");
    button_bounds.x = r_width - (layout_config.Toolbar.button_dim + layout_config.Toolbar.button_padding);
    const close_app = std.fmt.comptimePrint("#{d}#", .{@intFromEnum(rgui.IconName.cross)});
    if (rgui.button(button_bounds, close_app)) {
        // TODO: open popup to double check if this was desired?
        request_close.* = true;
    }

    rgui.setTooltip("Render entity inspector");
    button_bounds.x -= (layout_config.Toolbar.button_dim + layout_config.Toolbar.button_padding) * 4;
    const entity_inspector = std.fmt.comptimePrint("#{d}#", .{@intFromEnum(rgui.IconName.cube)});
    if (rgui.button(button_bounds, entity_inspector)) {
        toolbar.render_entity_inspector = !toolbar.render_entity_inspector;
    }

    rgui.setTooltip("Render entity list");
    button_bounds.x -= layout_config.Toolbar.button_dim + layout_config.Toolbar.button_padding;
    const entity_list = std.fmt.comptimePrint("#{d}#", .{@intFromEnum(rgui.IconName.box_grid)});
    if (rgui.button(button_bounds, entity_list)) {
        toolbar.render_entity_list = !toolbar.render_entity_list;
    }

    if (toolbar.panel_open != .none) {
        rgui.unlock();
    }
}

pub fn panelDraw(toolbar: *Toolbar, allocator: std.mem.Allocator, comptime Storage: type, storage: *Storage) !void {
    try switch (toolbar.panel_open) {
        .none => {},
        .save => saveOrLoadUi(.save, toolbar, allocator, Storage, storage),
        .load => saveOrLoadUi(.load, toolbar, allocator, Storage, storage),
    };
}

fn saveOrLoadUi(comptime op: enum { save, load }, toolbar: *Toolbar, allocator: std.mem.Allocator, comptime Storage: type, storage: *Storage) !void {
    const r_width: f32 = @floatFromInt(rl.getRenderWidth());
    const r_height: f32 = @floatFromInt(rl.getRenderHeight());

    const popup_panel_bounds = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = r_width,
        .height = r_height,
    };
    const message_panel = rl.Rectangle{
        .x = (popup_panel_bounds.width / 2) - (layout_config.Toolbar.popup_width / 2),
        .y = (popup_panel_bounds.height / 2) - (layout_config.Toolbar.popup_height / 2),
        .width = layout_config.Toolbar.popup_width,
        .height = layout_config.Toolbar.popup_height,
    };
    const header_height = 24;
    const message_panel_text = rl.Rectangle{
        .x = message_panel.x + layout_config.Toolbar.popup_text_padding,
        .y = message_panel.y + header_height + layout_config.Toolbar.popup_text_padding,
        .width = message_panel.width - layout_config.Toolbar.popup_text_padding * 2,
        .height = layout_config.input_field_height,
    };
    const message_panel_confirm_button = rl.Rectangle{
        .x = message_panel_text.x + message_panel_text.width - layout_config.Toolbar.button_dim,
        .y = message_panel_text.y + message_panel_text.height + layout_config.Toolbar.popup_text_padding,
        .width = layout_config.Toolbar.button_dim,
        .height = layout_config.Toolbar.button_dim,
    };

    rgui.setAlpha(layout_config.Toolbar.popup_alpha);
    _ = rgui.panel(popup_panel_bounds, null);
    rgui.setAlpha(1);

    const window_txt = if (op == .save) "Save scene" else "Load scene";
    const close_pressed = rgui.windowBox(message_panel, window_txt) == 1;
    if (close_pressed) {
        toolbar.panel_open = .none;
    }

    _ = rgui.textBox(message_panel_text, toolbar.panel_str[0 .. toolbar.panel_str.len - 1 :0], toolbar.panel_str.len, true);

    rgui.enableTooltip();
    defer rgui.disableTooltip();
    // Allow user to request append or overwrite of scene
    if (op == .load) {
        const load_op_field = rl.Rectangle{
            .x = message_panel_text.x,
            .y = message_panel_confirm_button.y,
            .width = message_panel_text.width - (message_panel_confirm_button.width + layout_config.Toolbar.button_padding),
            .height = layout_config.input_field_height,
        };

        var edit_mode_bound = load_op_field;
        edit_mode_bound.height *= if (toolbar.load_op_edit_mode) 3 else 1; // value field + option overwrite or append

        // If user is still hovering dropdown, all good
        toolbar.load_op_edit_mode = rl.checkCollisionPointRec(rl.getMousePosition(), edit_mode_bound);

        var tmp_value: i32 = @intFromEnum(toolbar.load_op);
        const mouse_pressed = rgui.dropdownBox(load_op_field, "overwrite;append", &tmp_value, toolbar.load_op_edit_mode) == 1;
        if (mouse_pressed) {
            toolbar.load_op = @enumFromInt(tmp_value);
        }
    }

    {
        const tooltip_str = if (op == .save) "Save scene to file" else "Load scene from file";
        rgui.setTooltip(tooltip_str);

        const button_txt = if (op == .save)
            std.fmt.comptimePrint("#{d}#", .{@intFromEnum(layout_config.Toolbar.file_save_icon)})
        else
            std.fmt.comptimePrint("#{d}#", .{@intFromEnum(layout_config.Toolbar.file_load_icon)});

        if (rgui.button(message_panel_confirm_button, button_txt)) {
            var zero_iter = std.mem.splitScalar(u8, &toolbar.panel_str, 0);
            const scene_name = zero_iter.first();

            // Currently you can call the file anything, but lets atleast avoid crashing by enforcing some length :)
            if (scene_name.len > "X.ezby".len) {
                toolbar.panel_open = .none;

                if (op == .save) {
                    const bytes = try saveScene(scene_name, allocator, Storage, storage);
                    allocator.free(bytes);
                } else {
                    loadScene(toolbar.load_op, scene_name, allocator, Storage, storage) catch |err| {
                        switch (err) {
                            // User most likely typed an invalid scene name
                            error.InvalidSceneName => toolbar.panel_open = .load,
                            else => return err,
                        }
                    };
                }
            }
        }
    }
}

fn saveScene(scene_name: []const u8, allocator: std.mem.Allocator, comptime Storage: type, storage: *Storage) ![]const u8 {
    const bytes = try ecez.ezby.serialize(allocator, Storage, storage.*, .{});

    const dir_path = try std.fs.selfExeDirPathAlloc(allocator);
    defer allocator.free(dir_path);

    var dir = try std.fs.openDirAbsolute(dir_path, .{ .access_sub_paths = true });
    defer dir.close();

    var scenes_dir = try dir.makeOpenPath("scenes", .{ .access_sub_paths = true });
    defer scenes_dir.close();

    try scenes_dir.writeFile(.{ .sub_path = scene_name, .data = bytes });

    return bytes;
}

fn loadScene(op: ecez.ezby.DeserializeOp, scene_name: []const u8, allocator: std.mem.Allocator, comptime Storage: type, storage: *Storage) !void {
    const dir_path = try std.fs.selfExeDirPathAlloc(allocator);
    defer allocator.free(dir_path);

    var dir = try std.fs.openDirAbsolute(dir_path, .{ .access_sub_paths = true });
    defer dir.close();

    var scenes_dir = try dir.makeOpenPath("scenes", .{ .access_sub_paths = true });
    defer scenes_dir.close();

    const scene_file = scenes_dir.openFile(scene_name, .{}) catch return error.InvalidSceneName;
    defer scene_file.close();

    const ezby_scene = try scene_file.readToEndAlloc(allocator, std.math.pow(usize, 1024, 3) * 256);
    defer allocator.free(ezby_scene);

    switch (op) {
        .overwrite => try ecez.ezby.deserialize(Storage, .overwrite, storage, ezby_scene),
        .append => try ecez.ezby.deserialize(Storage, .append, storage, ezby_scene),
    }
}
