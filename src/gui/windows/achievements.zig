const std = @import("std");

const main = @import("main");
const Vec2f = main.vec.Vec2f;
const graphics = main.graphics;
const c = graphics.c;
const ZonElement = main.ZonElement;
const achievements = main.achievements;
const Achievement = achievements.Achievement;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Icon = @import("../components/Icon.zig");
const Button = @import("../components/Button.zig");
const NoLayoutList = @import("../components/NoLayoutList.zig");
const HorizontalList = @import("../components/HorizontalList.zig");

pub var window: GuiWindow = GuiWindow{
	.contentSize = Vec2f{128, 256},
	.closeIfMouseIsGrabbed = true,
};

pub const AchievementNode = struct {
	achievement: Achievement,
	depth: u32 = 0,
	yOffset: f32 = 0,
	children: main.List(usize),
};

var achievementNodes: []AchievementNode = undefined;
var width: u31 = undefined;
var height: u31 = undefined;

fn generateNodes() void {
	achievementNodes = main.globalAllocator.alloc(AchievementNode, achievements.achievementCount());
	for(0..achievements.achievementCount()) |i| {
		achievementNodes[i] = .{
			.achievement = @enumFromInt(i),
			.children = .init(main.globalAllocator),
		};
	}
	for(0..achievements.achievementCount()) |i| {
		if(@as(Achievement, @enumFromInt(i)).parent()) |parent| {
			achievementNodes[@intFromEnum(parent)].children.append(i);
		}
	}
}

fn assignPositions(nodeIndex: usize, depth: u32, yOffset: f32) f32 {
	const node = &achievementNodes[nodeIndex];
	node.depth = depth;
	if(node.children.items.len == 0) {
		node.yOffset = yOffset;
		return 1;
	}
	var totalHeight: f32 = 0;
	for(node.children.items) |childIndex| {
		totalHeight += assignPositions(childIndex, depth + 1, yOffset + totalHeight);
	}
	const firstY = achievementNodes[node.children.items[0]].yOffset;
	const lastY = achievementNodes[node.children.items[node.children.items.len - 1]].yOffset;
	node.yOffset = (firstY + lastY) / 2.0;
	return totalHeight;
}

const padding: f32 = 8;

var list: *NoLayoutList = undefined;

pub fn onOpen() void {
	generateNodes();
	var maxYOffset: f32 = 0;
	for(achievementNodes) |achievement| {
		if(achievement.achievement.parent() != null) continue;
		maxYOffset += assignPositions(@intFromEnum(achievement.achievement), 0, maxYOffset);
	}
	var maxDepth: u32 = 0;
	for(achievementNodes) |achievement| {
		maxDepth = @max(maxDepth, achievement.depth + 1);
	}
	width = @intCast(maxDepth * 64);
	height = @intFromFloat(maxYOffset * 64);

	list = NoLayoutList.init(.{padding, 16 + padding}, 256, 256, 0);
	
	for(achievementNodes) |achievement| {
		std.debug.print("{d} {d}\n", .{achievement.depth, achievement.yOffset});
		list.add(Icon.init(.{@floatFromInt(achievement.depth * 32), achievement.yOffset * 32}, .{16, 16}, Button.pressedTextures.texture, true));
	}
	// list.add(Icon.init(.{0, 0}, .{@floatFromInt(width), @floatFromInt(height)}, Button.pressedTextures.texture, true));
	list.finish();

	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn render() void {
	const oldTranslation = graphics.draw.setTranslation(list.pos);
	defer graphics.draw.restoreTranslation(oldTranslation);
	var shiftedPos = list.pos;
	var clip = list.size;
	if(list.horizontalScrollBarEnabled) {
		const diff = list.childrenWidth - list.maxWidth;
		shiftedPos[0] -= diff*list.horizontalScrollBar.currentState;
		clip[1] -= 16;
	}
	if(list.verticalScrollBarEnabled) {
		const diff = list.childrenHeight - list.maxHeight;
		shiftedPos[1] -= diff*list.verticalScrollBar.currentState;
		clip[0] -= 16;
	}
	const oldClip = graphics.draw.setClip(clip);
	defer graphics.draw.restoreClip(oldClip);
	_ = graphics.draw.setTranslation(shiftedPos - list.pos);
	const listPadding: Vec2f = @splat(list.padding);
	for(achievementNodes) |achievement| {
		if(achievement.achievement.parent()) |parentIndex| {
			const parent = achievementNodes[@intFromEnum(parentIndex)];
			graphics.draw.setColor(0xff000000);
			graphics.draw.line(listPadding + Vec2f{@floatFromInt(parent.depth * 32 + 16), parent.yOffset * 32 + 8}, listPadding + Vec2f{@floatFromInt(parent.depth * 32 + 24), parent.yOffset * 32 + 8});
			graphics.draw.line(listPadding + Vec2f{@floatFromInt(achievement.depth * 32 - 8), achievement.yOffset * 32 + 8}, listPadding + Vec2f{@floatFromInt(achievement.depth * 32), achievement.yOffset * 32 + 8});
			graphics.draw.line(listPadding + Vec2f{@floatFromInt(parent.depth * 32 + 24), parent.yOffset * 32 + 8}, listPadding + Vec2f{@floatFromInt(achievement.depth * 32 - 8), achievement.yOffset * 32 + 8});
		}
	}
}

pub fn onClose() void {
	for(achievementNodes) |achievement| {
		achievement.children.deinit();
	}
	main.globalAllocator.free(achievementNodes);
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}
