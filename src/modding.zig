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
	try mod.addImport("registerCommandImpl", &main.server.command.registerCommandWasm);
	try mod.addImport("sendMessageImpl", &main.server.sendRawMessageWasm);
	try mod.addImport("addHealthImpl", &main.items.Inventory.Sync.addHealthWasm);
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