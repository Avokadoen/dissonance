const std = @import("std");

const ecez = @import("ecez");
const rgui = @import("raygui");
const rl = @import("raylib");
const ztracy = @import("ztracy");

const SceneEditor = @import("SceneEditor.zig");
const reflection = SceneEditor.reflection;
const EntityInspector = SceneEditor.EntityInspector;
const layout_config = SceneEditor.layout_config;
const UpdateEventArgument = @import("main.zig").UpdateEventArgument;

const box2d_c = @cImport(@cInclude("box2d/box2d.h"));
const Box2DRT = @This();

pub const components = struct {
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
            const position = storage.getComponent(selected_entity, Position) orelse {
                const label_bounds = rl.Rectangle{
                    .x = parent_bounds.x + layout_config.EntityInspector.component_field_width_padding,
                    .y = parent_bounds.y,
                    .width = parent_bounds.width - (layout_config.EntityInspector.component_field_width_padding * 2),
                    .height = layout_config.font_size * 1.5,
                };
                _ = rgui.label(label_bounds, "Box requires position component!");
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
            const ground_polygon = box2d_c.b2MakeBox(box.extent.x, box.extent.y);
            var shape_def = box2d_c.b2DefaultShapeDef();
            _ = box2d_c.b2CreatePolygonShape(box.body_id, &shape_def, &ground_polygon);
        }
    };
};

pub fn CreateSystems(comptime Storage: type) type {
    _ = Storage; // autofix
    return struct {
        // Ecez is multithreaded, we must indicate to ecez that the next systems depend on this one
        // Let box2d to its calculations
        pub fn doBox2DStep(rotation_barrier: *RotationPropagateQuery, position_barrier: *RotationPropagateQuery, event_argument: UpdateEventArgument) void {
            const zone = ztracy.ZoneN(@src(), @src().fn_name);
            defer zone.End();
            _ = rotation_barrier;
            _ = position_barrier;
            box2d_c.b2World_Step(event_argument.box2d_rt.world_id, event_argument.delta_time, event_argument.box2d_rt.config.substeps);
        }

        pub const RotationPropagateQuery = ecez.Query(struct {
            rotation: *components.Rotation,
            box: components.BoxCollider,
        }, .{}, .{});
        pub fn propagateBox2DRotation(rotation_query: *RotationPropagateQuery) void {
            const zone = ztracy.ZoneN(@src(), @src().fn_name);
            defer zone.End();

            while (rotation_query.next()) |entity| {
                const rotation = box2d_c.b2Body_GetRotation(entity.box.body_id);
                const radians = box2d_c.b2Rot_GetAngle(rotation);
                entity.rotation.degrees = std.math.radiansToDegrees(radians);
            }
        }

        pub const PositionPropagateQuery = ecez.Query(struct {
            position: *components.Position,
            box: components.BoxCollider,
        }, .{}, .{});
        pub fn propagateBox2DPosition(position_query: *PositionPropagateQuery) void {
            const zone = ztracy.ZoneN(@src(), @src().fn_name);
            defer zone.End();

            while (position_query.next()) |entity| {
                const p = box2d_c.b2Body_GetWorldPoint(
                    entity.box.body_id,
                    box2d_c.b2Vec2{
                        .x = -entity.box.extent.x,
                        .y = -entity.box.extent.y,
                    },
                );
                entity.position.value = rl.Vector2{
                    .x = p.x,
                    .y = p.y,
                };
            }
        }
    };
}

pub const Config = struct {
    length_units_per_meter: f32 = 128.0,
    gravity: f32 = 9.8,
    substeps: c_int = 4,
};

config: Config,
world_id: box2d_c.b2WorldId,

pub fn init(config: Config) Box2DRT {
    box2d_c.b2SetLengthUnitsPerMeter(config.length_units_per_meter);

    var world_def = box2d_c.b2DefaultWorldDef();
    world_def.gravity.y = config.gravity * config.length_units_per_meter;
    const world_id = box2d_c.b2CreateWorld(&world_def);

    return Box2DRT{
        .config = config,
        .world_id = world_id,
    };
}

pub fn deinit(box2d_rt: Box2DRT) void {
    box2d_c.b2DestroyWorld(box2d_rt.world_id);
}
