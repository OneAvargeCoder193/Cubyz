const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const draw = graphics.draw;
const TextBuffer = graphics.TextBuffer;
const vec = main.vec;
const Vec2f = vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const ScrollBar = GuiComponent.ScrollBar;

const NoLayoutList = @This();

const scrollBarWidth = 10;
const border: f32 = 3;

pos: Vec2f,
size: Vec2f,
children: main.List(GuiComponent),
padding: f32,
maxWidth: f32,
maxHeight: f32,
childrenWidth: f32 = 0,
childrenHeight: f32 = 0,
verticalScrollBar: *ScrollBar,
verticalScrollBarEnabled: bool = false,
horizontalScrollBar: *ScrollBar,
horizontalScrollBarEnabled: bool = false,

pub fn init(pos: Vec2f, maxWidth: f32, maxHeight: f32, padding: f32) *NoLayoutList {
	const verticalScrollBar = ScrollBar.init(undefined, scrollBarWidth, maxHeight - 2*border, 0, .vertical);
	const horizontalScrollBar = ScrollBar.init(undefined, maxHeight - 2*border, scrollBarWidth, 0, .horizontal);
	const self = main.globalAllocator.create(NoLayoutList);
	self.* = NoLayoutList{
		.children = .init(main.globalAllocator),
		.pos = pos,
		.size = .{0, 0},
		.maxWidth = maxWidth,
		.maxHeight = maxHeight,
		.padding = padding,
		.verticalScrollBar = verticalScrollBar,
		.horizontalScrollBar = horizontalScrollBar,
	};
	return self;
}

pub fn deinit(self: *const NoLayoutList) void {
	for(self.children.items) |*child| {
		child.deinit();
	}
	self.verticalScrollBar.deinit();
	self.horizontalScrollBar.deinit();
	self.children.deinit();
	main.globalAllocator.destroy(self);
}

pub fn toComponent(self: *NoLayoutList) GuiComponent {
	return .{.noLayoutList = self};
}

pub fn add(self: *NoLayoutList, _other: anytype) void {
	var other: GuiComponent = undefined;
	if(@TypeOf(_other) == GuiComponent) {
		other = _other;
	} else {
		other = _other.toComponent();
	}
	other.mutPos().* += @splat(self.padding);
	self.size = @max(self.size, other.pos() + other.size());
	self.children.append(other);
}

pub fn finish(self: *NoLayoutList) void {
	self.children.shrinkAndFree(self.children.items.len);
	if(self.size[0] > self.maxWidth) {
		self.horizontalScrollBarEnabled = true;
		self.childrenWidth = self.size[0];
		self.size[0] = self.maxWidth;
	}
	if(self.size[1] > self.maxHeight) {
		self.verticalScrollBarEnabled = true;
		self.childrenHeight = self.size[1];
		self.size[1] = self.maxHeight;
	}
	if(self.childrenWidth > self.maxWidth) {
		self.horizontalScrollBar.pos = .{border, self.size[1] + border};
		self.size[1] += 2*border + scrollBarWidth;
	}
	if(self.childrenHeight > self.maxHeight) {
		self.verticalScrollBar.pos = .{self.size[0] + border, border};
		self.size[0] += 2*border + scrollBarWidth;
	}
}

pub fn updateSelected(self: *NoLayoutList) void {
	for(self.children.items) |*child| {
		child.updateSelected();
	}
}

pub fn updateHovered(self: *NoLayoutList, mousePosition: Vec2f) void {
	var shiftedPos = self.pos;
	if(self.verticalScrollBarEnabled) {
		const diff = self.childrenHeight - self.maxHeight;
		shiftedPos[1] -= diff*self.verticalScrollBar.currentState;
	}
	if(self.horizontalScrollBarEnabled) {
		const diff = self.childrenWidth - self.maxWidth;
		shiftedPos[0] -= diff*self.horizontalScrollBar.currentState;
	}
	var i: usize = self.children.items.len;
	while(i != 0) {
		i -= 1;
		const child = &self.children.items[i];
		if(GuiComponent.contains(child.pos() + shiftedPos, child.size(), mousePosition)) {
			child.updateHovered(mousePosition - shiftedPos);
			break;
		}
	}
	if(self.horizontalScrollBarEnabled) {
		const diff = self.childrenWidth - self.maxWidth;
		self.horizontalScrollBar.scroll(-main.Window.horizontalScrollOffset*32/diff);
		main.Window.horizontalScrollOffset = 0;
		if(GuiComponent.contains(self.horizontalScrollBar.pos, self.horizontalScrollBar.size, mousePosition - self.pos)) {
			self.horizontalScrollBar.updateHovered(mousePosition - self.pos);
		}
	}
	if(self.verticalScrollBarEnabled) {
		const diff = self.childrenHeight - self.maxHeight;
		self.verticalScrollBar.scroll(-main.Window.verticalScrollOffset*32/diff);
		main.Window.verticalScrollOffset = 0;
		if(GuiComponent.contains(self.verticalScrollBar.pos, self.verticalScrollBar.size, mousePosition - self.pos)) {
			self.verticalScrollBar.updateHovered(mousePosition - self.pos);
		}
	}
}

pub fn render(self: *NoLayoutList, mousePosition: Vec2f) void {
	const oldTranslation = draw.setTranslation(self.pos);
	defer draw.restoreTranslation(oldTranslation);
	var shiftedPos = self.pos;
	var clip = self.size;
	if(self.horizontalScrollBarEnabled) {
		const diff = self.childrenWidth - self.maxWidth;
		shiftedPos[0] -= diff*self.horizontalScrollBar.currentState;
		self.horizontalScrollBar.render(mousePosition - self.pos);
		clip[1] -= 2*border + scrollBarWidth;
	}
	if(self.verticalScrollBarEnabled) {
		const diff = self.childrenHeight - self.maxHeight;
		shiftedPos[1] -= diff*self.verticalScrollBar.currentState;
		self.verticalScrollBar.render(mousePosition - self.pos);
		clip[0] -= 2*border + scrollBarWidth;
	}
	const oldClip = draw.setClip(clip);
	defer draw.restoreClip(oldClip);
	_ = draw.setTranslation(shiftedPos - self.pos);

	for(self.children.items) |*child| {
		child.render(mousePosition - shiftedPos);
	}
}

pub fn mainButtonPressed(self: *NoLayoutList, mousePosition: Vec2f) void {
	var shiftedPos = self.pos;
	if(self.horizontalScrollBarEnabled) {
		const diff = self.childrenWidth - self.maxWidth;
		shiftedPos[0] -= diff*self.horizontalScrollBar.currentState;
		if(GuiComponent.contains(self.horizontalScrollBar.pos, self.horizontalScrollBar.size, mousePosition - self.pos)) {
			self.horizontalScrollBar.mainButtonPressed(mousePosition - self.pos);
			return;
		}
	}
	if(self.verticalScrollBarEnabled) {
		const diff = self.childrenHeight - self.maxHeight;
		shiftedPos[1] -= diff*self.verticalScrollBar.currentState;
		if(GuiComponent.contains(self.verticalScrollBar.pos, self.verticalScrollBar.size, mousePosition - self.pos)) {
			self.verticalScrollBar.mainButtonPressed(mousePosition - self.pos);
			return;
		}
	}
	var selectedChild: ?*GuiComponent = null;
	for(self.children.items) |*child| {
		if(GuiComponent.contains(child.pos() + shiftedPos, child.size(), mousePosition)) {
			selectedChild = child;
		}
	}
	if(selectedChild) |child| {
		child.mainButtonPressed(mousePosition - shiftedPos);
	}
}

pub fn mainButtonReleased(self: *NoLayoutList, mousePosition: Vec2f) void {
	var shiftedPos = self.pos;
	if(self.horizontalScrollBarEnabled) {
		const diff = self.childrenWidth - self.maxWidth;
		shiftedPos[0] -= diff*self.horizontalScrollBar.currentState;
		self.horizontalScrollBar.mainButtonReleased(mousePosition - self.pos);
	}
	if(self.verticalScrollBarEnabled) {
		const diff = self.childrenHeight - self.maxHeight;
		shiftedPos[1] -= diff*self.verticalScrollBar.currentState;
		self.verticalScrollBar.mainButtonReleased(mousePosition - self.pos);
	}
	for(self.children.items) |*child| {
		child.mainButtonReleased(mousePosition - shiftedPos);
	}
}
