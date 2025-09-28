const std = @import("std");

const ecez = @import("ecez");
const rgui = @import("raygui");
const rl = @import("raylib");

const Box2DRT = @import("../Box2DRT.zig");
const EntityInspector = @import("EntityInspector.zig");
const layout_config = @import("layout_config.zig");
const SceneEditorOverrideWidgetArgs = @import("argument_structs.zig").SceneEditorOverrideWidgetArgs;

const EntityInfo = @This();

name_buffer: [64]u8,

pub fn init(inital_name: []const u8) EntityInfo {
    var info: EntityInfo = undefined;
    @memcpy(info.name_buffer[0..inital_name.len], inital_name);
    info.name_buffer[inital_name.len] = 0;

    return info;
}

pub fn name(info: *EntityInfo) [:0]u8 {
    const len = std.mem.indexOf(u8, &info.name_buffer, &[_]u8{0}).?;
    return info.name_buffer[0..len :0];
}

pub fn sceneEditorOverrideWidget(
    info: *EntityInfo,
    args: SceneEditorOverrideWidgetArgs,
    comptime Storage: type,
    storage: *Storage,
) void {
    _ = storage;

    var buffer: ["Entity 9999999, Name:".len]u8 = undefined;
    const str = std.fmt.bufPrint(&buffer, "Entity {d}, Name:", .{args.selected_entity.id}) catch fallback: {
        const fallback_str = "Name:";
        @memcpy(buffer[0..fallback_str.len], fallback_str);
        break :fallback buffer[0..fallback_str.len];
    };
    buffer[str.len] = 0;

    const label_bounds = rl.Rectangle{
        .x = args.parent_bounds.x + layout_config.EntityInspector.component_field_width_padding,
        .y = args.parent_bounds.y,
        .width = args.parent_bounds.width - (layout_config.EntityInspector.component_field_width_padding * 2),
        .height = layout_config.font_size * 1.5,
    };
    _ = rgui.label(label_bounds, buffer[0..str.len :0]);

    const text_box_bounds = rl.Rectangle{
        .x = args.parent_bounds.x + layout_config.EntityInspector.component_field_width_padding,
        .y = label_bounds.y + label_bounds.height,
        .width = args.parent_bounds.width - (layout_config.EntityInspector.component_field_width_padding * 2),
        .height = layout_config.input_field_height,
    };

    const edit_mode = rl.checkCollisionPointRec(rl.getMousePosition(), text_box_bounds);
    _ = rgui.textBox(text_box_bounds, info.name(), info.name_buffer.len, edit_mode);

    args.parent_bounds.y += text_box_bounds.height + label_bounds.height + layout_config.EntityInspector.spacing;
}
