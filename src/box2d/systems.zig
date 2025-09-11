const std = @import("std");

const ecez = @import("ecez");
const rl = @import("raylib");
const ztracy = @import("ztracy");

const box2d = @import("../Box2DRT.zig").box2d;
const UpdateEventArgument = @import("../common.zig").UpdateEventArgument;
const components = @import("components.zig");

pub fn Create(comptime Storage: type) type {
    return struct {
        /// Ecez is multithreaded, we must indicate to ecez that the next systems depend on this one
        /// Let box2d to its calculations
        pub fn doBox2DStep(rotation_barrier: *RotationPropagateQuery, position_barrier: *PositionPropagateQuery, event_argument: UpdateEventArgument) void {
            const zone = ztracy.ZoneN(@src(), @src().fn_name);
            defer zone.End();
            _ = rotation_barrier;
            _ = position_barrier;
            box2d.worldStep(event_argument.box2d_rt.world_id, event_argument.delta_time, event_argument.box2d_rt.config.substeps);
        }

        pub const RotationPropagateQuery = ecez.Query(struct {
            rotation: *components.Rotation,
            box: components.BoxCollider,
        }, .{}, .{});
        pub fn propagateBox2DRotation(rotation_query: *RotationPropagateQuery) void {
            const zone = ztracy.ZoneN(@src(), @src().fn_name);
            defer zone.End();

            while (rotation_query.next()) |entity| {
                const rotation = box2d.bodyGetRotation(entity.box.body_id);
                const radians = box2d.getAngle(rotation);
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
                const p = box2d.bodyGetWorldPoint(
                    entity.box.body_id,
                    box2d.Vec2{
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

        // Query just to ensure we wait for doBox2DStep
        pub const DoBox2DStepBarrier = ecez.Query(struct {
            entity: ecez.Entity,
        }, .{
            components.Position,
            components.Rotation,
        }, .{});
        pub const HitEventsStorage = Storage.Subset(.{
            *components.HitEvents,
        });
        pub fn registerHitEvents(do_box2d_barrier: *DoBox2DStepBarrier, hit_events_storage: *HitEventsStorage, event_argument: UpdateEventArgument) void {
            _ = do_box2d_barrier;

            const contact_events = box2d.worldGetContactEvents(event_argument.box2d_rt.world_id);

            const hit_count: usize = @intCast(contact_events.hitCount);
            for (contact_events.hitEvents[0..hit_count]) |hit_event| {
                const entity_a, const entity_b = getEntityAB(hit_event);

                for (&[_]RegShapes{
                    .{ .shape = hit_event.shapeIdA, .entity = entity_a, .other = entity_b },
                    .{ .shape = hit_event.shapeIdB, .entity = entity_b, .other = entity_a },
                }) |reg| {
                    if (box2d.shapeAreHitEventsEnabled(reg.shape)) {
                        var hit_event_component = hit_events_storage.getComponent(reg.entity, *components.HitEvents) orelse create_event_blk: {
                            hit_events_storage.setComponents(reg.entity, .{components.HitEvents.empty}) catch @panic("oom");
                            break :create_event_blk hit_events_storage.getComponent(reg.entity, *components.HitEvents).?;
                        };

                        hit_event_component.append(components.HitEvents.Data{
                            .other = reg.other,
                            .point = hit_event.point,
                            .normal = hit_event.normal,
                            .approachSpeed = hit_event.approachSpeed,
                        }) catch {
                            // TODO: replace with proper logging or some handling?
                            std.debug.print("failed to append hit event!\n", .{});
                        };
                    }
                }
            }
        }

        pub const TouchBeginStorage = Storage.Subset(.{
            *components.TouchBeginEvents,
        });
        pub fn registerTouchBeginEvents(do_box2d_barrier: *DoBox2DStepBarrier, touch_begin_storage: *TouchBeginStorage, event_argument: UpdateEventArgument) void {
            _ = do_box2d_barrier;

            const contact_events = box2d.worldGetContactEvents(event_argument.box2d_rt.world_id);

            const begin_count: usize = @intCast(contact_events.beginCount);
            for (contact_events.beginEvents[0..begin_count]) |begin_event| {
                const entity_a, const entity_b = getEntityAB(begin_event);

                for (&[_]RegShapes{
                    .{ .shape = begin_event.shapeIdA, .entity = entity_a, .other = entity_b },
                    .{ .shape = begin_event.shapeIdB, .entity = entity_b, .other = entity_a },
                }) |reg| {
                    if (box2d.shapeAreHitEventsEnabled(reg.shape)) {
                        var hit_event_component = touch_begin_storage.getComponent(reg.entity, *components.TouchBeginEvents) orelse create_event_blk: {
                            touch_begin_storage.setComponents(reg.entity, .{components.TouchBeginEvents.empty}) catch @panic("oom");
                            break :create_event_blk touch_begin_storage.getComponent(reg.entity, *components.TouchBeginEvents).?;
                        };

                        hit_event_component.append(components.TouchBeginEvents.Data{
                            .other = reg.other,
                        }) catch {
                            // TODO: replace with proper logging or some handling?
                            std.debug.print("failed to append hit event!\n", .{});
                        };
                    }
                }
            }
        }

        pub const TouchEndStorage = Storage.Subset(.{
            *components.TouchEndEvents,
        });
        pub fn registerTouchEndEvents(do_box2d_barrier: *DoBox2DStepBarrier, touch_end_storage: *TouchEndStorage, event_argument: UpdateEventArgument) void {
            _ = do_box2d_barrier;

            const contact_events = box2d.worldGetContactEvents(event_argument.box2d_rt.world_id);

            const end_count: usize = @intCast(contact_events.endCount);
            for (contact_events.endEvents[0..end_count]) |end_event| {
                const entity_a, const entity_b = getEntityAB(end_event);

                for (&[_]RegShapes{
                    .{ .shape = end_event.shapeIdA, .entity = entity_a, .other = entity_b },
                    .{ .shape = end_event.shapeIdB, .entity = entity_b, .other = entity_a },
                }) |reg| {
                    if (box2d.shapeAreHitEventsEnabled(reg.shape)) {
                        var hit_event_component = touch_end_storage.getComponent(reg.entity, *components.TouchEndEvents) orelse create_event_blk: {
                            touch_end_storage.setComponents(reg.entity, .{components.TouchEndEvents.empty}) catch @panic("oom");
                            break :create_event_blk touch_end_storage.getComponent(reg.entity, *components.TouchEndEvents).?;
                        };

                        hit_event_component.append(components.TouchEndEvents.Data{
                            .other = reg.other,
                        }) catch {
                            // TODO: replace with proper logging or some handling?
                            std.debug.print("failed to append hit event!\n", .{});
                        };
                    }
                }
            }
        }

        pub const RemoveHitEventsQuery = ecez.Query(
            struct {
                entity: ecez.Entity,
            },
            .{components.HitEvents},
            .{},
        );
        pub fn unRegisterHitEvents(remove_hit_events_query: *RemoveHitEventsQuery, hit_events_storage: *HitEventsStorage) void {
            while (remove_hit_events_query.next()) |hit_events| {
                hit_events_storage.unsetComponents(hit_events.entity, .{components.HitEvents});
            }
        }

        pub const RemoveTouchBeginQuery = ecez.Query(
            struct {
                entity: ecez.Entity,
            },
            .{components.TouchBeginEvents},
            .{},
        );
        pub fn unRegisterTouchBeginEvents(touch_begin_query: *RemoveTouchBeginQuery, touch_begin_storage: *TouchBeginStorage) void {
            while (touch_begin_query.next()) |touch_begin| {
                touch_begin_storage.unsetComponents(touch_begin.entity, .{components.TouchBeginEvents});
            }
        }

        pub const RemoveTouchEndQuery = ecez.Query(
            struct {
                entity: ecez.Entity,
            },
            .{components.TouchEndEvents},
            .{},
        );
        pub fn unRegisterTouchEndEvents(touch_end_query: *RemoveTouchEndQuery, touch_end_storage: *TouchEndStorage) void {
            while (touch_end_query.next()) |touch_end| {
                touch_end_storage.unsetComponents(touch_end.entity, .{components.TouchEndEvents});
            }
        }
    };
}

const RegShapes = struct {
    shape: box2d.ShapeId,
    entity: ecez.Entity,
    other: ecez.Entity,
};

fn getEntityAB(box2d_struct: anytype) std.meta.Tuple(&[2]type{ ecez.Entity, ecez.Entity }) {
    const body_a = box2d.shapeGetBody(box2d_struct.shapeIdA);
    const body_b = box2d.shapeGetBody(box2d_struct.shapeIdB);

    const entity_a_opaque = box2d.bodyGetUserData(body_a);
    const entity_a = ecez.Entity{
        .id = @intCast(@intFromPtr(entity_a_opaque)),
    };

    const entity_b_opaque = box2d.bodyGetUserData(body_b);
    const entity_b = ecez.Entity{
        .id = @intCast(@intFromPtr(entity_b_opaque)),
    };

    return .{
        entity_a,
        entity_b,
    };
}
