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
		std.debug.print("{s}\n", .{entry.name});
	}
}

pub fn deinit() void {
	mods.deinit();
}