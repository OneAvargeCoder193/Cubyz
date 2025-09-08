const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const draw = graphics.draw;
const TextBuffer = graphics.TextBuffer;
const Texture = graphics.Texture;
const random = main.random;
const vec = main.vec;
const Vec2f = vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const Button = GuiComponent.Button;
const Label = GuiComponent.Label;

const ScrollBar = @This();

const fontSize: f32 = 16;

var textureHorizontal: Texture = undefined;
var textureVertical: Texture = undefined;

const ScrollAxis = enum(u1) {
	horizontal = 0,
	vertical = 1,
};

pos: Vec2f,
size: Vec2f,
currentState: f32,
button: *Button,
mouseAnchor: f32 = undefined,
axis: ScrollAxis = undefined,

pub fn __init() void {
	textureHorizontal = Texture.initFromFile("assets/cubyz/ui/scrollbar_horizontal.png");
	textureVertical = Texture.initFromFile("assets/cubyz/ui/scrollbar_vertical.png");
}

pub fn __deinit() void {
	textureHorizontal.deinit();
	textureVertical.deinit();
}

pub fn init(pos: Vec2f, width: f32, height: f32, initialState: f32, axis: ScrollAxis) *ScrollBar {
	const button = Button.initText(.{0, 0}, undefined, "", .{});
	const self = main.globalAllocator.create(ScrollBar);
	self.* = ScrollBar{
		.pos = pos,
		.size = Vec2f{width, height},
		.currentState = initialState,
		.button = button,
		.axis = axis,
	};
	self.button.size = if (axis == .vertical) .{width, 16} else .{16, height};
	self.setButtonPosFromValue();
	return self;
}

pub fn deinit(self: *const ScrollBar) void {
	self.button.deinit();
	main.globalAllocator.destroy(self);
}

pub fn toComponent(self: *ScrollBar) GuiComponent {
	return .{.scrollBar = self};
}

fn setButtonPosFromValue(self: *ScrollBar) void {
	const range: f32 = self.size[@intFromEnum(self.axis)] - self.button.size[@intFromEnum(self.axis)];
	self.button.pos[@intFromEnum(self.axis)] = range*self.currentState;
}

fn updateValueFromButtonPos(self: *ScrollBar) void {
	const range: f32 = self.size[@intFromEnum(self.axis)] - self.button.size[@intFromEnum(self.axis)];
	const value = self.button.pos[@intFromEnum(self.axis)]/range;
	if(value != self.currentState) {
		self.currentState = value;
	}
}

pub fn scroll(self: *ScrollBar, offset: f32) void {
	self.currentState += offset;
	self.currentState = @min(1, @max(0, self.currentState));
}

pub fn updateHovered(self: *ScrollBar, mousePosition: Vec2f) void {
	if(GuiComponent.contains(self.button.pos, self.button.size, mousePosition - self.pos)) {
		self.button.updateHovered(mousePosition - self.pos);
	}
}

pub fn mainButtonPressed(self: *ScrollBar, mousePosition: Vec2f) void {
	if(GuiComponent.contains(self.button.pos, self.button.size, mousePosition - self.pos)) {
		self.button.mainButtonPressed(mousePosition - self.pos);
		self.mouseAnchor = mousePosition[@intFromEnum(self.axis)] - self.button.pos[@intFromEnum(self.axis)];
	}
}

pub fn mainButtonReleased(self: *ScrollBar, mousePosition: Vec2f) void {
	self.button.mainButtonReleased(mousePosition - self.pos);
}

pub fn render(self: *ScrollBar, mousePosition: Vec2f) void {
	if(self.axis == .horizontal) {
		textureHorizontal.bindTo(0);
	} else {
		textureVertical.bindTo(0);
	}
	Button.pipeline.bind(draw.getScissor());
	draw.setColor(0xff000000);
	draw.customShadedRect(Button.buttonUniforms, self.pos, self.size);

	const range: f32 = self.size[@intFromEnum(self.axis)] - self.button.size[@intFromEnum(self.axis)];
	self.setButtonPosFromValue();
	if(self.button.pressed) {
		self.button.pos[@intFromEnum(self.axis)] = mousePosition[@intFromEnum(self.axis)] - self.mouseAnchor;
		self.button.pos[@intFromEnum(self.axis)] = @min(@max(self.button.pos[@intFromEnum(self.axis)], 0), range - 0.001);
		self.updateValueFromButtonPos();
	}
	const oldTranslation = draw.setTranslation(self.pos);
	defer draw.restoreTranslation(oldTranslation);
	self.button.render(mousePosition - self.pos);
}
