const std = @import("std");

const main = @import("main");
const wasm = main.wasm;
const c = wasm.c;

pub var mods: main.ListUnmanaged(*wasm.WasmInstance) = .{};

pub fn init() void {
	const modDir = main.files.cwd().openIterableDir("mods") catch |err| {
		std.log.err("Failed to open mods folder: {}\n", .{err});
		return;
	};
	var iter = modDir.iterate();
	while(iter.next() catch |err| {
		std.log.err("Failed to iterate mods folder: {}\n", .{err});
		return;
	}) |entry| {
		if(entry.kind != .file) continue;
		if(!std.ascii.endsWithIgnoreCase(entry.name, ".wasm")) continue;

		const file = modDir.openFile(entry.name) catch |err| {
			std.log.err("Failed to open mod {s}: {}\n", .{entry.name, err});
			continue;
		};
		defer file.close();
		const mod = loadMod(file) catch |err| {
			std.log.err("Failed to load mod: {}\n", .{err});
			continue;
		};
		mods.append(main.globalAllocator, mod);
	}
}

fn loadMod(file: std.fs.File) !*wasm.WasmInstance {
	const mod = wasm.WasmInstance.init(main.globalAllocator, file) catch unreachable;
	errdefer mod.deinit(main.globalAllocator);
	mod.addImport("registerCommandImpl", main.server.command.registerCommandWasm) catch {};
	mod.addImport("sendMessageImpl", main.server.sendRawMessageWasm) catch {};
	mod.addImport("addHealthImpl", main.items.Inventory.Sync.addHealthWasm) catch {};
	mod.addImport("setSelectedPosition1Impl", main.server.setSelectedPosition1Wasm) catch {};
	mod.addImport("setSelectedPosition2Impl", main.server.setSelectedPosition2Wasm) catch {};
	mod.addImport("getSelectedPosition1Impl", main.server.getSelectedPosition1Wasm) catch {};
	mod.addImport("getSelectedPosition2Impl", main.server.getSelectedPosition2Wasm) catch {};
	mod.addImport("getPositionImpl", main.server.getPositionWasm) catch {};
	mod.addImport("setPositionImpl", main.server.setPositionWasm) catch {};
	mod.addImport("parseBlockImpl", main.blocks.parseBlockWasm) catch {};
	mod.addImport("setBlockImpl", main.server.world_zig.setBlockWasm) catch {};
	mod.instantiate() catch |err| {
		std.log.err("Failed to instantiate module: {}\n", .{err});
		return err;
	};
	return mod;
}

pub fn deinit() void {
	for(mods.items) |mod| {
		mod.deinit(main.globalAllocator);
	}
	mods.deinit(main.globalAllocator);
}