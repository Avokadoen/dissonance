const std = @import("std");

const ecez = @import("ecez");
const rgui = @import("raygui");
const rl = @import("raylib");
const ztracy = @import("ztracy");

const Box2DRT = @import("../Box2DRT.zig");
const box2d = Box2DRT.box2d;
const UpdateEventArgument = @import("../common.zig").UpdateEventArgument;
const SceneEditor = @import("../SceneEditor.zig");
const EntityInspector = @import("../SceneEditor.zig").EntityInspector;
const layout_config = SceneEditor.layout_config;
const reflection = SceneEditor.reflection;
const components = @import("components.zig");

pub const Dynamic = struct {
    enable_hit_events: bool,
    enable_contact_events: bool,
};

pub const HitEvents = GenEventType(struct {
    other: ecez.Entity,
    point: box2d.Vec2,
    normal: box2d.Vec2,
    approachSpeed: f32,
});

pub const TouchBeginEvents = GenEventType(struct {
    other: ecez.Entity,
});

pub const TouchEndEvents = GenEventType(struct {
    other: ecez.Entity,
});

pub const Position = struct {
    value: rl.Vector2,
};

pub const Rotation = struct {
    degrees: f32,
};

pub const BoxCollider = struct {
    body_id: box2d.BodyId = box2d.null_body_id,
    shape_id: box2d.ShapeId,
    extent: box2d.Vec2 = .{
        .x = 10,
        .y = 10,
    },

    pub fn sceneEditorOverrideWidget(
        box: *BoxCollider,
        selected_entity: ecez.Entity,
        box2d_rt: Box2DRT,
        entity_inspector: *EntityInspector,
        is_playing: bool,
        parent_bounds: *rl.Rectangle,
        comptime Storage: type,
        storage: *Storage,
    ) void {
        const position: Position = storage.getComponent(selected_entity, Position) orelse {
            const label_bounds = rl.Rectangle{
                .x = parent_bounds.x + layout_config.EntityInspector.component_field_width_padding,
                .y = parent_bounds.y,
                .width = parent_bounds.width - (layout_config.EntityInspector.component_field_width_padding * 2),
                .height = layout_config.font_size * 1.5,
            };
            _ = rgui.label(label_bounds, "Box requires Position component!");
            parent_bounds.y += label_bounds.height + layout_config.EntityInspector.spacing;
            return;
        };

        const rotation: Rotation = storage.getComponent(selected_entity, Rotation) orelse {
            const label_bounds = rl.Rectangle{
                .x = parent_bounds.x + layout_config.EntityInspector.component_field_width_padding,
                .y = parent_bounds.y,
                .width = parent_bounds.width - (layout_config.EntityInspector.component_field_width_padding * 2),
                .height = layout_config.font_size * 1.5,
            };
            _ = rgui.label(label_bounds, "Box requires Rotation component!");
            parent_bounds.y += label_bounds.height + layout_config.EntityInspector.spacing;
            return;
        };

        const maybe_dynamic = storage.getComponent(selected_entity, components.Dynamic);
        const radians = std.math.degreesToRadians(rotation.degrees);
        const box2d_rot = box2d.makeRot(radians);
        const box2d_pos = box2d.Vec2{
            .x = position.value.x,
            .y = position.value.y,
        };

        // Box newly created, register in box2d
        if (box2d.isNull(box.body_id)) {
            box2d_rt.createBody(selected_entity, box, box2d_pos, box2d_rot, maybe_dynamic);
        }

        if (is_playing == false) {
            box2d.bodySetTransform(box.body_id, box2d_pos, box2d_rot);
        }

        const prev = box.extent;
        reflection.renderStruct(entity_inspector, box2d.Vec2, &box.extent, parent_bounds);
        // TODO: float comparison bad
        if (prev.x == box.extent.x and prev.y == box.extent.y) {
            return;
        }

        // Disallow 0 extent
        box.extent.x = @max(box.extent.x, 1);
        box.extent.y = @max(box.extent.y, 1);

        if (box2d.isNull(box.shape_id) == false) {
            const update_body_mass = false;
            box2d.shapeDestroy(box.shape_id, update_body_mass);
        }

        const polygon = box2d.makeBox(box.extent.x * 0.5, box.extent.y * 0.5);
        var shape_def = Box2DRT.defaultShapeDef(maybe_dynamic);
        box.shape_id = box2d.bodyCreatePolygonShape(box.body_id, &shape_def, &polygon);
    }
};

fn GenEventType(comptime DataType: type) type {
    return struct {
        pub const EventType = @This();

        pub const empty = EventType{
            .event_len = 0,
            .events = undefined,
        };

        pub const max_events = 8;

        pub const Data = DataType;

        event_len: u8,
        events: [max_events]Data,

        pub fn append(events: *EventType, data: Data) !void {
            if (events.event_len >= max_events) {
                return error.OutOfMemory;
            }

            events.events[events.event_len] = data;
            events.event_len += 1;
        }
    };
}
