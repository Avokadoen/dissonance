const std = @import("std");

const ecez = @import("ecez");
const rgui = @import("raygui");
const rl = @import("raylib");
const tracy = @import("ztracy");

const Box2DRT = @import("../Box2DRT.zig");
const EntityInfo = @import("EntityInfo.zig");
const layout_config = @import("layout_config.zig");
const reflection = @import("reflection.zig");

const EntityInspector = @This();

pub const ActiveEdit = union(enum) { none: void, dropdown: u32, float: struct {
    hash: u32,
    input_buffer: [64]u8,
} };

pub const init = EntityInspector{
    .scroll = rl.Vector2{ .x = 0, .y = 0 },
    .active_edit = .none,
    .hovering_component_dropdown = false,
    .add_component_selected = 0,
    .fake_clipboard_comp_index = 0,
    .fake_clipboard_len = 0,
    .fake_clipboard = undefined,
};

scroll: rl.Vector2,
active_edit: ActiveEdit,
hovering_component_dropdown: bool,
add_component_selected: i32,

fake_clipboard_comp_index: u32,
fake_clipboard_len: u32,
fake_clipboard: [1024]u8,

pub fn draw(
    entity_inspector: *EntityInspector,
    comptime Storage: type,
    storage: *Storage,
    box2d_rt: Box2DRT,
    maybe_selected_entity: *?ecez.Entity,
) !void {
    const zone = tracy.ZoneN(@src(), @typeName(@This()) ++ "." ++ @src().fn_name);
    defer zone.End();

    const r_width = rl.getRenderWidth();
    const r_height = rl.getRenderHeight();

    const bounds = rl.Rectangle{
        .x = @floatFromInt(r_width - layout_config.EntityInspector.width),
        .y = layout_config.Toolbar.height,
        .width = 300,
        .height = @floatFromInt(r_height - layout_config.Toolbar.height),
    };
    const content = rl.Rectangle{
        .x = bounds.x,
        .y = bounds.y,
        .width = bounds.width - 16,
        // TODO: height is not trivial to know ahead of time
        .height = bounds.height * 20,
    };

    const scroll_bar_size: f32 = @floatFromInt(rgui.getStyle(.scrollbar, .{ .scrollbar = .scroll_slider_size }));

    var view: rl.Rectangle = undefined;
    rgui.setStyle(.listview, .{ .listview = .scrollbar_side }, rgui.scrollbar_right_side);
    const title = std.fmt.comptimePrint("#{d}#Entity Inspector", .{@intFromEnum(rgui.IconName.cube)});
    _ = rgui.scrollPanel(bounds, title, content, &entity_inspector.scroll, &view);

    rl.beginScissorMode(
        @intFromFloat(view.x),
        @intFromFloat(view.y),
        @intFromFloat(view.width),
        @intFromFloat(view.height),
    );
    defer rl.endScissorMode();

    const selected_entity = maybe_selected_entity.* orelse {
        return;
    };

    var delete_entity: bool = false;
    const y_stride = entity_buttons_blk: {
        rgui.enableTooltip();
        defer rgui.disableTooltip();

        var button_bound = rl.Rectangle{
            .x = bounds.x + bounds.width - scroll_bar_size - layout_config.EntityInspector.button_dim,
            .y = layout_config.EntityInspector.y_base_position + entity_inspector.scroll.y,
            .width = layout_config.EntityInspector.button_dim,
            .height = layout_config.EntityInspector.button_dim,
        };

        rgui.setTooltip("Delete entity");
        const delete_txt = std.fmt.comptimePrint("#{d}#", .{@intFromEnum(rgui.IconName.bin)});
        delete_entity = rgui.button(button_bound, delete_txt);
        button_bound.x -= button_bound.width + layout_config.EntityInspector.spacing;

        rgui.setTooltip("Paste clipboard component into entity");
        const paste_txt = std.fmt.comptimePrint("#{d}#", .{@intFromEnum(rgui.IconName.file_paste)});
        if (rgui.button(button_bound, paste_txt)) {
            try readComponentFromClipboard(entity_inspector, selected_entity, Storage, storage);
        }
        button_bound.x -= button_bound.width + layout_config.EntityInspector.spacing;

        // font_size because we have tooltip
        break :entity_buttons_blk button_bound.y + button_bound.height + layout_config.font_size;
    };

    const add_component_list_bound = rl.Rectangle{
        .x = bounds.x + layout_config.EntityInspector.component_field_width_padding,
        .y = y_stride + layout_config.EntityInspector.spacing,
        .width = bounds.width - (layout_config.EntityInspector.component_field_width_padding * 2 + scroll_bar_size),
        .height = layout_config.input_field_height,
    };
    var hovering_list_bound = add_component_list_bound;
    {
        if (entity_inspector.hovering_component_dropdown) {
            hovering_list_bound.height *= Storage.component_type_array.len + 1;
            entity_inspector.hovering_component_dropdown = rl.checkCollisionPointRec(rl.getMousePosition(), hovering_list_bound);
        } else {
            entity_inspector.hovering_component_dropdown = rl.checkCollisionPointRec(rl.getMousePosition(), add_component_list_bound);
        }

        const add_str = "Add component;";
        comptime var str_size: usize = add_str.len;
        inline for (Storage.component_type_array) |Component| {
            const comp_name = comptime reflection.componentName(Component);
            // cull the zero delimiter
            str_size += comp_name.len - 1;
        }
        // Add 1 per ; needed + zero delimiter
        str_size += Storage.component_type_array.len;

        var component_index_map: [Storage.component_type_array.len]u32 = undefined;
        var dropdown_str_buf: [str_size]u8 = undefined;
        const add_component_dropdown_str: [:0]const u8 = create_dropdown_str_blk: {
            var used_size: usize = add_str.len;
            @memcpy(dropdown_str_buf[0..used_size], add_str);

            if (entity_inspector.hovering_component_dropdown == false) {
                entity_inspector.add_component_selected = 0;
            } else {
                var component_index_map_index: usize = 0;
                inline for (Storage.component_type_array, 0..) |Component, comp_index| {
                    if (storage.hasComponents(selected_entity, .{Component}) == false) {
                        const comp_name: []const u8 = comptime reflection.componentName(Component);
                        @memcpy(dropdown_str_buf[used_size .. used_size + comp_name.len], comp_name);
                        dropdown_str_buf[used_size + comp_name.len - 1] = ';';
                        used_size += comp_name.len;

                        component_index_map[component_index_map_index] = comp_index;
                        component_index_map_index += 1;
                    }
                }
            }
            dropdown_str_buf[used_size - 1] = 0;
            break :create_dropdown_str_blk dropdown_str_buf[0 .. used_size - 1 :0];
        };

        const mouse_pressed = rgui.dropdownBox(
            add_component_list_bound,
            add_component_dropdown_str,
            &entity_inspector.add_component_selected,
            entity_inspector.hovering_component_dropdown,
        );
        if (mouse_pressed == 1 and entity_inspector.add_component_selected > 0) {
            const requested_component = component_index_map[@intCast(entity_inspector.add_component_selected - 1)];
            inline for (Storage.component_type_array, 0..) |Component, comp_index| {
                if (requested_component == comp_index and storage.hasComponents(selected_entity, .{Component}) == false) {
                    // TODO: this may crash if running the editor in release, should @memset(0) instead of undefined!
                    // Respect default values, otherwise use undefined
                    const inital_comp: Component = if (comptime reflection.componentHasDefaults(Component)) .{} else undefined;
                    try storage.setComponents(selected_entity, .{inital_comp});

                    entity_inspector.hovering_component_dropdown = false;
                    entity_inspector.add_component_selected = 0;
                }
            }
        }
    }

    var components_bound = rl.Rectangle{
        .x = bounds.x,
        .y = hovering_list_bound.y + hovering_list_bound.height + layout_config.EntityInspector.spacing,
        .width = bounds.width - scroll_bar_size,
        .height = @floatFromInt(layout_config.font_size),
    };
    inline for (Storage.component_type_array, 0..) |Component, comp_index| {
        if (storage.hasComponents(selected_entity, .{Component})) {
            const component_name = comptime reflection.componentName(Component);
            _ = rgui.line(components_bound, component_name);

            components_bound.y += layout_config.EntityInspector.spacing;

            var delete_component: bool = false;
            {
                rgui.enableTooltip();
                defer rgui.disableTooltip();

                var button_bound = rl.Rectangle{
                    .x = components_bound.x + layout_config.EntityInspector.component_field_width_padding,
                    .y = components_bound.y,
                    .width = layout_config.EntityInspector.button_dim,
                    .height = layout_config.EntityInspector.button_dim,
                };

                if (@sizeOf(Component) > 0) {
                    const tool_tip_str = std.fmt.comptimePrint("Copy {s} data to clipboard", .{component_name});
                    rgui.setTooltip(tool_tip_str);
                    const copy_txt = std.fmt.comptimePrint("#{d}#", .{@intFromEnum(rgui.IconName.file_copy)});
                    if (rgui.button(button_bound, copy_txt)) {
                        try writeComponentToClipboard(entity_inspector, selected_entity, Component, Storage, storage, comp_index);
                    }
                    button_bound.x += button_bound.width + layout_config.EntityInspector.spacing;
                }

                if (Component != EntityInfo) {
                    const tool_tip_str = std.fmt.comptimePrint("Delete {s} from entity", .{component_name});
                    rgui.setTooltip(tool_tip_str);
                    const delete_txt = std.fmt.comptimePrint("#{d}#", .{@intFromEnum(rgui.IconName.bin)});
                    delete_component = rgui.button(button_bound, delete_txt);
                    button_bound.x += button_bound.width + layout_config.EntityInspector.spacing;
                }

                // font size as we have tooltips
                components_bound.y += button_bound.height + layout_config.font_size + layout_config.EntityInspector.spacing;
            }

            if (@sizeOf(Component) > 0) {
                const component = storage.getComponent(selected_entity, *Component).?;

                if (comptime @hasDecl(Component, "sceneEditorOverrideWidget")) {
                    component.sceneEditorOverrideWidget(
                        selected_entity,
                        box2d_rt,
                        entity_inspector,
                        &components_bound,
                        Storage,
                        storage,
                    );
                } else {
                    reflection.renderStruct(
                        entity_inspector,
                        Component,
                        component,
                        &components_bound,
                    );
                }
            }

            // defer the delete of component to avoid using after free data in UI
            if (delete_component) {
                storage.unsetComponents(selected_entity, .{Component});
            }
        }
    }

    // defer the delete of entity to avoid using after free data in UI
    if (delete_entity) {
        try storage.destroyEntity(selected_entity);
        maybe_selected_entity.* = null;
    }
}

fn writeComponentToClipboard(
    entity_inspector: *EntityInspector,
    selected_entity: ecez.Entity,
    comptime Component: type,
    comptime Storage: type,
    storage: *Storage,
    comp_index: u32,
) !void {
    const component = storage.getComponent(selected_entity, Component).?;
    const comp_bytes = std.mem.toBytes(component);

    entity_inspector.fake_clipboard_comp_index = comp_index;
    entity_inspector.fake_clipboard_len = comp_bytes.len;
    @memcpy(entity_inspector.fake_clipboard[0..comp_bytes.len], &comp_bytes);
}

fn readComponentFromClipboard(entity_inspector: *EntityInspector, selected_entity: ecez.Entity, comptime Storage: type, storage: *Storage) !void {
    if (entity_inspector.fake_clipboard_len == 0) {
        return;
    }

    inline for (Storage.component_type_array, 0..) |Component, comp_index| {
        if (entity_inspector.fake_clipboard_comp_index == comp_index) {
            const component = std.mem.bytesToValue(Component, entity_inspector.fake_clipboard[0..entity_inspector.fake_clipboard_len]);
            try storage.setComponents(selected_entity, .{component});
        }
    }

    return;
}
