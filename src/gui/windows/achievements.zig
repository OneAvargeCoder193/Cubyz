const std = @import("std");

const main = @import("main");
const Vec2f = main.vec.Vec2f;
const graphics = main.graphics;
const c = graphics.c;
const Image = graphics.Image;
const FrameBuffer = graphics.FrameBuffer;
const ZonElement = main.ZonElement;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Icon = @import("../components/Icon.zig");
const Button = @import("../components/Button.zig");
const VerticalList = @import("../components/VerticalList.zig");
const HorizontalList = @import("../components/HorizontalList.zig");

pub var window: GuiWindow = GuiWindow{
	.contentSize = Vec2f{128, 256},
	.closeIfMouseIsGrabbed = true,
};

pub const Achievement = struct {
	name: []const u8,
	parent: ?usize,
	depth: usize = 0,
	yOffset: f32 = 0,
	children: main.List(usize),
};

var achievements: []Achievement = undefined;
var maxDepth: usize = 0;
var maxYOffset: f32 = 0;
var width: u31 = undefined;
var height: u31 = undefined;

fn generateNodes(_seed: u64, num: usize) void {
	var seed = _seed;
	achievements = main.globalAllocator.alloc(Achievement, num);
	for (0..num) |i| {
		const name = std.fmt.allocPrint(main.globalAllocator.allocator, "{d}", .{i}) catch undefined;
		const parent: ?usize = if(i == 0) null else main.random.nextInt(usize, &seed) % i;
		if(parent) |parentNode| {
			achievements[parentNode].children.append(i);
		}
		achievements[i] = .{
			.name = name,
			.parent = parent,
			.children = .init(main.globalAllocator),
		};
	}
}

fn assignPositions(nodeIndex: usize, depth: usize, yOffset: f32) f32 {
	const node = &achievements[nodeIndex];
	maxDepth = @max(maxDepth, depth);
	defer maxYOffset = @max(maxYOffset, node.yOffset);
	node.depth = depth;
	if(node.children.items.len == 0) {
		node.yOffset = yOffset;
		return 1;
	}
	var totalHeight: f32 = 0;
	for(node.children.items) |childIndex| {
		totalHeight += assignPositions(childIndex, depth + 1, yOffset + totalHeight);
	}
	const firstY = achievements[node.children.items[0]].yOffset;
	const lastY = achievements[node.children.items[node.children.items.len - 1]].yOffset;
	node.yOffset = (firstY + lastY) / 2.0;
	return totalHeight;
}

pub fn init() void {
	generateNodes(0, 1000);
	maxDepth = 0;
	maxYOffset = 0;
	_ = assignPositions(0, 0,0);
	width = @intCast(maxDepth * 64 + 64);
	height = @intFromFloat(maxYOffset * 64 + 64);
}

pub fn deinit() void {
	for(achievements) |achievement| {
		main.globalAllocator.free(achievement.name);
		achievement.children.deinit();
	}
	main.globalAllocator.free(achievements);
}

var fbo: FrameBuffer = undefined;

const padding: f32 = 8;

var list: *VerticalList = undefined;

pub fn onOpen() void {
	list = VerticalList.init(.{padding, 16 + padding}, 256, 16);
	const horizontal = HorizontalList.init();
	
	horizontal.add(Icon.init(.{0, 0}, .{@floatFromInt(width), @floatFromInt(height)}, Button.pressedTextures.texture, true));
	horizontal.finish(.center);

	list.add(horizontal);
	list.finish(.center);
	
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn render() void {
	const oldTranslation = graphics.draw.setTranslation(list.pos);
	defer graphics.draw.restoreTranslation(oldTranslation);
	const oldClip = graphics.draw.setClip(list.size);
	defer graphics.draw.restoreClip(oldClip);
	var shiftedPos = list.pos;
	if(list.scrollBarEnabled) {
		const diff = list.childrenHeight - list.maxHeight;
		shiftedPos[1] -= diff*list.scrollBar.currentState;
	}
	_ = graphics.draw.setTranslation(shiftedPos - list.pos);
	for(achievements) |achievement| {
		graphics.draw.setColor(0xffff0000);
		// graphics.draw.rect(.{@floatFromInt(achievement.depth), achievement.yOffset}, .{1, 1});
		graphics.draw.rect(.{@floatFromInt(achievement.depth * 64), achievement.yOffset * 64}, .{32, 32});
		
		if(achievement.parent) |parentIndex| {
			const parentNode = achievements[parentIndex];
			graphics.draw.setColor(0xff000000);
			graphics.draw.line(.{@floatFromInt(parentNode.depth * 64 + 32), parentNode.yOffset * 64 + 16}, .{@floatFromInt(parentNode.depth * 64 + 48), parentNode.yOffset * 64 + 16});
			graphics.draw.line(.{@floatFromInt(achievement.depth * 64 - 16), achievement.yOffset * 64 + 16}, .{@floatFromInt(achievement.depth * 64), achievement.yOffset * 64 + 16});
			graphics.draw.line(.{@floatFromInt(parentNode.depth * 64 + 48), parentNode.yOffset * 64 + 16}, .{@floatFromInt(achievement.depth * 64 - 16), achievement.yOffset * 64 + 16});
		}
	}
}

pub fn onClose() void {
	fbo.deinit();
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}
