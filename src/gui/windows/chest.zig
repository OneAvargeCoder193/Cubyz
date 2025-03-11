const std = @import("std");

const main = @import("root");
const Player = main.game.Player;
const ItemStack = main.items.ItemStack;
const Vec2f = main.vec.Vec2f;
const Texture = main.graphics.Texture;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = GuiComponent.Button;
const HorizontalList = GuiComponent.HorizontalList;
const VerticalList = GuiComponent.VerticalList;
const ItemSlot = GuiComponent.ItemSlot;

const hotbar = @import("hotbar.zig");

pub var window = GuiWindow{
	.relativePosition = .{
		.{.attachedToWindow = .{.reference = &hotbar.window, .selfAttachmentPoint = .middle, .otherAttachmentPoint = .middle}},
		.{.attachedToWindow = .{.reference = &hotbar.window, .selfAttachmentPoint = .upper, .otherAttachmentPoint = .lower}},
	},
	.contentSize = Vec2f{64*10, 64*3},
	.scale = 0.75,
	.closeIfMouseIsGrabbed = true,
};

const padding: f32 = 8;

var itemSlots: main.List(*ItemSlot) = undefined;

pub fn init() void {
	itemSlots = .init(main.globalAllocator);
}

pub fn deinit() void {
	itemSlots.deinit();
}

pub var openInventory: ?main.items.Inventory = null;

pub fn onOpen() void {
	const blockPos = main.renderer.MeshSelection.selectedBlockPos.?;
	openInventory = main.renderer.mesh_storage.getInventory(blockPos[0], blockPos[1], blockPos[2]);

	const list = VerticalList.init(.{padding, padding + 16}, 300, 0);
	// Some miscellanious slots and buttons:
	// TODO: armor slots, backpack slot + stack-based backpack inventory, other items maybe?
	for(0..1) |y| {
		const row = HorizontalList.init();
		for(0..10) |x| {
			const index: usize = y*10 + x;
			const slot = ItemSlot.init(.{0, 0}, openInventory.?, @intCast(index), .default, .normal);
			itemSlots.append(slot);
			row.add(slot);
		}
		list.add(row);
	}
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	itemSlots.clearRetainingCapacity();
	if(window.rootComponent) |*comp| {
		comp.deinit();
		window.rootComponent = null;
	}
}
