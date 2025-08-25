const std = @import("std");

const ecez = @import("ecez");
const rgui = @import("raygui");
const rl = @import("raylib");
const ztracy = @import("ztracy");

const Box2DRT = @import("../Box2DRT.zig");
const UpdateEventArgument = @import("../common.zig").UpdateEventArgument;
const SceneEditor = @import("../SceneEditor.zig");
const EntityInspector = @import("../SceneEditor.zig").EntityInspector;
const layout_config = SceneEditor.layout_config;
const reflection = SceneEditor.reflection;
const components = @import("components.zig");

const box2d_c = @cImport(@cInclude("box2d/box2d.h"));
pub const DynamicTag = struct {};

pub const Position = struct {
    value: rl.Vector2,
};

pub const Rotation = struct {
    degrees: f32,
};

pub const BoxCollider = struct {
    body_id: box2d_c.b2BodyId = box2d_c.b2_nullBodyId,
    shape_id: box2d_c.b2ShapeId,
    extent: box2d_c.b2Vec2 = .{
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

        const has_dynamic = storage.hasComponents(selected_entity, .{DynamicTag});

        const radians = std.math.degreesToRadians(rotation.degrees);
        const box2d_rot = box2d_c.b2MakeRot(radians);
        const box2d_pos = box2d_c.b2Vec2{
            .x = position.value.x,
            .y = position.value.y,
        };

        // Box newly created, register in box2d
        if (box2d_c.B2_IS_NULL(box.body_id)) {
            box2d_rt.createBody(selected_entity, box, box2d_pos, box2d_rot, has_dynamic);
        }

        if (is_playing == false) {
            box2d_c.b2Body_SetTransform(box.body_id, box2d_pos, box2d_rot);
        }

        const prev = box.extent;
        reflection.renderStruct(entity_inspector, box2d_c.b2Vec2, &box.extent, parent_bounds);
        // TODO: float comparison bad
        if (prev.x == box.extent.x and prev.y == box.extent.y) {
            return;
        }

        // Disallow 0 extent
        box.extent.x = @max(box.extent.x, 1);
        box.extent.y = @max(box.extent.y, 1);

        if (box2d_c.B2_IS_NULL(box.shape_id) == false) {
            const update_body_mass = false;
            box2d_c.b2DestroyShape(box.shape_id, update_body_mass);
        }

        const polygon = box2d_c.b2MakeBox(box.extent.x * 0.5, box.extent.y * 0.5);
        var shape_def = Box2DRT.defaultShapeDef();
        box.shape_id = box2d_c.b2CreatePolygonShape(box.body_id, &shape_def, &polygon);
    }
};
