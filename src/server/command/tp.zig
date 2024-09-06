const std = @import("std");

const main = @import("root");
const User = main.server.User;

const cmd_utils = @import("cmd_utils.zig");

pub const description = "Teleport to location.";
pub const usage = "/tp <x> <y> <z>";

pub fn execute(args: []const u8, source: *User) void {
	var split = std.mem.splitScalar(u8, args, ' ');

	const x = cmd_utils.readCoordFloat(f64, &split, .x, source) catch |err| switch (err) {
		cmd_utils.CommandError.NotEnoughArgs => {
			source.sendMessage("#ff0000Too few arguments for command /tp");
			return;
		},
		cmd_utils.CommandError.ParseFailed => {
			source.sendMessage("#ff0000Failed to parse x coordinate");
			return;
		}
	};

	const y = cmd_utils.readCoordFloat(f64, &split, .y, source) catch |err| switch (err) {
		cmd_utils.CommandError.NotEnoughArgs => {
			source.sendMessage("#ff0000Too few arguments for command /tp");
			return;
		},
		cmd_utils.CommandError.ParseFailed => {
			source.sendMessage("#ff0000Failed to parse y coordinate");
			return;
		}
	};

	const z = cmd_utils.readCoordFloat(f64, &split, .z, source) catch |err| switch (err) {
		cmd_utils.CommandError.NotEnoughArgs => {
			source.sendMessage("#ff0000Too few arguments for command /tp");
			return;
		},
		cmd_utils.CommandError.ParseFailed => {
			source.sendMessage("#ff0000Failed to parse z coordinate");
			return;
		}
	};

	main.network.Protocols.genericUpdate.sendTPCoordinates(source.conn, .{x, y, z});
}