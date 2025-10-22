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
			.name = main.globalAllocator.dupe(u8, decl.name),
			.description = main.globalAllocator.dupe(u8, @field(commandList, decl.name).description),
			.usage = main.globalAllocator.dupe(u8, @field(commandList, decl.name).usage),
			.exec = .{.func = &@field(commandList, decl.name).execute},
		}) catch unreachable;
		std.log.debug("Registered command: '/{s}'", .{decl.name});
	}
	for(main.modding.mods.items) |mod| {
		mod.invoke("registerCommands", &.{}, &.{}) catch {};
	}
}

pub fn deinit() void {
	var iter = commands.valueIterator();
	while(iter.next()) |command| {
		main.globalAllocator.free(command.name);
		main.globalAllocator.free(command.description);
		main.globalAllocator.free(command.usage);
	}
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
				const args = msg[@min(end + 1, msg.len)..];
				const nameLoc, const nameLen = instance.createWasmFromSlice(command);
				defer instance.free(@intCast(nameLoc.of.i32), command.len) catch unreachable;
				const argLoc, const argLen = instance.createWasmFromSlice(args);
				defer instance.free(@intCast(argLoc.of.i32), args.len) catch unreachable;
				var argList = [_]main.wasm.c.wasm_val_t{
					nameLoc,
					nameLen,
					argLoc,
					argLen,
					.{.kind = main.wasm.c.WASM_I32, .of = .{.i32 = @intCast(source.id)}},
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
	const name = instance.createSliceFromWasm(main.globalAllocator, args.*.data[0], args.*.data[1]) catch unreachable;
	const description = instance.createSliceFromWasm(main.globalAllocator, args.*.data[2], args.*.data[3]) catch unreachable;
	const usage = instance.createSliceFromWasm(main.globalAllocator, args.*.data[3], args.*.data[4]) catch unreachable;
	commands.put(name, .{
		.name = name,
		.description = description,
		.usage = usage,
		.exec = .{.mod = instance},
	}) catch unreachable;
	std.log.debug("Registered command: '/{s}'", .{name});
	return null;
}