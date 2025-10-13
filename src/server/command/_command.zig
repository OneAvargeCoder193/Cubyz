const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const Command = struct {
	exec: union(enum) {
		func: *const fn(args: []const u8, source: *User) void,
		mod: *main.wasm.WasmInstance,
	},
	name: []const u8,
	description: []const u8,
	usage: []const u8,
};

pub var commands: std.StringHashMap(Command) = undefined;

pub fn init() void {
	commands = .init(main.globalAllocator.allocator);
	const commandList = @import("_list.zig");
	inline for(@typeInfo(commandList).@"struct".decls) |decl| {
		commands.put(decl.name, .{
			.name = decl.name,
			.description = @field(commandList, decl.name).description,
			.usage = @field(commandList, decl.name).usage,
			.exec = .{.func = &@field(commandList, decl.name).execute},
		}) catch unreachable;
		std.log.debug("Registered command: '/{s}'", .{decl.name});
	}
	for(main.modding.mods.items) |mod| {
		mod.invoke("registerCommands", &.{}, &.{}) catch {};
	}
}

pub fn deinit() void {
	commands.deinit();
}

pub fn execute(msg: []const u8, source: *User) void {
	const end = std.mem.indexOfScalar(u8, msg, ' ') orelse msg.len;
	const command = msg[0..end];
	if(commands.get(command)) |cmd| {
		source.sendMessage("#00ff00Executing Command /{s}", .{msg});
		switch(cmd.exec) {
			.func => |exec| {
				exec(msg[@min(end + 1, msg.len)..], source);
			},
			.mod => |instance| {
				const memory = main.wasm.c.wasm_memory_data(instance.memory);
				const nameLoc = instance.alloc(command.len) catch unreachable;
				defer instance.free(nameLoc, command.len) catch unreachable;
				const args = msg[@min(end + 1, msg.len)..];
				const argLoc = instance.alloc(args.len) catch unreachable;
				defer instance.free(argLoc, args.len) catch unreachable;
				@memcpy(memory[nameLoc..nameLoc + command.len], command);
				@memcpy(memory[argLoc..argLoc + args.len], args);
				var argList = [_]main.wasm.c.wasm_val_t{
					.{.kind = main.wasm.c.WASM_I32, .of = .{.@"i32" = @intCast(nameLoc)}},
					.{.kind = main.wasm.c.WASM_I32, .of = .{.@"i32" = @intCast(command.len)}},
					.{.kind = main.wasm.c.WASM_I32, .of = .{.@"i32" = @intCast(argLoc)}},
					.{.kind = main.wasm.c.WASM_I32, .of = .{.@"i32" = @intCast(args.len)}},
					.{.kind = main.wasm.c.WASM_I32, .of = .{.@"i32" = @intCast(source.id)}},
				};
				var retList = [0]main.wasm.c.wasm_val_t{};
				instance.currentSide = .server;
				instance.invoke("executeCommand", &argList, &retList) catch unreachable;
			}
		}
	} else {
		source.sendMessage("#ff0000Unrecognized Command \"{s}\"", .{command});
	}
}

pub fn registerCommandWasm(env: ?*anyopaque, args: [*c]const main.wasm.c.wasm_val_vec_t, _: [*c]main.wasm.c.wasm_val_vec_t) callconv(.c) ?*main.wasm.c.wasm_trap_t {
	const instance = @as(*main.wasm.WasmInstance.Env, @ptrCast(@alignCast(env.?))).instance;
	const nameStart: usize = @intCast(args.*.data[0].of.i32);
	const nameLen: usize = @intCast(args.*.data[1].of.i32);
	const descriptionStart: usize = @intCast(args.*.data[2].of.i32);
	const descriptionLen: usize = @intCast(args.*.data[3].of.i32);
	const usageStart: usize = @intCast(args.*.data[4].of.i32);
	const usageLen: usize = @intCast(args.*.data[5].of.i32);
	const memory = main.wasm.c.wasm_memory_data(instance.memory);
	const name = memory[nameStart..nameStart + nameLen];
	const description = memory[descriptionStart..descriptionStart + descriptionLen];
	const usage = memory[usageStart..usageStart + usageLen];
	commands.put(name, .{
		.name = name,
		.description = description,
		.usage = usage,
		.exec = .{.mod = instance},
	}) catch unreachable;
	std.log.debug("Registered command: '/{s}'", .{name});
	return null;
}