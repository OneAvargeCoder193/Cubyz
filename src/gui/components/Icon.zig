const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const draw = graphics.draw;
const Texture = graphics.Texture;
const vec = main.vec;
const Vec2f = vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;

const Icon = @This();

const fontSize: f32 = 16;

index: gui.ComponentIndex,
pos: Vec2f,
size: Vec2f,
texture: Texture,
hasShadow: bool,

pub fn init(pos: Vec2f, size: Vec2f, texture: Texture, hasShadow: bool) *Icon {
	const self, const index = gui.createComponent(Icon);
	self.* = Icon{
		.index = index,
		.texture = texture,
		.pos = pos,
		.size = size,
		.hasShadow = hasShadow,
	};
	return self;
}

pub fn deinit(self: *const Icon) void {
	gui.removeComponent(self.index);
	main.globalAllocator.destroy(self);
}

pub fn toComponent(self: *Icon) GuiComponent {
	return .{.icon = self};
}

pub fn updateTexture(self: *Icon, newTexture: Texture) !void {
	self.texture = newTexture;
}

pub fn render(self: *Icon, _: Vec2f) void {
	if(self.hasShadow) {
		draw.setColor(0xff000000);
		self.texture.render(self.pos + Vec2f{1, 1}, self.size);
	}
	draw.setColor(0xffffffff);
	self.texture.render(self.pos, self.size);
}

pub fn initWasm(_: *main.wasm.WasmInstance, posX: f32, posY: f32, sizeX: f32, sizeY: f32, textureId: u32, hasShadow: bool) u32 {
	const label = init(.{posX, posY}, .{sizeX, sizeY}, .{.textureID = @intCast(textureId)}, hasShadow);
	return @intFromEnum(label.index);
}