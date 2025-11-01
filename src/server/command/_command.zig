const std = @import("std");

const main = @import("main");
const User = main.server.User;

pub const Command = struct {
	const Exec = main.wasm.ModdableFunction(fn(args: []const u8, source: *User) void, struct {
		fn wasmWrapper(instance: *main.wasm.WasmInstance, func: *main.wasm.c.wasm_func_t, args: anytype) void {
			instance.currentSide = .server;
			instance.invokeFunc(func, .{args[0], args[1].id}, void) catch {};
		}
	}.wasmWrapper);

	exec: Exec,
	name: []const u8,
	description: []const u8,
	usage: []const u8,
};

pub var commands: std.StringHashMap(Command) = undefined;

pub fn init() void {
	commands = .init(main.globalAllocator.allocator);
	const commandList = @import("_list.zig");
	inline for(@typeInfo(commandList).@"struct".decls) |decl| {
		commands.put(main.globalAllocator.dupe(u8, decl.name), .{
			.name = main.globalAllocator.dupe(u8, decl.name),
			.description = main.globalAllocator.dupe(u8, @field(commandList, decl.name).description),
			.usage = main.globalAllocator.dupe(u8, @field(commandList, decl.name).usage),
			.exec = .initFromCode(&@field(commandList, decl.name).execute),
		}) catch unreachable;
		std.log.debug("Registered command: '/{s}'", .{decl.name});
	}
	for(main.modding.mods.items) |mod| {
		mod.invoke("registerCommands", .{}, void) catch {};
	}
}

pub fn deinit() void {
	var iter = commands.iterator();
	while(iter.next()) |command| {
		main.globalAllocator.free(command.value_ptr.*.name);
		main.globalAllocator.free(command.value_ptr.*.description);
		main.globalAllocator.free(command.value_ptr.*.usage);
		main.globalAllocator.free(command.key_ptr.*);
	}
	commands.deinit();
}

pub fn execute(msg: []const u8, source: *User) void {
	const end = std.mem.indexOfScalar(u8, msg, ' ') orelse msg.len;
	const command = msg[0..end];
	if(commands.get(command)) |cmd| {
		source.sendMessage("#00ff00Executing Command /{s}", .{msg});
		cmd.exec.invoke(.{msg[@min(end + 1, msg.len)..], source});
	} else {
		source.sendMessage("#ff0000Unrecognized Command \"{s}\"", .{command});
	}
}

pub fn registerCommandWasm(instance: *main.wasm.WasmInstance, funcName: []const u8, name: []const u8, description: []const u8, usage: []const u8) void {
	commands.put(main.globalAllocator.dupe(u8, name), .{
		.name = main.globalAllocator.dupe(u8, name),
		.description = main.globalAllocator.dupe(u8, description),
		.usage = main.globalAllocator.dupe(u8, usage),
		.exec = .initFromWasm(instance, funcName),
	}) catch unreachable;
	std.log.debug("Registered command: '/{s}'", .{name});
}