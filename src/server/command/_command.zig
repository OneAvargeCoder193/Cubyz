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
		commands.put(main.globalAllocator.dupe(u8, decl.name), .{
			.name = main.globalAllocator.dupe(u8, decl.name),
			.description = main.globalAllocator.dupe(u8, @field(commandList, decl.name).description),
			.usage = main.globalAllocator.dupe(u8, @field(commandList, decl.name).usage),
			.exec = .{.func = &@field(commandList, decl.name).execute},
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
		switch(cmd.exec) {
			.func => |exec| {
				exec(msg[@min(end + 1, msg.len)..], source);
			},
			.mod => |instance| {
				const args = msg[@min(end + 1, msg.len)..];
				instance.currentSide = .server;
				instance.invoke("executeCommand", .{command, args, source.id}, void) catch unreachable;
			}
		}
	} else {
		source.sendMessage("#ff0000Unrecognized Command \"{s}\"", .{command});
	}
}

pub fn registerCommandWasm(instance: *main.wasm.WasmInstance, name: []const u8, description: []const u8, usage: []const u8) void {
	commands.put(main.globalAllocator.dupe(u8, name), .{
		.name = main.globalAllocator.dupe(u8, name),
		.description = main.globalAllocator.dupe(u8, description),
		.usage = main.globalAllocator.dupe(u8, usage),
		.exec = .{.mod = instance},
	}) catch unreachable;
	std.log.debug("Registered command: '/{s}'", .{name});
}