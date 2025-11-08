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
	for(mods.items) |mod| {
		mod.invoke("init", .{}, void) catch {};
	}
}

fn loadMod(file: std.fs.File) !*wasm.WasmInstance {
	const mod = wasm.WasmInstance.init(main.globalAllocator, file) catch unreachable;
	errdefer mod.deinit(main.globalAllocator);
	// Miscellaneous functions
	mod.addImport("registerCommandImpl", main.server.command.registerCommandWasm) catch {};
	mod.addImport("sendMessageImpl", main.server.sendRawMessageWasm) catch {};
	mod.addImport("registerAssetImpl", main.server.world_zig.registerAssetWasm) catch {};
	mod.addImport("registerCallbackImpl", main.callbacks.registerCallbackWasm) catch {};

	// Player related functions
	mod.addImport("addHealthImpl", main.items.Inventory.Sync.addHealthWasm) catch {};
	mod.addImport("setSelectedPosition1Impl", main.server.setSelectedPosition1Wasm) catch {};
	mod.addImport("setSelectedPosition2Impl", main.server.setSelectedPosition2Wasm) catch {};
	mod.addImport("getSelectedPosition1Impl", main.server.getSelectedPosition1Wasm) catch {};
	mod.addImport("getSelectedPosition2Impl", main.server.getSelectedPosition2Wasm) catch {};
	mod.addImport("getPositionImpl", main.server.getPositionWasm) catch {};
	mod.addImport("setPositionImpl", main.server.setPositionWasm) catch {};

	// Client side functions
	mod.addImport("showMessageImpl", main.gui.windowlist.chat.showMessageWasm) catch {};

	// World related functions
	mod.addImport("parseBlockImpl", main.blocks.parseBlockWasm) catch {};
	mod.addImport("modelIndexStartImpl", main.blocks.modelIndexStartWasm) catch {};
	mod.addImport("setBlockImpl", main.server.world_zig.setBlockWasm) catch {};
	mod.addImport("getBlockImpl", main.server.world_zig.getBlockWasm) catch {};

	// Rotation mode related functions
	mod.addImport("registerRotationModeImpl", main.rotation.registerRotationModeWasm) catch {};
	mod.addImport("modelInitImpl", main.models.modelInitWasm) catch {};
	mod.addImport("getModelFromIdImpl", main.models.getModelFromIdWasm) catch {};
	mod.addImport("getRawFacesImpl", main.models.getRawFacesWasm) catch {};

	// Gui window related functions
	mod.addImport("registerWindowImpl", main.gui.registerWindowWasm) catch {};
	mod.addImport("setRootComponentImpl", main.gui.setRootComponentWasm) catch {};
	mod.addImport("getRootComponentImpl", main.gui.getRootComponentWasm) catch {};
	mod.addImport("openWindowImpl", main.gui.openWindowWasm) catch {};
	mod.addImport("closeWindowImpl", main.gui.closeWindowWasm) catch {};

	// Base gui component functions
	mod.addImport("getComponentTypeImpl", main.gui.getComponentTypeWasm) catch {};
	mod.addImport("guiComponentPosImpl", main.gui.GuiComponent.guiComponentPosWasm) catch {};
	mod.addImport("guiComponentSizeImpl", main.gui.GuiComponent.guiComponentSizeWasm) catch {};
	mod.addImport("guiComponentDeinitImpl", main.gui.deinitComponentWasm) catch {};

	// Graphics functions
	mod.addImport("initTextureFromFileImpl", main.graphics.initTextureFromFileWasm) catch {};
	mod.addImport("deinitTextureImpl", main.graphics.deinitTextureWasm) catch {};

	// Individual gui component functions
	mod.addImport("initTextButtonImpl", main.gui.GuiComponent.Button.initTextWasm) catch {};
	mod.addImport("initIconButtonImpl", main.gui.GuiComponent.Button.initIconWasm) catch {};

	mod.addImport("initCheckBoxImpl", main.gui.GuiComponent.CheckBox.initWasm) catch {};

	mod.addImport("initIconImpl", main.gui.GuiComponent.Icon.initWasm) catch {};

	mod.addImport("initLabelImpl", main.gui.GuiComponent.Label.initWasm) catch {};

	mod.addImport("initTextInputImpl", main.gui.GuiComponent.TextInput.initWasm) catch {};
	mod.addImport("clearTextInputImpl", main.gui.GuiComponent.TextInput.clearWasm) catch {};
	mod.addImport("setTextInputImpl", main.gui.GuiComponent.TextInput.setWasm) catch {};

	mod.addImport("initVerticalListImpl", main.gui.GuiComponent.VerticalList.initWasm) catch {};
	mod.addImport("addVerticalListImpl", main.gui.GuiComponent.VerticalList.addWasm) catch {};
	mod.addImport("finishVerticalListImpl", main.gui.GuiComponent.VerticalList.finishWasm) catch {};
	mod.instantiate() catch |err| {
		std.log.err("Failed to instantiate module: {}\n", .{err});
		return err;
	};
	return mod;
}

pub fn deinit() void {
	for(mods.items) |mod| {
		mod.invoke("deinit", .{}, void) catch {};
	}
	for(mods.items) |mod| {
		mod.deinit(main.globalAllocator);
	}
	mods.deinit(main.globalAllocator);
}