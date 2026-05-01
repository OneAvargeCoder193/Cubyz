const std = @import("std");
const main = @import("main.zig");
const wasi = main.wasi;
const wasm = main.wasm;
const wasmer = main.wasmer;

pub var engine: *wasm.Engine = undefined;
pub var store: *wasm.Store = undefined;
pub var module: *wasm.Module = undefined;
var env: wasm.InstanceEnv = undefined;

fn registerAssetImpl(_: *wasm.InstanceEnv, namePtr: [*]u8, nameLen: u32, contentPtr: [*]u8, contentLen: u32) void {
	std.debug.print("{s} {s}\n", .{namePtr[0..nameLen], contentPtr[0..contentLen]});
}

fn sendMessageImpl(_: *wasm.InstanceEnv, index: u32, message: [*]u8, messageLen: u32) void {
	const user = main.server.getUserByIndexAndIncreaseRefCount(index);
	defer user.?.decreaseRefCount();
	user.?.sendRawMessage(message[0..messageLen]);
}

fn registerCommandImpl(
	instanceEnv: *wasm.InstanceEnv,
	funcName: [*]u8, funcNameLen: u32,
	name: [*]u8, nameLen: u32,
	description: [*]u8, descriptionLen: u32,
	usage: [*]u8, usageLen: u32
) void {
	main.server.command.registerCommand(
		instanceEnv, instanceEnv.instance.getExportFunc(module, funcName[0..funcNameLen]) orelse @panic("callback doesnt exist in wasm"),
		name[0..nameLen], description[0..descriptionLen], usage[0..usageLen]
	);
}

pub fn ModdableFunc(comptime FuncType: type, wasmWrapper: anytype) type {
	return union(enum) {
		native: *const FuncType,
		modded: struct {env: *wasm.InstanceEnv, func: *wasm.Func},
		
		pub fn call(self: @This(), args: anytype) @typeInfo(FuncType).@"fn".return_type.? {
			switch(self) {
				.native => |func| {
					return @call(.auto, func, args);
				},
				.modded => |data| {
					return @call(.auto, wasmWrapper, .{data.env, data.func} ++ args);
				}
			}
		}
	};
}

pub fn init() !void {
	engine = try wasm.Engine.init();
	store = try wasm.Store.init(engine);

	const wasmBytes = main.files.cwd().read(main.globalAllocator, "mods/Modding.wasm") catch @panic("mod not found");
	defer main.globalAllocator.free(wasmBytes);
	
	module = try wasmer.Module.init(store, wasmBytes);

	std.log.info("instantiating module...", .{});

	env.instance = try wasmer.Instance.init(store, module, .{
		.registerAssetImpl = try wasm.Func.init(store, registerAssetImpl, &env),
		.registerCommandImpl = try wasm.Func.init(store, registerCommandImpl, &env),
		.sendMessageImpl = try wasm.Func.init(store, sendMessageImpl, &env),
	});

	std.log.info("retrieving exports...", .{});

    env.memory = env.instance.getExportMem(module, "memory") orelse {
        std.log.err("failed to retrieve \"memory\" export from instance", .{});
        return error.ExportNotFound;
    };

	const loadAssets: ?*wasm.Func = env.instance.getExportFunc(module, "loadAssets") orelse null;
	defer if(loadAssets) |loadAssetsFn| loadAssetsFn.deinit();
	if(loadAssets) |loadAssetsFn| loadAssetsFn.call(void, .{}) catch {};

	const registerCommands: ?*wasm.Func = env.instance.getExportFunc(module, "registerCommands") orelse null;
	defer if(registerCommands) |registerCommandsFn| registerCommandsFn.deinit();
	if(registerCommands) |registerCommandsFn| registerCommandsFn.call(void, .{}) catch {};
}

pub fn deinit() void {
	env.memory.deinit();
	env.instance.deinit();
	module.deinit();
	store.deinit();
	engine.deinit();
}