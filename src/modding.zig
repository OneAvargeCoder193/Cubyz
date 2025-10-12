const std = @import("std");

const main = @import("main");
const wasm = main.wasm;
const c = wasm.c;

var mods: std.StringHashMap(wasm.WasmInstance) = undefined;

pub fn init() void {
	mods = .init(main.globalAllocator.allocator);
	const modDir = main.files.cwd().openIterableDir("mods") catch |err| {
		std.log.err("Failed to open mods folder: {}\n", .{err});
		return;
	};
	var iter = modDir.iterate();
	while(iter.next() catch |err| {
		std.log.err("Failed to iterate mods folder: {}\n", .{err});
		return;
	}) |entry| {
		const file = modDir.openFile(entry) catch |err| {
			std.log.err("Failed to open mod {s}: {}\n", .{entry.name, err});
			continue;
		};
		defer file.close();
		const mod = wasm.WasmInstance.init(main.globalAllocator, file) catch unreachable;
		defer mod.deinit(main.globalAllocator);
		mod.addImport("registerCommandImpl", &[_]?*c.wasm_valtype_t{
			c.wasm_valtype_new_i32(),
			c.wasm_valtype_new_i32(),
			c.wasm_valtype_new_i32(),
			c.wasm_valtype_new_i32(),
			c.wasm_valtype_new_i32(),
			c.wasm_valtype_new_i32(),
		}, &.{}, &main.server.command.registerCommandWasm);
		mod.addImport("sendMessageUnformatted", &[_]?*c.wasm_valtype_t{
			c.wasm_valtype_new_i32(),
			c.wasm_valtype_new_i32(),
			c.wasm_valtype_new_i32(),
		}, &.{}, &main.server.sendRawMessageWasm);
		mod.addImport("addHealthImpl", &[_]?*c.wasm_valtype_t{
			c.wasm_valtype_new_i32(),
			c.wasm_valtype_new_f32(),
			c.wasm_valtype_new_i32(),
		}, &.{}, &main.items.Inventory.Sync.addHealthWasm);
		mod.instantiate() catch |err| {
			std.log.err("Failed to instantiate module: {}\n", .{err});
			return;
		};
	}
}

pub fn deinit() void {
	mods.deinit();
}