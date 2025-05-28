const std = @import("std");

const main = @import("main");
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;

pub var window = GuiWindow{
	.contentSize = .{100, 100},
	.showTitleBar = false,
	.closeIfMouseIsGrabbed = true,
	.hasBackground = false,
};

const padding: f32 = 12;

const Location = enum {
	bottom,
	top,
};

const Section = enum {
	choice,
	settings,
	data
};

const Element = union (enum) {
	list: struct {
		elements: []*Element,
		location: Location,

		pub fn getHeight(self: @This()) f32 {
			var sum: f32 = 0;

			for (self.elements) |elem| {
				sum += elem.getHeight();
			}

			return sum;
		}

		pub fn render(self: @This(), x: f32, y: f32, w: f32, h: f32) void {
			var newY: f32 = if(self.location == .bottom) y + h - self.getHeight() - padding else y + padding;
			for (self.elements) |elem| {
				elem.render(x + padding, newY, w, h);
				newY += elem.getHeight();
			}
		}
	},
	button: struct {
		text: []const u8,
		
		pub fn getHeight(_: @This()) f32 {
			return 16;
		}
		
		pub fn render(self: @This(), x: f32, y: f32, _: f32, _: f32) void {
			main.graphics.draw.text(self.text, x, y, 16, .left);
		}
	},
	empty: struct {
		pub fn getHeight(_: @This()) f32 {
			return 16;
		}
		
		pub fn render(_: @This(), _: f32, _: f32, _: f32, _: f32) void {}
	},

	pub fn getHeight(self: Element) f32 {
		switch(self) {
			inline else => |val| {
				return val.getHeight();
			}
		}
	}

	pub fn render(self: Element, x: f32, y: f32, w: f32, h: f32) void {
		switch(self) {
			inline else => |val| {
				return val.render(x, y, w, h);
			}
		}
	}
};

fn openSettings() void {

}

var back: Element = .{.button = .{
	.text = "Back to Game",
}};
var invite: Element = .{.button = .{
	.text = "Invite Players",
}};
var settings: Element = .{.button = .{
	.text = "Settings",
	.onPress = &openSettings,
}};
var empty: Element = .empty;
var save: Element = .{.button = .{
	.text = "Save & Quit",
}};
var pauseMenuList = [_]*Element{&back, &invite, &settings, &empty, &save}; 
var pauseMenu: Element = .{.list = .{
	.elements = &pauseMenuList,
	.location = .bottom,
}};

var graphics: Element = .{.button = .{
	.text = "Graphics",
}};
var sound: Element = .{.button = .{
	.text = "Sound",
}};
var controls: Element = .{.button = .{
	.text = "Controls",
}};
var accsesibility: Element = .{.button = .{
	.text = "Accessibility",
}};
var changeName: Element = .{.button = .{
	.text = "Change Name",
}};

fn reorderHudCallbackFunction(_: usize) void {
	gui.reorderWindows = !gui.reorderWindows;
}
pub fn onOpen() void {}

pub fn onClose() void {
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}

pub fn render() void {
	const size = main.Window.getWindowSize() / @as(Vec2f, @splat(main.graphics.draw.getScale()));

	main.graphics.draw.restoreTranslation(.{0, 0});

	main.graphics.draw.setColor(0xaf000000);
	main.graphics.draw.rect(.{0, 0}, size);

	main.graphics.draw.setColor(0xffffffff);
	pauseMenu.render(0, 0, size[0] * 0.4, size[1]);
	
	main.graphics.draw.line(.{size[0] * 0.4, 0}, .{size[0] * 0.4, size[1]});
}