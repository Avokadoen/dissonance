const std = @import("std");

const ecez = @import("ecez");
const rgui = @import("raygui");
const rl = @import("raylib");
const ztracy = @import("ztracy");

pub const components = @import("box2d/components.zig");
pub const systems = @import("box2d/systems.zig");

pub const box2d = struct {
    const c = @cImport(@cInclude("box2d/box2d.h"));

    pub const WorldId = c.b2WorldId;
    pub const WorldDef = c.b2WorldDef;

    pub const ShapeDef = c.b2ShapeDef;
    pub const ShapeId = c.b2ShapeId;
    pub const null_shape_id = c.b2_nullShapeId;

    pub const BodyDef = c.b2BodyDef;
    pub const BodyId = c.b2BodyId;
    pub const null_body_id = c.b2_nullBodyId;

    pub const BodyType = enum(c_uint) {
        static = c.b2_staticBody,
        kinematic = c.b2_kinematicBody,
        dynamic = c.b2_dynamicBody,
    };

    pub const Vec2 = c.b2Vec2;
    pub const Rot = c.b2Rot;

    pub const Polygon = c.b2Polygon;

    pub const ContactEvents = c.b2ContactEvents;

    pub fn createWorld(def: *const WorldDef) WorldId {
        return c.b2CreateWorld(@ptrCast(def));
    }

    pub fn destroyWorld(world_id: WorldId) void {
        c.b2DestroyWorld(world_id);
    }

    pub fn defaultWorldDef() WorldDef {
        return c.b2DefaultWorldDef();
    }

    pub fn worldStep(world_id: WorldId, time_step: f32, sub_step_count: c_int) void {
        c.b2World_Step(world_id, time_step, sub_step_count);
    }

    pub fn worldGetContactEvents(world_id: WorldId) ContactEvents {
        return c.b2World_GetContactEvents(world_id);
    }

    pub fn setLengthUnitsPerMeter(length_units: f32) void {
        c.b2SetLengthUnitsPerMeter(length_units);
    }

    pub fn shapeDefaultDef() ShapeDef {
        return c.b2DefaultShapeDef();
    }

    pub fn shapeDestroy(shape_id: ShapeId, update_body_mass: bool) void {
        c.b2DestroyShape(shape_id, update_body_mass);
    }

    pub fn shapeAreHitEventsEnabled(shape_id: ShapeId) bool {
        return c.b2Shape_AreHitEventsEnabled(shape_id);
    }

    pub fn shapeGetBody(shape_id: ShapeId) BodyId {
        return c.b2Shape_GetBody(shape_id);
    }

    pub fn bodyDefaultDef() BodyDef {
        return c.b2DefaultBodyDef();
    }

    pub fn bodyCreate(world_id: WorldId, def: *const BodyDef) BodyId {
        return c.b2CreateBody(world_id, def);
    }

    pub fn bodyDestroy(body_id: BodyId) void {
        return c.b2DestroyBody(body_id);
    }

    pub fn bodySetTransform(body_id: BodyId, position: Vec2, rotation: Rot) void {
        c.b2Body_SetTransform(body_id, position, rotation);
    }

    pub fn bodyGetRotation(body_id: BodyId) Rot {
        return c.b2Body_GetRotation(body_id);
    }

    pub fn bodyCreatePolygonShape(body_id: BodyId, def: *const ShapeDef, polygon: *const Polygon) ShapeId {
        return c.b2CreatePolygonShape(body_id, @ptrCast(def), @ptrCast(polygon));
    }

    pub fn bodyGetWorldPoint(body_id: BodyId, local_point: Vec2) Vec2 {
        return c.b2Body_GetWorldPoint(body_id, local_point);
    }

    pub fn bodyGetUserData(body_id: BodyId) ?*anyopaque {
        return c.b2Body_GetUserData(body_id);
    }

    pub fn makeRot(arg_radians: f32) Rot {
        return c.b2MakeRot(arg_radians);
    }

    pub fn makeBox(half_width: f32, half_height: f32) Polygon {
        return c.b2MakeBox(half_width, half_height);
    }

    pub fn getAngle(arg_q: Rot) f32 {
        return c.b2Rot_GetAngle(arg_q);
    }

    pub fn isNull(id: anytype) bool {
        return c.B2_IS_NULL(id);
    }
};

const Box2DRT = @This();

pub const Config = struct {
    length_units_per_meter: f32 = 512.0,
    gravity: f32 = 9.8,
    substeps: c_int = 4,
};

config: Config,
world_id: box2d.WorldId,

pub fn init(config: Config) Box2DRT {
    box2d.setLengthUnitsPerMeter(config.length_units_per_meter);
    var world_def = box2d.defaultWorldDef();
    world_def.gravity.y = config.gravity * config.length_units_per_meter;
    const world_id = box2d.createWorld(&world_def);

    return Box2DRT{
        .config = config,
        .world_id = world_id,
    };
}

pub fn reset(box2d_rt: *Box2DRT, allocator: std.mem.Allocator, comptime Storage: type, storage: *Storage) !void {
    const BoxColliderQuery = ecez.Query(struct {
        box: *components.BoxCollider,
    }, .{}, .{});
    var box_iter = try BoxColliderQuery.submit(allocator, storage);
    defer box_iter.deinit(allocator);
    while (box_iter.next()) |entity| {
        const update_body_mass = false;
        box2d.shapeDestroy(entity.box.shape_id, update_body_mass);
        entity.box.shape_id = box2d.null_shape_id;
        box2d.bodyDestroy(entity.box.body_id);
        entity.box.body_id = box2d.null_body_id;
    }
    box2d.destroyWorld(box2d_rt.world_id);

    box2d.setLengthUnitsPerMeter(box2d_rt.config.length_units_per_meter);
    var world_def = box2d.defaultWorldDef();
    world_def.gravity.y = box2d_rt.config.gravity * box2d_rt.config.length_units_per_meter;
    box2d_rt.world_id = box2d.createWorld(&world_def);
}

/// Reload physics engine to sync with storage loads
pub fn reloadPhysicsState(box2d_rt: *Box2DRT, allocator: std.mem.Allocator, comptime Storage: type, storage: *Storage) !void {
    const BoxColliderQuery = ecez.Query(struct {
        handle: ecez.Entity,
        box: *components.BoxCollider,
        position: *const components.Position,
        rotation: *const components.Rotation,
    }, .{}, .{});
    var box_iter = try BoxColliderQuery.submit(allocator, storage);
    defer box_iter.deinit(allocator);
    while (box_iter.next()) |entity| {
        const maybe_dynamic = storage.getComponent(entity.handle, components.Dynamic);
        const radians = std.math.degreesToRadians(entity.rotation.degrees);
        const box2d_rot = box2d.makeRot(radians);
        const box2d_pos = box2d.Vec2{
            .x = entity.position.value.x,
            .y = entity.position.value.y,
        };
        box2d_rt.createBody(entity.handle, entity.box, box2d_pos, box2d_rot, maybe_dynamic);
        box2d.bodySetTransform(entity.box.body_id, box2d_pos, box2d_rot);

        const polygon = box2d.makeBox(entity.box.extent.x * 0.5, entity.box.extent.y * 0.5);
        var shape_def = defaultShapeDef(maybe_dynamic);
        entity.box.shape_id = box2d.bodyCreatePolygonShape(entity.box.body_id, &shape_def, &polygon);
    }
}

pub fn getRaylibWorldPos(box: components.BoxCollider) box2d.Vec2 {
    return box2d.bodyGetWorldPoint(
        box.body_id,
        box2d.Vec2{
            .x = -box.extent.x * 0.5,
            .y = -box.extent.y * 0.5,
        },
    );
}

pub fn createBody(
    box2d_rt: *const Box2DRT,
    entity: ecez.Entity,
    box: *components.BoxCollider,
    box2d_pos: box2d.Vec2,
    box2d_rot: box2d.Rot,
    dynamic: ?components.Dynamic,
) void {
    var body_def = box2d.bodyDefaultDef();
    body_def.position = box2d_pos;
    body_def.rotation = box2d_rot;
    body_def.type = @intFromEnum(if (dynamic != null) box2d.BodyType.dynamic else box2d.BodyType.static);
    // HACK: Store the entity handle as a address to some data, but then the address is the data ...
    body_def.userData = @ptrFromInt(@as(usize, @intCast(entity.id)));
    box.body_id = box2d.bodyCreate(box2d_rt.world_id, &body_def);
}

pub fn defaultShapeDef(maybe_dynamic: ?components.Dynamic) box2d.ShapeDef {
    var shape_def = box2d.shapeDefaultDef();
    if (maybe_dynamic) |dynamic| {
        shape_def.enableHitEvents = dynamic.enable_hit_events;
        shape_def.enableContactEvents = dynamic.enable_contact_events;
    }
    return shape_def;
}

pub fn deinit(box2d_rt: Box2DRT) void {
    box2d.destroyWorld(box2d_rt.world_id);
}
