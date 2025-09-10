const std = @import("std");

const main = @import("main");
const Vec2f = main.vec.Vec2f;
const graphics = main.graphics;
const c = graphics.c;
const Texture = graphics.Texture;
const Image = graphics.Image;
const ZonElement = main.ZonElement;
const achievements = main.achievements;
const Achievement = achievements.Achievement;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Icon = @import("../components/Icon.zig");
const Button = @import("../components/Button.zig");
const Label = @import("../components/Label.zig");
const VerticalList = @import("../components/VerticalList.zig");
const HorizontalList = @import("../components/HorizontalList.zig");

pub var window: GuiWindow = GuiWindow{
	.contentSize = Vec2f{128, 256},
	.closeIfMouseIsGrabbed = true,
};

const AchievementData = struct {
	icon: graphics.Texture,
	name: []u8,

	pub fn deinit(self: AchievementData) void {
		self.icon.deinit();
	}
};

const padding: f32 = 8;

var achievementList: main.List(AchievementData) = undefined;

fn readTexture(textureId: []const u8) !graphics.Texture {
	var splitter = std.mem.splitScalar(u8, textureId, ':');
	const mod = splitter.first();
	const id = splitter.rest();
	var path = try std.fmt.allocPrint(main.stackAllocator.allocator, "serverAssets/{s}/achievements/icons/{s}.png", .{mod, id});
	defer main.stackAllocator.free(path);
	const file = main.files.cwd().openFile(path) catch |err| blk: {
		if(err != error.FileNotFound) {
			std.log.err("Could not open file {s}: {s}", .{path, @errorName(err)});
		}
		main.stackAllocator.free(path);
		path = try std.fmt.allocPrint(main.stackAllocator.allocator, "assets/{s}/achievements/icons/{s}.png", .{mod, id}); // Default to global assets.
		break :blk main.files.cwd().openFile(path) catch |err2| {
			std.log.err("File not found. Searched in \"{s}\" and also in the assetFolder \"serverAssets\"", .{path});
			return err2;
		};
	};
	file.close();
	return Texture.initFromFile(path);
	
}

pub fn onOpen() void {
	achievementList = .init(main.globalAllocator);
	for(0..achievements.achievementCount()) |index| {
		const achievement = Achievement.fromIndex(@intCast(index));
		achievementList.append(.{
			.icon = readTexture(achievement.icon()) catch unreachable,
			.name = achievement.id(),
		});
	}

	const list = VerticalList.init(.{padding, 16 + padding}, 256, 8);
	
	for(achievementList.items) |achievementData| {
		const horizontalList = HorizontalList.init();
		horizontalList.add(Icon.init(.{0, 0}, .{32, 32}, achievementData.icon, true));
		horizontalList.add(Label.init(.{0, 0}, 150, achievementData.name, .left));
		horizontalList.finish(.{0, 0}, .left);
		list.add(Button.initComponent(.{0, 0}, horizontalList, .{.callback = null}));
	}
	list.finish(.center);

	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	for(achievementList.items) |achievementData| {
		achievementData.deinit();
	}
	achievementList.deinit();
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}
