const std = @import("std");

const ecez = @import("ecez");
const rl = @import("raylib");
const ztracy = @import("ztracy");

const UpdateEventArgument = @import("../common.zig").UpdateEventArgument;
const components = @import("components.zig");

const box2d_c = @cImport(@cInclude("box2d/box2d.h"));

/// Ecez is multithreaded, we must indicate to ecez that the next systems depend on this one
/// Let box2d to its calculations
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
                .x = 0,
                .y = 0,
            },
        );
        entity.position.value = rl.Vector2{
            .x = p.x,
            .y = p.y,
        };
    }
}
