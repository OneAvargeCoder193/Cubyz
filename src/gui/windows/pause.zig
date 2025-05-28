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

const padding: f32 = 8;

const Location = enum {
	bottom,
	top,
};

pub fn List(len: comptime_int, elems: [len]type, loc: Location) type {
	return struct {
		const Self = @This();

		const elements = elems;
		const location = loc;

		pub fn getHeight() f32 {
			var sum: f32 = 0;

			inline for (elements) |elem| {
				sum += elem.getHeight();
			}

			return sum;
		}

		pub fn render(x: f32, _: f32) void {
			var newY: f32 = if(location == .bottom) main.Window.getWindowSize()[1] - Self.getHeight() else 0;
			inline for (elements) |elem| {
				elem.render(x, newY);
				newY += elem.getHeight();
			}
		}
	};
}

pub fn Button(name: []const u8) type {
	return struct {
		const text = name;

		pub fn getHeight() f32 {
			return 16;
		}

		pub fn render(x: f32, y: f32) void {
			main.graphics.draw.text(text, x, y, 16, .left);
		}
	};
}

pub fn Break() type {
	return struct {
		pub fn getHeight() f32 {
			return 16;
		}

		pub fn render(_: f32, _: f32) void {}
	};
}

const PauseMenu = List(
	5, [_]type{
		Button("Back to Game"),
		Button("Invite Players"),
		Button("Settings"),
		Break(),
		Button("Save & Quit"),
	},
	.bottom
);

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
	main.graphics.draw.restoreTranslation(.{0, 0});

	PauseMenu.render(0, 0);

	main.graphics.draw.setColor(0xaf000000);
	main.graphics.draw.rect(.{0, 0}, main.Window.getWindowSize());
}