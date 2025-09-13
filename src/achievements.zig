const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const Assets = main.assets.Assets;

var arena = main.heap.NeverFailingArenaAllocator.init(main.globalAllocator);
const allocator = arena.allocator();

pub const maxAchievementCount = 256;

pub const Achievement = enum(u8) {
	_,
	pub fn toIndex(self: Achievement) u8 {
		return @intFromEnum(self);
	}
	pub fn fromIndex(index: u8) Achievement {
		return @enumFromInt(index);
	}
	pub fn id(self: Achievement) []u8 {
		return _id[self.toIndex()];
	}
	pub fn parent(self: Achievement) ?Achievement {
		return .fromIndex(_parent[self.toIndex()] orelse return null);
	}
	pub fn icon(self: Achievement) []u8 {
		return _icon[self.toIndex()];
	}
};

var _id: [maxAchievementCount][]u8 = undefined;
var _parent: [maxAchievementCount]?u8 = undefined;
var _icon: [maxAchievementCount][]u8 = undefined;

var reverseIndices = std.StringHashMap(u8).init(allocator.allocator);

var size: u32 = 0;

pub fn init() void {}

pub fn deinit() void {
	arena.deinit();
}

pub fn reset() void {
	size = 0;
	_ = arena.reset(.free_all);
	reverseIndices = .init(arena.allocator().allocator);
}

pub fn register(_: []const u8, id: []const u8, zon: ZonElement) u8 {
	_id[size] = allocator.dupe(u8, id);
	reverseIndices.put(_id[size], @intCast(size)) catch unreachable;

	_icon[size] = allocator.dupe(u8, zon.get([]const u8, "icon", "cubyz:default_icon"));

	defer size += 1;
	std.log.debug("Registered achievement: {d: >5} '{s}'", .{size, id});
	return @intCast(size);
}

fn registerParent(typ: u16, zon: ZonElement) void {
	if(zon.get(?[]const u8, "parent", null)) |replacement| {
		_parent[typ] = getTypeById(replacement);
	} else {
		_parent[typ] = null;
	}
}

pub fn finishAchievements(zonElements: Assets.ZonHashMap) void {
	var i: u16 = 0;
	while(i < size) : (i += 1) {
		registerParent(i, zonElements.get(_id[i]) orelse continue);
	}
}

pub fn getTypeById(id: []const u8) u8 {
	if(reverseIndices.get(id)) |result| {
		return result;
	} else {
		std.log.err("Couldn't find achievement {s}. Replacing it with air...", .{id});
		return 0;
	}
}

pub fn achievementCount() u8 {
	return @intCast(size);
}