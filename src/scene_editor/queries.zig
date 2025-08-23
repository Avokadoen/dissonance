const ecez = @import("ecez");

const EntityInfo = @import("EntityInfo.zig");

pub const EntityInfoQuery = ecez.Query(struct {
    handle: ecez.Entity,
    info: *EntityInfo,
}, .{}, .{});
