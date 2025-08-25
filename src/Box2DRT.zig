const std = @import("std");

const ecez = @import("ecez");
const rgui = @import("raygui");
const rl = @import("raylib");
const ztracy = @import("ztracy");

pub const components = @import("box2d/components.zig");
pub const systems = @import("box2d/systems.zig");

const box2d_c = @cImport(@cInclude("box2d/box2d.h"));
const Box2DRT = @This();

pub const Config = struct {
    length_units_per_meter: f32 = 512.0,
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

pub fn reset(box2d_rt: *Box2DRT, allocator: std.mem.Allocator, comptime Storage: type, storage: *Storage) !void {
    const BoxColliderQuery = ecez.Query(struct {
        box: *components.BoxCollider,
    }, .{}, .{});
    var box_iter = try BoxColliderQuery.submit(allocator, storage);
    defer box_iter.deinit(allocator);
    while (box_iter.next()) |entity| {
        const update_body_mass = false;
        box2d_c.b2DestroyShape(entity.box.shape_id, update_body_mass);
        entity.box.shape_id = box2d_c.b2_nullShapeId;
        box2d_c.b2DestroyBody(entity.box.body_id);
        entity.box.body_id = box2d_c.b2_nullBodyId;
    }
    box2d_c.b2DestroyWorld(box2d_rt.world_id);

    box2d_c.b2SetLengthUnitsPerMeter(box2d_rt.config.length_units_per_meter);
    var world_def = box2d_c.b2DefaultWorldDef();
    world_def.gravity.y = box2d_rt.config.gravity * box2d_rt.config.length_units_per_meter;
    box2d_rt.world_id = box2d_c.b2CreateWorld(&world_def);
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
        const has_dynamic = storage.hasComponents(entity.handle, .{components.DynamicTag});
        const radians = std.math.degreesToRadians(entity.rotation.degrees);
        const box2d_rot = box2d_c.b2MakeRot(radians);
        const box2d_pos = box2d_c.b2Vec2{
            .x = entity.position.value.x,
            .y = entity.position.value.y,
        };
        box2d_rt.createBody(entity.handle, entity.box, box2d_pos, box2d_rot, has_dynamic);
        box2d_c.b2Body_SetTransform(entity.box.body_id, box2d_pos, box2d_rot);

        const polygon = box2d_c.b2MakeBox(entity.box.extent.x * 0.5, entity.box.extent.y * 0.5);
        var shape_def = defaultShapeDef();
        entity.box.shape_id = box2d_c.b2CreatePolygonShape(entity.box.body_id, &shape_def, &polygon);
    }
}

pub fn getRaylibWorldPos(box: components.BoxCollider) box2d_c.b2Vec2 {
    return box2d_c.b2Body_GetWorldPoint(
        box.body_id,
        box2d_c.b2Vec2{
            .x = -box.extent.x * 0.5,
            .y = -box.extent.y * 0.5,
        },
    );
}

pub fn createBody(
    box2d_rt: *const Box2DRT,
    entity: ecez.Entity,
    box: *components.BoxCollider,
    box2d_pos: box2d_c.b2Vec2,
    box2d_rot: box2d_c.b2Rot,
    has_dynamic: bool,
) void {
    var body_def = box2d_c.b2DefaultBodyDef();
    body_def.position = box2d_pos;
    body_def.rotation = box2d_rot;
    body_def.type = if (has_dynamic) box2d_c.b2_dynamicBody else box2d_c.b2_staticBody;
    // HACK: Store the entity handle as a address to some data, but then the address is the data ...
    body_def.userData = @ptrFromInt(@as(usize, @intCast(entity.id)));
    box.body_id = box2d_c.b2CreateBody(box2d_rt.world_id, &body_def);
}

pub fn defaultShapeDef() box2d_c.b2ShapeDef {
    var shape_def = box2d_c.b2DefaultShapeDef();
    // shape_def.enableSensorEvents = true;
    // shape_def.enableContactEvents = true;
    shape_def.enableHitEvents = true;
    shape_def.invokeContactCreation = true;
    return shape_def;
}

pub fn deinit(box2d_rt: Box2DRT) void {
    box2d_c.b2DestroyWorld(box2d_rt.world_id);
}
