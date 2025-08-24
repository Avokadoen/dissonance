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

pub fn reset(box2d_rt: *Box2DRT) void {
    box2d_c.b2DestroyWorld(box2d_rt.world_id);

    box2d_c.b2SetLengthUnitsPerMeter(box2d_rt.config.length_units_per_meter);

    var world_def = box2d_c.b2DefaultWorldDef();
    world_def.gravity.y = box2d_rt.config.gravity * box2d_rt.config.length_units_per_meter;
    box2d_rt.world_id = box2d_c.b2CreateWorld(&world_def);
}

/// Reload physics engine to sync with storage loads
pub fn reloadPhysicsState(box2d_rt: Box2DRT, allocator: std.mem.Allocator, comptime Storage: type, storage: *Storage) !void {
    const BoxColliderQuery = ecez.Query(struct {
        handle: ecez.Entity,
        box: *components.BoxCollider,
        position: components.Position,
        rotation: components.Rotation,
    }, .{}, .{});
    var box_iter = try BoxColliderQuery.submit(allocator, storage);
    defer box_iter.deinit(allocator);
    while (box_iter.next()) |entity| {
        const has_dynamic = storage.hasComponents(entity.handle, .{components.DynamicTag});
        const has_static = storage.hasComponents(entity.handle, .{components.StaticTag});
        // TODO: maybe DONT crash if user adds both :)
        // Fuck you if you add both ...
        std.debug.assert((has_dynamic and has_static) == false);

        var body_def = box2d_c.b2DefaultBodyDef();
        body_def.position = box2d_c.b2Vec2{ .x = entity.position.value.x, .y = entity.position.value.y };
        const radians = std.math.degreesToRadians(entity.rotation.degrees);
        body_def.rotation = box2d_c.b2MakeRot(radians);
        body_def.type = if (has_dynamic) box2d_c.b2_dynamicBody else box2d_c.b2_staticBody;
        entity.box.body_id = box2d_c.b2CreateBody(box2d_rt.world_id, &body_def);

        // TODO: is this leaking?
        // Update polygon, just in case :)
        // These polygons are centered on the origin and when they are added to a body they
        // will be centered on the body position.
        const polygon = box2d_c.b2MakeBox(entity.box.extent.x, entity.box.extent.y);
        var shape_def = box2d_c.b2DefaultShapeDef();
        _ = box2d_c.b2CreatePolygonShape(entity.box.body_id, &shape_def, &polygon);
    }
}

pub fn deinit(box2d_rt: Box2DRT) void {
    box2d_c.b2DestroyWorld(box2d_rt.world_id);
}
