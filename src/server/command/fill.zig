const std = @import("std");

const main = @import("root");
const User = main.server.User;

const blocks = main.blocks;

const cmd_utils = @import("cmd_utils.zig");

pub const description = "Fill an area of blocks.";
pub const usage = "/fill <x1> <y1> <z1> <x2> <y2> <z2> <block>";

pub fn execute(args: []const u8, source: *User) void {
	var split = std.mem.splitScalar(u8, args, ' ');

	const x1 = cmd_utils.readCoordInt(i32, &split, .x, source) catch |err| switch (err) {
		cmd_utils.CommandError.NotEnoughArgs => {
			source.sendMessage("#ff0000Too few arguments for command /fill");
			return;
		},
		cmd_utils.CommandError.ParseFailed => {
			source.sendMessage("#ff0000Failed to parse first x coordinate");
			return;
		}
	};

	const y1 = cmd_utils.readCoordInt(i32, &split, .y, source) catch |err| switch (err) {
		cmd_utils.CommandError.NotEnoughArgs => {
			source.sendMessage("#ff0000Too few arguments for command /fill");
			return;
		},
		cmd_utils.CommandError.ParseFailed => {
			source.sendMessage("#ff0000Failed to parse first y coordinate");
			return;
		}
	};

	const z1 = cmd_utils.readCoordInt(i32, &split, .z, source) catch |err| switch (err) {
		cmd_utils.CommandError.NotEnoughArgs => {
			source.sendMessage("#ff0000Too few arguments for command /fill");
			return;
		},
		cmd_utils.CommandError.ParseFailed => {
			source.sendMessage("#ff0000Failed to parse first z coordinate");
			return;
		}
	};

	const x2 = cmd_utils.readCoordInt(i32, &split, .x, source) catch |err| switch (err) {
		cmd_utils.CommandError.NotEnoughArgs => {
			source.sendMessage("#ff0000Too few arguments for command /fill");
			return;
		},
		cmd_utils.CommandError.ParseFailed => {
			source.sendMessage("#ff0000Failed to parse second x coordinate");
			return;
		}
	};

	const y2 = cmd_utils.readCoordInt(i32, &split, .y, source) catch |err| switch (err) {
		cmd_utils.CommandError.NotEnoughArgs => {
			source.sendMessage("#ff0000Too few arguments for command /fill");
			return;
		},
		cmd_utils.CommandError.ParseFailed => {
			source.sendMessage("#ff0000Failed to parse second y coordinate");
			return;
		}
	};

	const z2 = cmd_utils.readCoordInt(i32, &split, .z, source) catch |err| switch (err) {
		cmd_utils.CommandError.NotEnoughArgs => {
			source.sendMessage("#ff0000Too few arguments for command /fill");
			return;
		},
		cmd_utils.CommandError.ParseFailed => {
			source.sendMessage("#ff0000Failed to parse second z coordinate");
			return;
		}
	};

	const blockString = cmd_utils.readText(&split) catch |err| switch (err) {
		cmd_utils.CommandError.NotEnoughArgs => {
			source.sendMessage("#ff0000Too few arguments for command /fill");
			return;
		},
		cmd_utils.CommandError.ParseFailed => unreachable
	};

	const block: u16 = blocks.getByID(blockString);
	const b = blocks.Block.fromInt(block);

	var x: i32 = x1;
	while (x < x2) : (x += 1) {
		var y: i32 = y1;
		while (y < y2) : (y += 1) {
			var z: i32 = z1;
			while (z < z2) : (z += 1) {
				main.server.world.?.updateBlock(x, y, z, b);
			}
		}
	}
}