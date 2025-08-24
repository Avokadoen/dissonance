const std = @import("std");

const ecez = @import("ecez");
const rgui = @import("raygui");
const rl = @import("raylib");
const tracy = @import("ztracy");

const Box2DRT = @import("../Box2DRT.zig");
const EntityInfo = @import("EntityInfo.zig");
const layout_config = @import("layout_config.zig");
const queries = @import("queries.zig");

const EntityList = @This();
pub const searchbar_len = 64;

pub const init = EntityList{
    .scroll = rl.Vector2{ .x = 0, .y = 0 },
    .entity_copy_bytes = null,
    .searchbar_str = [_]u8{0} ** searchbar_len,
};

scroll: rl.Vector2,
entity_copy_bytes: ?[]const u8,

searchbar_str: [64]u8,

pub fn draw(
    entity_list: *EntityList,
    allocator: std.mem.Allocator,
    comptime Storage: type,
    storage: *Storage,
    box2d_rt: *Box2DRT,
    selected_entity: *?ecez.Entity,
) !void {
    const zone = tracy.ZoneN(@src(), @typeName(@This()) ++ "." ++ @src().fn_name);
    defer zone.End();

    const r_height = rl.getRenderHeight();

    rgui.setStyle(.listview, .{ .listview = .scrollbar_side }, rgui.scrollbar_left_side);
    const scroll_bar_size: f32 = @floatFromInt(rgui.getStyle(.scrollbar, .{ .scrollbar = .scroll_slider_size }));
    const title = std.fmt.comptimePrint("#{d}#Entity List", .{@intFromEnum(rgui.IconName.box_grid)});

    const bounds = rl.Rectangle{
        .x = 0,
        .y = layout_config.Toolbar.height,
        .width = layout_config.EntityList.width,
        .height = @floatFromInt(r_height - layout_config.Toolbar.height),
    };

    var entity_entry_bounds = rl.Rectangle{
        .x = bounds.x + layout_config.EntityList.entity_entry_padding,
        .y = bounds.y + 30 + layout_config.EntityList.spacing + entity_list.scroll.y,
        .width = bounds.width - layout_config.EntityList.entity_entry_padding * 2,
        .height = 30,
    };

    var button_bound = rl.Rectangle{
        .x = bounds.x + scroll_bar_size,
        .y = entity_entry_bounds.y,
        .width = layout_config.EntityInspector.button_dim,
        .height = layout_config.EntityInspector.button_dim,
    };

    const searchbar_label_bound = rl.Rectangle{
        .x = button_bound.x,
        .y = button_bound.y + button_bound.height + layout_config.EntityList.spacing + layout_config.font_size,
        .width = bounds.width - (scroll_bar_size + (layout_config.EntityList.spacing * 2)),
        .height = layout_config.font_size,
    };

    const searchbar_bound = rl.Rectangle{
        .x = button_bound.x,
        .y = searchbar_label_bound.y + searchbar_label_bound.height,
        .width = bounds.width - (scroll_bar_size + (layout_config.EntityList.spacing * 2)),
        .height = layout_config.input_field_height,
    };

    const line_bound = rl.Rectangle{
        .x = bounds.x,
        .y = searchbar_bound.y + searchbar_bound.height + layout_config.EntityInspector.spacing,
        .width = bounds.width,
        .height = @floatFromInt(layout_config.font_size),
    };

    const post_line_offset = searchbar_label_bound.height + searchbar_bound.height + button_bound.height + layout_config.EntityInspector.spacing * 3 + layout_config.font_size * 2;

    var view: rl.Rectangle = undefined;
    {
        const total_entities: f32 = @floatFromInt(storage.created_entity_count.load(.monotonic) - storage.inactive_entities.items.len);
        const content = rl.Rectangle{
            .x = bounds.x,
            .y = bounds.y,
            .width = bounds.width - scroll_bar_size,
            .height = post_line_offset + (total_entities + 1) * (entity_entry_bounds.height + layout_config.EntityInspector.spacing),
        };
        _ = rgui.scrollPanel(bounds, title, content, &entity_list.scroll, &view);
    }

    {
        rl.beginScissorMode(
            @intFromFloat(view.x),
            @intFromFloat(view.y),
            @intFromFloat(view.width),
            @intFromFloat(view.height),
        );
        defer rl.endScissorMode();

        {
            rgui.enableTooltip();
            defer rgui.disableTooltip();

            rgui.setTooltip("New entity");
            const create_entity_txt = std.fmt.comptimePrint("#{d}#", .{@intFromEnum(rgui.IconName.file_add)});
            if (rgui.button(button_bound, create_entity_txt)) {
                const new_entity_info = EntityInfo.init("new entity");
                selected_entity.* = try storage.createEntity(.{new_entity_info});
            }
            button_bound.x += layout_config.EntityList.spacing + button_bound.width;

            rgui.setTooltip("Copy selected entity to clipboard");
            const copy_entity_txt = std.fmt.comptimePrint("#{d}#", .{@intFromEnum(rgui.IconName.file_copy)});
            if (rgui.button(button_bound, copy_entity_txt)) {
                if (selected_entity.*) |entity| {
                    // free previous bytes if any
                    if (entity_list.entity_copy_bytes) |ezby_bytes| {
                        allocator.free(ezby_bytes);
                    }

                    // create a new storage
                    var dummy_storage = try Storage.init(allocator);
                    defer dummy_storage.deinit();

                    // create a new entiy in said storage
                    const place_holder_entity = try dummy_storage.createEntity(.{});

                    // foreach component, if present, get and add to new entity
                    inline for (Storage.component_type_array) |Component| {
                        if (@sizeOf(Component) > 0) {
                            if (storage.getComponent(entity, Component)) |component| {
                                try dummy_storage.setComponents(place_holder_entity, .{component});
                            }
                        } else {
                            if (storage.hasComponents(entity, .{Component})) {
                                try dummy_storage.setComponents(place_holder_entity, .{Component{}});
                            }
                        }
                    }

                    // serialize storage to ezby bytes
                    entity_list.entity_copy_bytes = try ecez.ezby.serialize(allocator, Storage, dummy_storage, .{});
                }
            }
            button_bound.x += layout_config.EntityList.spacing + button_bound.width;

            rgui.setTooltip("Paste entity from clipboard");
            const paste_entity_txt = std.fmt.comptimePrint("#{d}#", .{@intFromEnum(rgui.IconName.file_paste)});
            if (rgui.button(button_bound, paste_entity_txt)) {
                if (entity_list.entity_copy_bytes) |ezby_bytes| {
                    box2d_rt.reset();
                    try ecez.ezby.deserialize(Storage, .append, storage, ezby_bytes);
                    try box2d_rt.reloadPhysicsState(allocator, Storage, storage);
                }
            }

            const edit_mode = rl.checkCollisionPointRec(rl.getMousePosition(), searchbar_bound);
            _ = rgui.label(searchbar_label_bound, "Entity name search:");
            _ = rgui.textBox(
                searchbar_bound,
                entity_list.searchbar_str[0 .. entity_list.searchbar_str.len - 1 :0],
                entity_list.searchbar_str.len,
                edit_mode,
            );

            _ = rgui.line(line_bound, "");

            entity_entry_bounds.y += post_line_offset;
        }

        const searchbar_ptr: [*:0]u8 = @ptrCast(&entity_list.searchbar_str);
        const searchbar_slice = std.mem.span(searchbar_ptr);

        var info_query = try queries.EntityInfoQuery.submit(allocator, storage);
        defer info_query.deinit(allocator);
        while (info_query.next()) |entity| {
            if (searchbar_slice.len > 0) {
                const index_of = std.mem.indexOf(u8, &entity.info.name_buffer, searchbar_slice);
                if (index_of == null) {
                    continue;
                }
            }

            // if scene editor has no entity selected, and we have not selected an arbitrary entity
            // yet which the scene editor can grab
            if (selected_entity.* == null) {
                selected_entity.* = entity.handle;
            }

            if (rgui.button(entity_entry_bounds, entity.info.name())) {
                selected_entity.* = entity.handle;
            }

            entity_entry_bounds.y += entity_entry_bounds.height + layout_config.EntityList.spacing;
        }
    }
}

pub fn deinit(entity_list: *EntityList, allocator: std.mem.Allocator) void {
    if (entity_list.entity_copy_bytes) |ezby_bytes| {
        allocator.free(ezby_bytes);
    }
}
