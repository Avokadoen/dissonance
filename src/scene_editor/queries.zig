const ecez = @import("ecez");

const components = @import("components.zig");

pub const EditorInfo = ecez.Query(struct {
    handle: ecez.Entity,
    info: *components.EditorInfo,
}, .{}, .{});
