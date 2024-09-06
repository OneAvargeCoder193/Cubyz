const std = @import("std");

const main = @import("root");

const vec = main.vec;
const Vec3f = vec.Vec3f;

const User = main.server.User;

pub const CommandError = error {
	NotEnoughArgs,
	ParseFailed
};

fn readNext(split: *std.mem.SplitIterator(u8, .scalar)) ?[]const u8 {
	while (split.next()) |arg| {
		if (arg.len != 0)
			return arg;
	}
	return null;
}

pub fn readInt(comptime T: type, split: *std.mem.SplitIterator(u8, .scalar)) CommandError!T {
	if (readNext(split)) |arg| {
		const f: T = std.fmt.parseInt(T, arg, 10) catch return CommandError.ParseFailed;
		return f;
	}
	return CommandError.NotEnoughArgs;
}

pub fn readFloat(comptime T: type, split: *std.mem.SplitIterator(u8, .scalar)) CommandError!T {
	if (readNext(split)) |arg| {
		const f: T = std.fmt.parseFloat(T, arg) catch return CommandError.ParseFailed;
		return f;
	}
	return CommandError.NotEnoughArgs;
}

pub fn readText(split: *std.mem.SplitIterator(u8, .scalar)) CommandError![]const u8 {
	if (readNext(split)) |arg| {
		return arg;
	}
	return CommandError.NotEnoughArgs;
}

const CoordAxis = enum (u2) {
	x = 0,
	y = 1,
	z = 2
};

pub fn readCoordFloat(comptime T: type, split: *std.mem.SplitIterator(u8, .scalar), axis: CoordAxis, source: *User) CommandError!T {
	if (readNext(split)) |arg| {
		var f: T = 0;

		var state: enum {
			None,
			RemoveFirstChar,
			NoNumber
		} = .None;

		if (arg[0] == '~') {
			f = source.player.pos[@intFromEnum(axis)];
			if (arg.len == 1) {
				state = .NoNumber;
			} else {
				state = .RemoveFirstChar;
			}
		}
		
		if (state == .RemoveFirstChar) {
			f += std.fmt.parseFloat(T, arg[1..]) catch return CommandError.ParseFailed;
		} else if (state == .None) {
			f += std.fmt.parseFloat(T, arg) catch return CommandError.ParseFailed;
		}
		return f;
	}
	return CommandError.NotEnoughArgs;
}

pub fn readCoordInt(comptime T: type, split: *std.mem.SplitIterator(u8, .scalar), axis: CoordAxis, source: *User) CommandError!T {
	if (readNext(split)) |arg| {
		var f: T = 0;

		var state: enum {
			None,
			RemoveFirstChar,
			NoNumber
		} = .None;

		if (arg[0] == '~') {
			f = @intFromFloat(@floor(source.player.pos[@intFromEnum(axis)]));
			if (arg.len == 1) {
				state = .NoNumber;
			} else {
				state = .RemoveFirstChar;
			}
		}

		if (state == .RemoveFirstChar) {
			f += std.fmt.parseInt(T, arg[1..], 10) catch return CommandError.ParseFailed;
		} else if (state == .None) {
			f += std.fmt.parseInt(T, arg, 10) catch return CommandError.ParseFailed;
		}
		return f;
	}
	return CommandError.NotEnoughArgs;
}