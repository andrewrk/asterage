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
    extern "js" fn fillRect(Rect) void;
    extern "js" fn drawImage(img: Sprite.Index, rect: Rect, radians: f32) void;
    extern "js" fn loadSound(ptr: [*]const u8, len: usize) void;
    extern "js" fn playSound(sound: usize) void;
    extern "js" fn loadImage(ptr: [*]const u8, len: usize) void;
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

const Rect = packed struct(u64) {
    x: u16,
    y: u16,
    w: u16,
    h: u16,

    fn fromVec(pos: V, size: V) Rect {
        return .{
            .x = @trunc(pos.x),
            .y = @trunc(pos.y),
            .w = @trunc(size.x),
            .h = @trunc(size.y),
        };
    }
};

const Size = packed struct(u64) {
    w: i16,
    h: i16,
    padding: u32 = 0,
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
    rng: std.Random.DefaultPrng = .init(0),
    stars: [150]Star,
};

var game: Game = .{ .stars = undefined };

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

        fn ptr(i: Index) *Ship {
            return &game.ships.items[@intFromEnum(i)];
        }
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
        try assets.loadSprite("img/ship/ranger0.png", .{ .x = 32, .y = 32 }),
        try assets.loadSprite("img/ship/ranger1.png", .{ .x = 32, .y = 32 }),
        try assets.loadSprite("img/ship/ranger2.png", .{ .x = 32, .y = 32 }),
        try assets.loadSprite("img/ship/ranger3.png", .{ .x = 32, .y = 32 }),
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
            .x = 20 + 100 * @as(f32, @floatFromInt(i)),
            .y = 20,
        };
    }

    generateStars(&game.stars);
}
fn loadSound(sound: []const u8) void {
    js.loadSound(sound.ptr, sound.len);
}

const Star = struct {
    rect: Rect,
};

const display_size: Size = .{ .w = 336, .h = 262 };

fn generateStars(stars: []Star) void {
    const rng = game.rng.random();
    for (stars) |*star| {
        const w: u16 = switch (rng.enumValue(enum { big, small })) {
            .big => 2,
            .small => 1,
        };
        star.* = .{ .rect = .{
            .x = rng.uintLessThanBiased(u16, display_size.w),
            .y = rng.uintLessThanBiased(u16, display_size.h),
            .w = w,
            .h = w,
        } };
    }
}

/// The main game loop.
export fn update() void {
    var button_buffer: [16]u8 = undefined;
    js.buttons(&button_buffer, button_buffer.len);
    const buttons: [2]*const Buttons = .{
        @ptrCast(&button_buffer[0]),
        @ptrCast(&button_buffer[8]),
    };

    for (&game.players, buttons) |*player, button| {
        const ship = player.ship.ptr();
        ship.input = .{
            .left = button.left,
            .right = button.right,
            .forward = button.b,
            .fire = button.a,
        };
        if (!ship.prev_input.forward and ship.input.forward) {
            ship.setAnimation(ship.accel);
        } else if (ship.prev_input.forward and !ship.input.forward) {
            ship.setAnimation(ship.still);
        }
        ship.prev_input = ship.input;
    }

    const dt = 1.0 / 60.0;

    for (game.ships.items) |*ship| {
        ship.pos.add(ship.vel.scaled(dt));

        // explode ships that reach 0 hp
        //if (ship.hp <= 0) {
        //    // spawn explosion here
        //    try decorations.append(.{
        //        .anim_playback = .{ .index = explosion_animation, .time_passed = 0 },
        //        .pos = ship.pos,
        //        .vel = ship.vel,
        //        .rotation = 0,
        //        .rotation_vel = 0,
        //        .duration = 100,
        //    });
        //    // delete ship and spawn it somewhere else
        //    ship.* = ranger_template;
        //    const new_angle = math.pi * 2 * std.crypto.random.float(f32);
        //    ship.pos = display_center.plus(V.unit(new_angle).scaled(500));
        //    continue;
        //}

        const rotate_input = // convert to 1.0 or -1.0
            @as(f32, @floatFromInt(@intFromBool(ship.input.right))) -
            @as(f32, @floatFromInt(@intFromBool(ship.input.left)));
        ship.rotation = @mod(
            ship.rotation + rotate_input * ship.rotation_vel * dt,
            2 * math.pi,
        );

        // convert to 1.0 or 0.0
        const thrust_input: f32 = @floatFromInt(@intFromBool(ship.input.forward));
        const thrust = V.unit(ship.rotation);
        ship.vel.add(thrust.scaled(thrust_input * ship.thrust * dt));

        const turret = &ship.turret;
        {
            turret.cooldown -= dt;
            if (ship.input.fire and turret.cooldown <= 0) {
                turret.cooldown = turret.cooldown_amount;
                //try bullets.append(.{
                //    .sprite = bullet_small,
                //    .pos = ship.pos.plus(V.unit(ship.rotation + turret.angle).scaled(turret.radius)),
                //    .vel = V.unit(ship.rotation).scaled(turret.bullet_speed).plus(ship.vel),
                //    .duration = turret.bullet_duration,
                //    .radius = 2,
                //    .damage = turret.bullet_damage,
                //});
            }
        }
    }

    display(dt);
}

fn display(dt: f32) void {
    for (game.stars) |star| {
        js.fillRect(star.rect);
    }

    for (game.ships.items) |*ship| {
        const sprite = game.assets.animate(&ship.anim_playback, dt);
        std.log.debug("pos = {any} size = {any}", .{ ship.pos, sprite.size });
        js.drawImage(
            sprite.index,
            .fromVec(ship.pos, sprite.size),
            // The ship asset images point up instead of to the right.
            ship.rotation + math.pi / 2.0,
        );

        // HP bar
        //if (ship.hp < ship.max_hp) {
        //    const health_bar_size: V = .{ .x = 32, .y = 4 };
        //    var start = ship.pos.minus(health_bar_size.scaled(0.5)).floored();
        //    start.y -= ship.radius + health_bar_size.y;
        //    sdlAssertZero(c.SDL_SetRenderDrawColor(renderer, 0xff, 0xff, 0xff, 0xff));
        //    sdlAssertZero(c.SDL_RenderFillRect(renderer, &sdlRect(
        //        start.minus(.{ .x = 1, .y = 1 }),
        //        health_bar_size.plus(.{ .x = 2, .y = 2 }),
        //    )));
        //    const hp_percent = ship.hp / ship.max_hp;
        //    if (hp_percent > 0.45) {
        //        sdlAssertZero(c.SDL_SetRenderDrawColor(renderer, 0x00, 0x94, 0x13, 0xff));
        //    } else {
        //        sdlAssertZero(c.SDL_SetRenderDrawColor(renderer, 0xe2, 0x00, 0x03, 0xff));
        //    }
        //    sdlAssertZero(c.SDL_RenderFillRect(renderer, &sdlRect(
        //        start,
        //        .{ .x = health_bar_size.x * hp_percent, .y = health_bar_size.y },
        //    )));
        //}
    }
}

const Sprite = struct {
    index: Index,
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

    fn loadSprite(a: *Assets, name: []const u8, size: V) !Sprite.Index {
        js.loadImage(name.ptr, name.len);
        const index: Sprite.Index = @enumFromInt(a.sprites.items.len);
        try a.sprites.append(gpa, .{
            .index = index,
            .pos = .{ .x = 0, .y = 0 },
            .size = size,
        });
        return @enumFromInt(a.sprites.items.len - 1);
    }
};
