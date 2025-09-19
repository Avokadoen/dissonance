const std = @import("std");

const rgui = @import("raygui");
const rl = @import("raylib");

const EntityInspector = @import("EntityInspector.zig");
const layout_config = @import("layout_config.zig");

pub fn renderStruct(
    entity_inspector: *EntityInspector,
    comptime Struct: type,
    instance: *Struct,
    parent_bounds: *rl.Rectangle,
) void {
    inline for (@typeInfo(Struct).@"struct".fields) |field| {
        switch (@typeInfo(field.type)) {
            .bool => renderBool(&@field(instance, field.name), field.name, parent_bounds),
            .int, .float => renderIntOrFloat(entity_inspector, Struct, field.type, &@field(instance, field.name), field.name, parent_bounds),
            .@"enum" => |enum_info| renderEnum(entity_inspector, enum_info, field.type, &@field(instance, field.name), field.name, parent_bounds),
            .array => |arr_info| {
                inline for (&@field(instance, field.name), 0..) |*arr_element, index| {
                    const field_name = std.fmt.comptimePrint("{s}_{d}", .{ field.name, index });
                    switch (@typeInfo(arr_info.child)) {
                        .bool => renderBool(arr_element, field_name, parent_bounds),
                        .int, .float => renderIntOrFloat(entity_inspector, Struct, arr_info.child, arr_element, field_name, parent_bounds),
                        .@"struct" => renderStruct(entity_inspector, arr_info.child, arr_element, parent_bounds),
                        .@"enum" => |enum_info| renderEnum(entity_inspector, enum_info, arr_info.child, arr_element, field_name, parent_bounds),
                        else => @compileError("Unimplemented"),
                    }
                }
            },
            .@"struct" => {
                const label_bounds = rl.Rectangle{
                    .x = parent_bounds.x + layout_config.EntityInspector.component_field_width_padding,
                    .y = parent_bounds.y,
                    .width = parent_bounds.width - (layout_config.EntityInspector.component_field_width_padding * 2),
                    .height = layout_config.font_size * 1.5,
                };
                _ = rgui.label(label_bounds, field.name);
                parent_bounds.y += label_bounds.height + layout_config.EntityInspector.spacing;

                renderStruct(entity_inspector, field.type, &@field(instance, field.name), parent_bounds);
            },
            .@"union" => @compileError("Unimplemented"), // Is this needed?
            .optional => @compileError("Unimplemented"), // Is this needed?
            .pointer => @compileError("please dont use pointer in a component type!"), // This will lead to serialization issues :(
            else => |type_tag| @compileError("sceneEditorGenericWidget does not support " ++ @tagName(type_tag)),
        }
    }
}

pub fn renderBool(value: *bool, field_name: [:0]const u8, parent_bounds: *rl.Rectangle) void {
    const checkbox_bound = rl.Rectangle{
        .x = parent_bounds.x + layout_config.EntityInspector.component_field_width_padding,
        .y = parent_bounds.y,
        .width = layout_config.EntityInspector.checkbox_dim,
        .height = layout_config.EntityInspector.checkbox_dim,
    };
    _ = rgui.checkBox(checkbox_bound, field_name, value);

    parent_bounds.y += checkbox_bound.height + layout_config.EntityInspector.spacing;
}

pub fn renderIntOrFloat(
    entity_inspector: *EntityInspector,
    comptime ParentType: type,
    comptime T: type,
    value: *T,
    comptime field_name: [:0]const u8,
    parent_bounds: *rl.Rectangle,
) void {
    const label_bounds = rl.Rectangle{
        .x = parent_bounds.x + layout_config.EntityInspector.component_field_width_padding,
        .y = parent_bounds.y,
        .width = parent_bounds.width - (layout_config.EntityInspector.component_field_width_padding * 2),
        .height = layout_config.font_size * 1.5,
    };
    _ = rgui.label(label_bounds, field_name);

    const value_bound = rl.Rectangle{
        .x = parent_bounds.x + layout_config.EntityInspector.component_field_width_padding,
        .y = parent_bounds.y + label_bounds.height,
        .width = parent_bounds.width - (layout_config.EntityInspector.component_field_width_padding * 2),
        .height = layout_config.input_field_height,
    };

    switch (@typeInfo(T)) {
        .int => |int_info| {
            const edit_mode = rl.checkCollisionPointRec(rl.getMousePosition(), value_bound);
            const min_value = if (int_info.signedness == .signed) std.math.minInt(i32) else 0;
            const max_value = std.math.maxInt(i32);
            var tmp_int: i32 = @intCast(value.*);
            _ = rgui.valueBox(value_bound, "", &tmp_int, min_value, max_value, edit_mode);
            value.* = @intCast(tmp_int);
        },
        .float => {
            const edit_mode = rl.checkCollisionPointRec(rl.getMousePosition(), value_bound);
            var text_buffer: [64]u8 = undefined;
            var text_buffer_write: std.io.Writer = .fixed(&text_buffer);
            text_buffer_write.printValue(
                "d",
                .{},
                value.*,
                std.options.fmt_max_depth,
            ) catch @panic("failed to format float");
            text_buffer[text_buffer_write.end] = 0;

            if (edit_mode) {
                const this_float = std.hash.XxHash32.hash(0xABBAABBA, @typeName(ParentType) ++ field_name);
                if (entity_inspector.active_edit != .float or entity_inspector.active_edit.float.hash != this_float) {
                    entity_inspector.active_edit = .{ .float = .{
                        .hash = this_float,
                        .input_buffer = undefined,
                    } };

                    var edit_buffer_write: std.io.Writer = .fixed(&entity_inspector.active_edit.float.input_buffer);
                    edit_buffer_write.printValue(
                        "d",
                        .{},
                        value.*,
                        std.options.fmt_max_depth,
                    ) catch @panic("failed to format float");
                    @memset(entity_inspector.active_edit.float.input_buffer[edit_buffer_write.end..], 0);
                }

                const used_text_buffer = std.mem.span(@as([*:0]u8, @ptrCast(&entity_inspector.active_edit.float.input_buffer)));
                var tmp_float: f32 = std.fmt.parseFloat(f32, used_text_buffer) catch 0;
                _ = rgui.valueBoxFloat(value_bound, "", used_text_buffer, &tmp_float, edit_mode);
                value.* = @floatCast(tmp_float);
            } else {
                const used_text_buffer = text_buffer[0..text_buffer_write.end :0];
                var tmp_float: f32 = @floatCast(value.*);
                _ = rgui.valueBoxFloat(value_bound, "", used_text_buffer, &tmp_float, edit_mode);
            }
        },
        else => unreachable,
    }

    parent_bounds.y += label_bounds.height + layout_config.EntityInspector.spacing + value_bound.height;
}

pub fn renderEnum(
    entity_inspector: *EntityInspector,
    comptime enum_info: std.builtin.Type.Enum,
    comptime T: type,
    value: *T,
    field_name: [:0]const u8,
    parent_bounds: *rl.Rectangle,
) void {
    const label_bounds = rl.Rectangle{
        .x = parent_bounds.x + layout_config.EntityInspector.component_field_width_padding,
        .y = parent_bounds.y,
        .width = parent_bounds.width - (layout_config.EntityInspector.component_field_width_padding * 2),
        .height = layout_config.font_size * 1.5,
    };
    _ = rgui.label(label_bounds, field_name);

    var tmp_value: i32 = @intFromEnum(value.*);
    const value_bound = rl.Rectangle{
        .x = parent_bounds.x + layout_config.EntityInspector.component_field_width_padding,
        .y = parent_bounds.y + label_bounds.height,
        .width = parent_bounds.width - (layout_config.EntityInspector.component_field_width_padding * 2),
        .height = layout_config.input_field_height,
    };

    var edit_mode_bound = rl.Rectangle{
        .x = value_bound.x,
        .y = value_bound.y,
        .width = value_bound.width,
        .height = value_bound.height,
    };
    const edit_mode = is_editing_this_blk: {
        const this_enum = std.hash.XxHash32.hash(0xABBAABBA, @typeName(T));

        // User is currently editing some enum
        switch (entity_inspector.active_edit) {
            .dropdown => |*dropdown_value| {
                // ... and if user is not editing this enum
                if (dropdown_value.* != this_enum) {
                    break :is_editing_this_blk false;
                }
                // User is editing this enum
                // check if we are still hovering dropdown options, + 1 to account for the actual value field
                edit_mode_bound.height *= enum_info.fields.len + 1;

                // If user is still hovering dropdown, all good
                if (rl.checkCollisionPointRec(rl.getMousePosition(), edit_mode_bound)) {
                    break :is_editing_this_blk true;
                }
                // User stopped editing this enum, propagate needed insepctor state and report back
                entity_inspector.active_edit = .none;
                break :is_editing_this_blk false;
            },
            else => {
                // User is not editing any enum, but might start editing this
                if (rl.checkCollisionPointRec(rl.getMousePosition(), edit_mode_bound)) {
                    entity_inspector.active_edit = .{ .dropdown = this_enum };
                    break :is_editing_this_blk true;
                }
                // User is not starting to edit this enum
                break :is_editing_this_blk false;
            },
        }
    };

    // We need a format string that is i.e for 3 enum values: "{s};{s};{s}"
    const dropdown_fmt_str = "{s};" ** (enum_info.fields.len - 1) ++ "{s}";
    const FmtTupleType = std.meta.Tuple(&([_]type{[]const u8} ** enum_info.fields.len));
    comptime var fmt_data_tuple: FmtTupleType = undefined;
    inline for (&fmt_data_tuple, enum_info.fields) |*tag_name, field| {
        tag_name.* = field.name;
    }
    const values_str = std.fmt.comptimePrint(dropdown_fmt_str, fmt_data_tuple);

    _ = rgui.dropdownBox(value_bound, values_str, &tmp_value, edit_mode);
    value.* = @enumFromInt(tmp_value);

    parent_bounds.y += edit_mode_bound.height + layout_config.EntityInspector.spacing + value_bound.height;
}

pub const ComponentListEntry = struct {
    Component: type,
    global_index: u32,
};

/// Get list of component editor actually can see.
/// Components that has a decl with IgnoreInEditor will not be included in the editor
pub fn getComponentList(comptime Storage: type) []const ComponentListEntry {
    if (@inComptime() == false) {
        @compileError("calling " ++ @src().fn_name ++ " on runtime is illegal (use comptime)");
    }

    comptime var component_array: [Storage.component_type_array.len]ComponentListEntry = undefined;
    comptime var component_array_len = 0;
    for (Storage.component_type_array, 0..) |Component, comp_index| {
        if (@hasDecl(Component, "IgnoreInEditor") == false) {
            component_array[component_array_len] = ComponentListEntry{
                .Component = Component,
                .global_index = comp_index,
            };
            component_array_len += 1;
        }
    }

    return component_array[0..component_array_len];
}

pub fn componentName(comptime Component: type) [:0]const u8 {
    if (@inComptime() == false) {
        @compileError("calling " ++ @src().fn_name ++ " on runtime is illegal (use comptime)");
    }

    const full_name = std.fmt.comptimePrint("{s}" ++ [_]u8{0}, .{@typeName(Component)});
    var iter = std.mem.splitScalar(u8, full_name, '.');
    var last_name_section: []const u8 = undefined;
    while (iter.next()) |name_section| {
        last_name_section = name_section;
    }
    return last_name_section[0.. :0];
}

pub fn componentHasDefaults(comptime Component: type) bool {
    if (@inComptime() == false) {
        @compileError("calling " ++ @src().fn_name ++ " on runtime is illegal (use comptime)");
    }

    inline for (@typeInfo(Component).@"struct".fields) |field| {
        if (field.default_value_ptr == null) {
            return false;
        }
    }

    return true;
}
