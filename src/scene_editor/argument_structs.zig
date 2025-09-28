const ecez = @import("ecez");
const rl = @import("raylib");

const Box2DRT = @import("../Box2DRT.zig");
const EntityInspector = @import("EntityInspector.zig");

pub const SceneEditorOverrideWidgetArgs = struct {
    selected_entity: ecez.Entity,
    box2d_rt: *Box2DRT,
    entity_inspector: *EntityInspector,
    is_playing: bool,
    parent_bounds: *rl.Rectangle,
};
