const rl = @import("raylib");

const Box2DRT = @import("../Box2DRT.zig");

total_time: f64,
delta_time: f32,
frame_dim: rl.Vector2,
box2d_rt: Box2DRT,
