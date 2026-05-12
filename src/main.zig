const std = @import("std");
const log = std.log;
const assert = std.debug.assert;
const gpa = std.heap.wasm_allocator;
const math = std.math;

const V = @import("Vec2d.zig");

const js = struct {
    extern "js" fn log(ptr: [*]const u8, len: usize) void;
    extern "js" fn panic(ptr: [*]const u8, len: usize) noreturn;
    extern "js" fn buttons(ptr: [*]u8, len: usize) void;
    extern "js" fn fillText(ptr: [*]const u8, len: usize, size: u16, x: u16, y: u16) void;
    extern "js" fn drawImage(img: usize, x: u16, y: u16) void;
    extern "js" fn loadSound(ptr: [*]const u8, len: usize) void;
    extern "js" fn playSound(sound: usize) void;
    extern "js" fn loadImage(ptr: [*]const u8, len: usize) Size;
};

pub const std_options: std.Options = .{
    .logFn = logFn,
    .log_level = .debug,
};

pub fn panic(msg: []const u8, st: ?*std.builtin.StackTrace, addr: ?usize) noreturn {
    _ = st;
    _ = addr;
    log.err("panic: {s}", .{msg});
    @trap();
}

fn logFn(
    comptime message_level: log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime message_level.asText();
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    var buf: [500]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, level_txt ++ prefix2 ++ format, args) catch l: {
        buf[buf.len - 3 ..][0..3].* = "...".*;
        break :l &buf;
    };
    js.log(line.ptr, line.len);
}

const String = Slice(u8);

fn Slice(T: type) type {
    return packed struct(u64) {
        ptr: u32,
        len: u32,

        const empty: @This() = .{ .ptr = 0, .len = 0 };

        fn init(s: []const T) @This() {
            return .{
                .ptr = @intFromPtr(s.ptr),
                .len = s.len,
            };
        }
    };
}

const Size = packed struct(u32) {
    x: u16,
    y: u16,
};

const Buttons = extern struct {
    a: bool,
    b: bool,
    up: bool,
    down: bool,
    left: bool,
    right: bool,
    start: bool,
};

fn fillText(text: []const u8, size: u16, x: u16, y: u16) void {
    js.fillText(text.ptr, text.len, size, x, y);
}

const Game = struct {
    assets: Assets = .{},
    players: [2]Player = .{
        .{
            .ship = @enumFromInt(0),
        },
        .{
            .ship = @enumFromInt(1),
        },
    },
    ships: std.ArrayList(Ship) = .empty,
};

var game: Game = .{};

const Player = struct {
    ship: Ship.Index,
};

const Ship = struct {
    still: Animation.Index,
    accel: Animation.Index,
    anim_playback: Animation.Playback,
    /// pixels
    pos: V,
    /// pixels per second
    vel: V,
    /// radians
    rotation: f32,
    radius: f32,

    /// radians per second
    rotation_vel: f32,
    /// pixels per second squared
    thrust: f32,

    /// Player or AI decisions on what they want the ship to do.
    input: Input,
    /// Keeps track of the input from last frame so that the game logic can
    /// notice when a button is first pressed.
    prev_input: Input,

    turret: Turret,

    hp: f32,
    max_hp: f32,

    const Index = enum(u32) {
        _,
    };

    const Input = packed struct {
        fire: bool = false,
        forward: bool = false,
        left: bool = false,
        right: bool = false,
    };

    fn setAnimation(ship: *Ship, animation: Animation.Index) void {
        ship.anim_playback = .{
            .index = animation,
            .time_passed = 0,
        };
    }
};

const Animation = struct {
    /// Index into frames array
    start: u32,
    /// Number of frames elements used in this animation.
    len: u32,
    /// After finishing, will jump to this next animation (which may be
    /// itself, in which case it will loop).
    next: Index,
    /// frames per second
    fps: f32,

    /// Index into animations array.
    const Index = enum(u32) {
        none = math.maxInt(u32),
        _,
    };

    const Playback = struct {
        index: Index,
        /// number of seconds passed since Animation start.
        time_passed: f32,
    };
};

const Turret = struct {
    /// Together with angle, this is the location of the turret from the center
    /// of the containing object. Pixels.
    radius: f32,
    /// Together with radius, this is the location of the turret from the
    /// center of the containing object. Radians.
    angle: f32,
    /// Seconds until ready. Less than or equal to 0 means ready.
    cooldown: f32,
    /// Seconds until ready. Cooldown is set to this after firing.
    cooldown_amount: f32,

    /// pixels per second
    bullet_speed: f32,
    /// seconds
    bullet_duration: f32,
    /// Amount of HP the bullet removes upon landing a hit.
    bullet_damage: f32,
};

export fn setup() void {
    setupFallible() catch @panic("setup failed");
}

fn setupFallible() !void {
    loadSound("sfx/weak_shot1.ogg");
    const assets = &game.assets;

    const ship_sprites = [_]Sprite.Index{
        try assets.loadSprite("img/ship/ranger0.png"),
        try assets.loadSprite("img/ship/ranger1.png"),
        try assets.loadSprite("img/ship/ranger2.png"),
        try assets.loadSprite("img/ship/ranger3.png"),
    };
    const ship_still = try assets.addAnimation(&.{
        ship_sprites[0],
    }, null, 30);
    const ship_steady_thrust = try assets.addAnimation(&.{
        ship_sprites[2],
        ship_sprites[3],
    }, null, 10);
    const ship_accel = try assets.addAnimation(&.{
        ship_sprites[0],
        ship_sprites[1],
    }, ship_steady_thrust, 10);

    const ship_radius = assets.sprite(ship_sprites[0]).size.x / 2.0;

    const ship_turret: Turret = .{
        .radius = ship_radius,
        .angle = 0,
        .cooldown = 0,
        .cooldown_amount = 0.2,
        .bullet_speed = 500,
        .bullet_duration = 0.5,
        .bullet_damage = 10,
    };

    const ranger_template: Ship = .{
        .input = .{},
        .prev_input = .{},
        .still = ship_still,
        .accel = ship_accel,
        .anim_playback = .{ .index = ship_still, .time_passed = 0 },
        .pos = .{ .x = 0, .y = 0 },
        .vel = .{ .x = 0, .y = 0 },
        .rotation = -math.pi / 2.0,
        .rotation_vel = math.pi * 1.1,
        .thrust = 150,
        .turret = ship_turret,
        .radius = ship_radius,
        .hp = 80,
        .max_hp = 80,
    };

    const ships = &game.ships;

    for (&game.players, 0..) |_, i| {
        try ships.append(gpa, ranger_template);
        ships.items[ships.items.len - 1].pos = .{
            .x = 500 + 500 * @as(f32, @floatFromInt(i)),
            .y = 500,
        };
    }
}
fn loadSound(sound: []const u8) void {
    js.loadSound(sound.ptr, sound.len);
}

/// The main game loop.
export fn update() void {
    var button_buffer: [16]u8 = undefined;
    js.buttons(&button_buffer, button_buffer.len);
    const buttons: [2]*const Buttons = .{
        @ptrCast(&button_buffer[0]),
        @ptrCast(&button_buffer[8]),
    };

    if (buttons[0].a) {
        fillText("player 1 A pressed", 30, 1, 100);
        js.playSound(0);
    }
    if (buttons[1].b) {
        fillText("player 2 B pressed", 30, 1, 100);
        js.playSound(0);
    }

    js.drawImage(0, 100, 0);
}

const Sprite = struct {
    pos: V,
    size: V,

    const Index = enum(u32) {
        /// Index into the images array.
        _,
    };
};

const Assets = struct {
    sprites: std.ArrayList(Sprite) = .empty,
    frames: std.ArrayList(Sprite.Index) = .empty,
    animations: std.ArrayList(Animation) = .empty,

    fn animate(a: Assets, anim: *Animation.Playback, dt: f32) Sprite {
        const animation = a.animations.items[@intFromEnum(anim.index)];
        const frame_index: u32 = @floor(anim.time_passed * animation.fps);
        const frame = animation.start + frame_index;
        const frame_sprite = a.sprite(a.frames.items[frame]);
        anim.time_passed += dt;
        const end_time = @as(f32, @floatFromInt(animation.len)) / animation.fps;
        if (anim.time_passed >= end_time) {
            anim.time_passed -= end_time;
            anim.index = animation.next;
        }
        return frame_sprite;
    }

    /// null next_animation means to loop.
    fn addAnimation(
        a: *Assets,
        frames: []const Sprite.Index,
        next_animation: ?Animation.Index,
        fps: f32,
    ) !Animation.Index {
        try a.frames.appendSlice(gpa, frames);
        const result: Animation.Index = @enumFromInt(a.animations.items.len);
        try a.animations.append(gpa, .{
            .start = @intCast(a.frames.items.len - frames.len),
            .len = @intCast(frames.len),
            .next = next_animation orelse result,
            .fps = fps,
        });
        return result;
    }

    fn sprite(a: Assets, index: Sprite.Index) Sprite {
        return a.sprites.items[@intFromEnum(index)];
    }

    fn loadSprite(a: *Assets, name: []const u8) !Sprite.Index {
        const size = js.loadImage(name.ptr, name.len);
        try a.sprites.append(gpa, .{
            .pos = .{ .x = 0, .y = 0 },
            .size = .{ .x = size.x, .y = size.y },
        });
        return @enumFromInt(a.sprites.items.len - 1);
    }
};
