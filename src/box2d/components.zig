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
pub const StaticTag = struct {};

pub const Position = struct {
    value: rl.Vector2,
};

pub const Rotation = struct {
    degrees: f32,
};

pub const BoxCollider = struct {
    body_id: box2d_c.b2BodyId = box2d_c.b2_nullBodyId,
    extent: box2d_c.b2Vec2 = .{
        .x = 10,
        .y = 10,
    },

    pub fn sceneEditorOverrideWidget(
        box: *BoxCollider,
        selected_entity: ecez.Entity,
        box2d_rt: Box2DRT,
        entity_inspector: *EntityInspector,
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
        const has_static = storage.hasComponents(selected_entity, .{StaticTag});
        // TODO: maybe DONT crash if user adds both :)
        // Fuck you if you add both ...
        std.debug.assert((has_dynamic and has_static) == false);

        if (!has_dynamic and !has_static) {
            const label_bounds = rl.Rectangle{
                .x = parent_bounds.x + layout_config.EntityInspector.component_field_width_padding,
                .y = parent_bounds.y,
                .width = parent_bounds.width - (layout_config.EntityInspector.component_field_width_padding * 2),
                .height = layout_config.font_size * 1.5,
            };
            _ = rgui.label(label_bounds, "Box requires either DynamicTag or StaticTag!");
            parent_bounds.y += label_bounds.height + layout_config.EntityInspector.spacing;
            return;
        }

        // Box newly created, register in box2d
        if (box2d_c.B2_IS_NULL(box.body_id)) {
            var body_def = box2d_c.b2DefaultBodyDef();
            body_def.position = box2d_c.b2Vec2{ .x = position.value.x, .y = position.value.y };
            const radians = std.math.degreesToRadians(rotation.degrees);
            body_def.rotation = box2d_c.b2MakeRot(radians);
            body_def.type = if (has_dynamic) box2d_c.b2_dynamicBody else box2d_c.b2_staticBody;
            box.body_id = box2d_c.b2CreateBody(box2d_rt.world_id, &body_def);
        }

        reflection.renderStruct(entity_inspector, box2d_c.b2Vec2, &box.extent, parent_bounds);

        // Disallow 0 extent
        box.extent.x = @max(box.extent.x, 1);
        box.extent.y = @max(box.extent.y, 1);

        // TODO: is this leaking?
        // Update polygon, just in case :)
        // These polygons are centered on the origin and when they are added to a body they
        // will be centered on the body position.
        const polygon = box2d_c.b2MakeBox(box.extent.x, box.extent.y);
        var shape_def = box2d_c.b2DefaultShapeDef();
        _ = box2d_c.b2CreatePolygonShape(box.body_id, &shape_def, &polygon);
    }
};
