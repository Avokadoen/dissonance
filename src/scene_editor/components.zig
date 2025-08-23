const std = @import("std");

const ecez = @import("ecez");
const rgui = @import("raygui");
const rl = @import("raylib");

const EntityInspector = @import("EntityInspector.zig");
const layout_config = @import("layout_config.zig");

pub const EditorInfo = struct {
    name_buffer: [64]u8,

    pub fn init(inital_name: []const u8) EditorInfo {
        var info: EditorInfo = undefined;
        @memcpy(info.name_buffer[0..inital_name.len], inital_name);
        info.name_buffer[inital_name.len] = 0;

        return info;
    }

    pub fn name(info: *EditorInfo) [:0]u8 {
        const len = std.mem.indexOf(u8, &info.name_buffer, &[_]u8{0}).?;
        return info.name_buffer[0..len :0];
    }

    pub fn sceneEditorOverrideWidget(
        info: *EditorInfo,
        entity_inspector: *EntityInspector,
        parent_bounds: *rl.Rectangle,
    ) void {
        _ = entity_inspector;

        const label_bounds = rl.Rectangle{
            .x = parent_bounds.x + layout_config.EntityInspector.component_field_width_padding,
            .y = parent_bounds.y,
            .width = parent_bounds.width - (layout_config.EntityInspector.component_field_width_padding * 2),
            .height = layout_config.font_size * 1.5,
        };
        _ = rgui.label(label_bounds, "Name:");

        const text_box_bounds = rl.Rectangle{
            .x = parent_bounds.x + layout_config.EntityInspector.component_field_width_padding,
            .y = label_bounds.y + label_bounds.height,
            .width = parent_bounds.width - (layout_config.EntityInspector.component_field_width_padding * 2),
            .height = layout_config.input_field_height,
        };

        const edit_mode = rl.checkCollisionPointRec(rl.getMousePosition(), text_box_bounds);
        _ = rgui.textBox(text_box_bounds, info.name(), info.name_buffer.len, edit_mode);

        parent_bounds.y += text_box_bounds.height + label_bounds.height + layout_config.EntityInspector.spacing;
    }
};

pub const queries = struct {};
