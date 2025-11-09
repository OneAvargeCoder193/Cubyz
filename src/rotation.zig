const std = @import("std");

const blocks = @import("blocks.zig");
const Block = blocks.Block;
const chunk = @import("chunk.zig");
const Neighbor = chunk.Neighbor;
const main = @import("main");
const ModelIndex = main.models.ModelIndex;
const Tag = main.Tag;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const Vec3f = vec.Vec3f;
const Mat4f = vec.Mat4f;
const ZonElement = main.ZonElement;

const list = @import("rotation/_list.zig");

pub const RayIntersectionResult = struct {
	distance: f64,
	min: Vec3f,
	max: Vec3f,
	face: Neighbor,
};

pub const Degrees = enum(u2) {
	@"0" = 0,
	@"90" = 1,
	@"180" = 2,
	@"270" = 3,
};

// TODO: Why not just use a tagged union?
/// Each block gets 16 bit of additional storage(apart from the reference to the block type).
/// These 16 bits are accessed and interpreted by the `RotationMode`.
/// With the `RotationMode` interface there is almost no limit to what can be done with those 16 bit.
pub const RotationMode = struct { // MARK: RotationMode
	pub const DefaultFunctions = struct {
		pub fn empty() void {}
		pub fn model(block: Block) ModelIndex {
			return blocks.meshes.modelIndexStart(block);
		}
		pub fn rotateZ(data: u16, _: Degrees) u16 {
			return data;
		}
		pub fn generateData(_: *main.game.World, _: Vec3i, _: Vec3f, _: Vec3f, _: Vec3i, _: ?Neighbor, _: *Block, _: Block, blockPlacing: bool) bool {
			return blockPlacing;
		}
		pub fn createBlockModel(_: Block, _: *u16, zon: ZonElement) ModelIndex {
			return main.models.getModelIndex(zon.as([]const u8, "cubyz:cube"));
		}
		pub fn updateData(_: *Block, _: Neighbor, _: Block) bool {
			return false;
		}
		pub fn modifyBlock(_: *Block, _: u16) bool {
			return false;
		}
		pub fn rayIntersection(block: Block, _: ?main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f) ?RayIntersectionResult {
			return rayModelIntersection(blocks.meshes.model(block), relativePlayerPos, playerDir);
		}
		pub fn rayModelIntersection(modelIndex: ModelIndex, relativePlayerPos: Vec3f, playerDir: Vec3f) ?RayIntersectionResult {
			// Check the true bounding box (using this algorithm here: https://tavianator.com/2011/ray_box.html):
			const invDir = @as(Vec3f, @splat(1))/playerDir;
			const modelData = modelIndex.model();
			const min: Vec3f = modelData.min;
			const max: Vec3f = modelData.max;
			const t1 = (min - relativePlayerPos)*invDir;
			const t2 = (max - relativePlayerPos)*invDir;
			const boxTMin = @reduce(.Max, @min(t1, t2));
			const boxTMax = @reduce(.Min, @max(t1, t2));
			if(boxTMin <= boxTMax and boxTMax > 0) {
				var face: Neighbor = undefined;
				if(boxTMin == t1[0]) {
					face = Neighbor.dirNegX;
				} else if(boxTMin == t1[1]) {
					face = Neighbor.dirNegY;
				} else if(boxTMin == t1[2]) {
					face = Neighbor.dirDown;
				} else if(boxTMin == t2[0]) {
					face = Neighbor.dirPosX;
				} else if(boxTMin == t2[1]) {
					face = Neighbor.dirPosY;
				} else if(boxTMin == t2[2]) {
					face = Neighbor.dirUp;
				} else {
					unreachable;
				}
				return .{
					.distance = boxTMin,
					.min = min,
					.max = max,
					.face = face,
				};
			}
			return null;
		}
		pub fn onBlockBreaking(_: ?main.items.Item, _: Vec3f, _: Vec3f, currentData: *Block) void {
			currentData.* = .{.typ = 0, .data = 0};
		}
		pub fn canBeChangedInto(oldBlock: Block, newBlock: Block, item: main.items.ItemStack, shouldDropSourceBlockOnSuccess: *bool) CanBeChangedInto {
			shouldDropSourceBlockOnSuccess.* = true;
			if(oldBlock == newBlock) return .no;
			if(oldBlock.typ == newBlock.typ) return .yes;
			if(!oldBlock.replacable()) {
				var damage: f32 = main.game.Player.defaultBlockDamage;
				const isTool = item.item != null and item.item.? == .tool;
				if(isTool) {
					damage = item.item.?.tool.getBlockDamage(oldBlock);
				}
				damage -= oldBlock.blockResistance();
				if(damage > 0) {
					if(isTool and item.item.?.tool.isEffectiveOn(oldBlock)) {
						return .{.yes_costsDurability = 1};
					} else return .yes;
				}
			} else {
				if(item.item) |_item| {
					if(_item == .baseItem) {
						if(_item.baseItem.block() != null and _item.baseItem.block().? == newBlock.typ) {
							return .{.yes_costsItems = 1};
						}
					}
				}
				if(newBlock.typ == 0) {
					return .yes;
				}
			}
			return .no;
		}
		pub fn getBlockTags() []const Tag {
			return &.{};
		}
	};

	pub const CanBeChangedInto = union(enum(u32)) {
		no: void,
		yes: void,
		yes_costsDurability: u16,
		yes_costsItems: u16,
		yes_dropsItems: u16,
	};

	/// if the block should be destroyed or changed when a certain neighbor is removed.
	dependsOnNeighbors: bool = false,

	/// The default rotation data intended for generation algorithms
	naturalStandard: u16 = 0,

	initFn: main.wasm.ModdableFunction(fn() void, main.wasm.clientNoWrapper) = .initFromCode(&DefaultFunctions.empty),
	deinitFn: main.wasm.ModdableFunction(fn() void, main.wasm.clientNoWrapper) = .initFromCode(&DefaultFunctions.empty),
	resetFn: main.wasm.ModdableFunction(fn() void, main.wasm.clientNoWrapper) = .initFromCode(&DefaultFunctions.empty),

	modelFn: main.wasm.ModdableFunction(fn(block: Block) ModelIndex, struct{
		fn wrapper(instance: *main.wasm.WasmInstance, func: *main.wasm.c.wasm_func_t, args: anytype) ModelIndex {
			instance.currentSide = .client;
			const index = instance.invokeFunc(func, .{@as(u32, @bitCast(args[0]))}, u32) catch unreachable;
			return @enumFromInt(index);
		}
	}.wrapper) = .initFromCode(&DefaultFunctions.model),

	// Rotates block data counterclockwise around the Z axis.
	rotateZFn: main.wasm.ModdableFunction(fn(data: u16, angle: Degrees) u16, struct{
		fn wrapper(instance: *main.wasm.WasmInstance, func: *main.wasm.c.wasm_func_t, args: anytype) u16 {
			instance.currentSide = .client;
			return instance.invokeFunc(func, .{args[0], @as(u32, @intFromEnum(args[1]))}, u16) catch unreachable;
		}
	}.wrapper) = .initFromCode(&DefaultFunctions.rotateZ),

	createBlockModelFn: main.wasm.ModdableFunction(fn(block: Block, modeData: *u16, zon: ZonElement) ModelIndex, struct{
		fn wrapper(instance: *main.wasm.WasmInstance, func: *main.wasm.c.wasm_func_t, args: anytype) ModelIndex {
			instance.currentSide = .client;
			const data = instance.alloc(@sizeOf(u16));
			defer instance.free(data, @sizeOf(u16));
			const text = args[2].toStringEfficient(main.stackAllocator, "");
			defer main.stackAllocator.free(text);
			const textAlloc = instance.allocSlice(text);
			defer instance.free(textAlloc, @intCast(text.len));
			const index = instance.invokeFunc(func, .{@as(u32, @bitCast(args[0])), data, textAlloc, @as(u32, @intCast(text.len))}, u32) catch unreachable;
			args[1].* = instance.getMemory(u16, data);
			return @enumFromInt(index);
		}
	}.wrapper) = .initFromCode(&DefaultFunctions.createBlockModel),

	/// Updates the block data of a block in the world or places a block in the world.
	/// return true if the placing was successful, false otherwise.
	generateDataFn: main.wasm.ModdableFunction(fn(world: *main.game.World, pos: Vec3i, relativePlayerPos: Vec3f, playerDir: Vec3f, relativeDir: Vec3i, neighbor: ?Neighbor, currentData: *Block, neighborBlock: Block, blockPlacing: bool) bool, struct{
		fn wrapper(instance: *main.wasm.WasmInstance, func: *main.wasm.c.wasm_func_t, args: anytype) bool {
			instance.currentSide = .client;
			const data = instance.alloc(@sizeOf(u32));
			defer instance.free(data, @sizeOf(u32));
			instance.setMemory(u32, @bitCast(args[6].*), data);
			defer args[6].* = @bitCast(instance.getMemory(u32, data));
			return instance.invokeFunc(func, .{args[1][0], args[1][1], args[1][2], args[2][0], args[2][1], args[2][2], args[3][0], args[3][1], args[3][2], args[4][0], args[4][1], args[4][2], args[5] != null, @as(u32, if(args[5]) |neighbor| @intFromEnum(neighbor) else 0), data, @as(u32, @bitCast(args[7])), args[8]}, bool) catch unreachable;
		}
	}.wrapper) = .initFromCode(&DefaultFunctions.generateData),

	/// Updates data of a placed block if the RotationMode dependsOnNeighbors.
	updateDataFn: main.wasm.ModdableFunction(fn(block: *Block, neighbor: Neighbor, neighborBlock: Block) bool, struct{
		fn wrapper(instance: *main.wasm.WasmInstance, func: *main.wasm.c.wasm_func_t, args: anytype) bool {
			instance.currentSide = .client;
			const data = instance.alloc(@sizeOf(u32));
			defer instance.free(data, @sizeOf(u32));
			instance.setMemory(u32, @bitCast(args[0].*), data);
			defer args[0].* = @bitCast(instance.getMemory(u32, data));
			return instance.invokeFunc(func, .{data, @as(u32, @intFromEnum(args[1])), @as(u32, @bitCast(args[2]))}, bool) catch unreachable;
		}
	}.wrapper) = .initFromCode(&DefaultFunctions.updateData),

	modifyBlockFn: main.wasm.ModdableFunction(fn(block: *Block, newType: u16) bool, struct{
		fn wrapper(instance: *main.wasm.WasmInstance, func: *main.wasm.c.wasm_func_t, args: anytype) bool {
			instance.currentSide = .client;
			const data = instance.alloc(@sizeOf(u32));
			defer instance.free(data, @sizeOf(u32));
			instance.setMemory(u32, @bitCast(args[0].*), data);
			defer args[0].* = @bitCast(instance.getMemory(u32, data));
			return instance.invokeFunc(func, .{data, args[1]}, bool) catch unreachable;
		}
	}.wrapper) = .initFromCode(&DefaultFunctions.modifyBlock),

	rayIntersectionFn: main.wasm.ModdableFunction(fn(block: Block, item: ?main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f) ?RayIntersectionResult, struct{
		fn wrapper(instance: *main.wasm.WasmInstance, func: *main.wasm.c.wasm_func_t, args: anytype) ?RayIntersectionResult {
			instance.currentSide = .client;
			const distance: u32 = instance.alloc(@sizeOf(f64));
			defer instance.free(distance, @sizeOf(f64));
			var min: [3]u32 = undefined;
			for(0..3) |i| min[i] = instance.alloc(@sizeOf(f32));
			defer for(0..3) |i| instance.free(min[i], @sizeOf(f32));
			var max: [3]u32 = undefined;
			for(0..3) |i| max[i] = instance.alloc(@sizeOf(f32));
			defer for(0..3) |i| instance.free(max[i], @sizeOf(f32));
			const face: u32 = instance.alloc(@sizeOf(u32));
			defer instance.free(face, @sizeOf(u32));
			instance.invokeFunc(func, .{args[0], args[2], args[3], distance, min, max, face}, void);
			return .{
				.distance = instance.getMemory(f64, distance),
				.min = .{instance.getMemory(f32, min[0]), instance.getMemory(f32, min[1]), instance.getMemory(f32, min[2])},
				.max = .{instance.getMemory(f32, max[0]), instance.getMemory(f32, max[1]), instance.getMemory(f32, max[2])},
				.face = @enumFromInt(instance.getMemory(u32, face)),
			};
		}
	}.wrapper) = .initFromCode(&DefaultFunctions.rayIntersection),

	onBlockBreakingFn: main.wasm.ModdableFunction(fn(item: ?main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f, currentData: *Block) void, struct{
		fn wrapper(instance: *main.wasm.WasmInstance, func: *main.wasm.c.wasm_func_t, args: anytype) void {
			instance.currentSide = .client;
			instance.invokeFunc(func, .{args[1], args[2], args[3]}, void);
		}
	}.wrapper) = .initFromCode(&DefaultFunctions.onBlockBreaking),

	canBeChangedIntoFn: main.wasm.ModdableFunction(fn(oldBlock: Block, newBlock: Block, item: main.items.ItemStack, shouldDropSourceBlockOnSuccess: *bool) CanBeChangedInto, struct{
		fn wrapper(instance: *main.wasm.WasmInstance, func: *main.wasm.c.wasm_func_t, args: anytype) CanBeChangedInto {
			instance.currentSide = .client;
			const shouldDrop = instance.alloc(@sizeOf(bool));
			defer instance.free(shouldDrop, @sizeOf(bool));
			const value = instance.alloc(@sizeOf(u16));
			defer instance.free(value, @sizeOf(u16));
			const result = instance.invokeFunc(func, .{args[0], args[1], shouldDrop, value}, u32);
			const typ = @as(std.meta.Tag(CanBeChangedInto), @enumFromInt(result));
			return switch(typ) {
				.no, .yes => |tag| @unionInit(CanBeChangedInto, @tagName(tag), {}),
				inline else => |tag| @unionInit(CanBeChangedInto, @tagName(tag), value),
			};
		}
	}.wrapper) = .initFromCode(&DefaultFunctions.canBeChangedInto),

	getBlockTagsFn: main.wasm.ModdableFunction(fn() []const Tag, struct{
		fn wrapper(instance: *main.wasm.WasmInstance, _: *main.wasm.c.wasm_func_t, _: anytype) []const Tag {
			instance.currentSide = .client;
			@panic("getBlockTags is not implemented for wasm mods.");
		}
	}.wrapper) = .initFromCode(&DefaultFunctions.getBlockTags),

	pub fn init(self: RotationMode) void {
		self.initFn.invoke(.{});
	}

	pub fn deinit(self: RotationMode) void {
		self.deinitFn.invoke(.{});
	}

	pub fn reset(self: RotationMode) void {
		self.resetFn.invoke(.{});
	}

	pub fn model(self: RotationMode, block: Block) ModelIndex {
		return self.modelFn.invoke(.{block});
	}

	pub fn rotateZ(self: RotationMode, data: u16, angle: Degrees) u16 {
		return self.rotateZFn.invoke(.{data, angle});
	}

	pub fn createBlockModel(self: RotationMode, block: Block, modeData: *u16, zon: ZonElement) ModelIndex {
		return self.createBlockModelFn.invoke(.{block, modeData, zon});
	}

	pub fn generateData(self: RotationMode, world: *main.game.World, pos: Vec3i, relativePlayerPos: Vec3f, playerDir: Vec3f, relativeDir: Vec3i, neighbor: ?Neighbor, currentData: *Block, neighborBlock: Block, blockPlacing: bool) bool {
		return self.generateDataFn.invoke(.{world, pos, relativePlayerPos, playerDir, relativeDir, neighbor, currentData, neighborBlock, blockPlacing});
	}

	pub fn updateData(self: RotationMode, block: *Block, neighbor: Neighbor, neighborBlock: Block) bool {
		return self.updateDataFn.invoke(.{block, neighbor, neighborBlock});
	}

	pub fn modifyBlock(self: RotationMode, block: *Block, newType: u16) bool {
		return self.modifyBlockFn.invoke(.{block, newType});
	}

	pub fn rayIntersection(self: RotationMode, block: Block, item: ?main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f) ?RayIntersectionResult {
		return self.rayIntersectionFn.invoke(.{block, item, relativePlayerPos, playerDir});
	}

	pub fn onBlockBreaking(self: RotationMode, item: ?main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f, currentData: *Block) void {
		self.onBlockBreakingFn.invoke(.{item, relativePlayerPos, playerDir, currentData});
	}

	pub fn canBeChangedInto(self: RotationMode, oldBlock: Block, newBlock: Block, item: main.items.ItemStack, shouldDropSourceBlockOnSuccess: *bool) CanBeChangedInto {
		return self.canBeChangedIntoFn.invoke(.{oldBlock, newBlock, item, shouldDropSourceBlockOnSuccess});
	}

	pub fn getBlockTags(self: RotationMode) []const Tag {
		return self.getBlockTagsFn.invoke(.{});
	}
};

var rotationModes: std.StringHashMap(RotationMode) = undefined;

pub fn rotationMatrixTransform(quad: *main.models.QuadInfo, transformMatrix: Mat4f) void {
	quad.normal = vec.xyz(Mat4f.mulVec(transformMatrix, vec.combine(quad.normal, 0)));
	for(&quad.corners) |*corner| {
		corner.* = vec.xyz(Mat4f.mulVec(transformMatrix, vec.combine(corner.* - Vec3f{0.5, 0.5, 0.5}, 1))) + Vec3f{0.5, 0.5, 0.5};
	}
}

// MARK: init/register

pub fn init() void {
	rotationModes = .init(main.globalAllocator.allocator);
	inline for(@typeInfo(list).@"struct".decls) |declaration| {
		register(declaration.name, @field(list, declaration.name));
	}
	for(main.modding.mods.items) |mod| {
		mod.invoke("registerRotationModes", .{}, void) catch {};
	}
}

pub fn reset() void {
	var iter = rotationModes.valueIterator();
	while(iter.next()) |mode| {
		mode.reset();
	}
}

pub fn deinit() void {
	var iter = rotationModes.valueIterator();
	while(iter.next()) |mode| {
		mode.deinit();
	}
	rotationModes.deinit();
}

pub fn getByID(id: []const u8) *RotationMode {
	if(rotationModes.getPtr(id)) |mode| return mode;
	std.log.err("Could not find rotation mode {s}. Using cubyz:no_rotation instead.", .{id});
	return rotationModes.getPtr("cubyz:no_rotation").?;
}

pub fn register(comptime id: []const u8, comptime Mode: type) void {
	var result: RotationMode = RotationMode{};
	inline for(@typeInfo(RotationMode).@"struct".fields) |field| {
		if(!std.mem.eql(u8, field.name[field.name.len - 2..], "Fn")) {
			if(@hasDecl(Mode, field.name)) {
				@field(result, field.name) = @field(Mode, field.name);
			}
		} else {
			if(@hasDecl(Mode, field.name[0..field.name.len - 2])) {
				@field(result, field.name) = .initFromCode(@field(Mode, field.name[0..field.name.len - 2]));
			}
		}
	}
	result.init();
	rotationModes.putNoClobber(id, result) catch unreachable;
}

pub fn registerRotationModeWasm(
	instance: *main.wasm.WasmInstance,
	id: []const u8, dependsOnNeighbors: ?bool, naturalStandard: ?u16,
	initFn: []const u8, deinitFn: []const u8, resetFn: []const u8,
	modelFn: []const u8, rotateZFn: []const u8,
	createBlockModelFn: []const u8, generateDataFn: []const u8,
	updateDataFn: []const u8, modifyBlockFn: []const u8,
	rayIntersectionFn: []const u8, onBlockBreakingFn: []const u8,
	canBeChangedIntoFn: []const u8, getBlockTagsFn: []const u8,
) void {
	var result: RotationMode = .{};
	if(dependsOnNeighbors) |_| result.dependsOnNeighbors = dependsOnNeighbors.?;
	if(naturalStandard) |_| result.naturalStandard = naturalStandard.?;
	result.initFn = .initFromWasm(instance, initFn);
	result.deinitFn = .initFromWasm(instance, deinitFn);
	result.resetFn = .initFromWasm(instance, resetFn);
	if(modelFn.len != 0) result.modelFn = .initFromWasm(instance, modelFn);
	if(rotateZFn.len != 0) result.rotateZFn = .initFromWasm(instance, rotateZFn);
	if(createBlockModelFn.len != 0) result.createBlockModelFn = .initFromWasm(instance, createBlockModelFn);
	if(generateDataFn.len != 0) result.generateDataFn = .initFromWasm(instance, generateDataFn);
	if(updateDataFn.len != 0) result.updateDataFn = .initFromWasm(instance, updateDataFn);
	if(modifyBlockFn.len != 0) result.modifyBlockFn = .initFromWasm(instance, modifyBlockFn);
	if(rayIntersectionFn.len != 0) result.rayIntersectionFn = .initFromWasm(instance, rayIntersectionFn);
	if(onBlockBreakingFn.len != 0) result.onBlockBreakingFn = .initFromWasm(instance, onBlockBreakingFn);
	if(canBeChangedIntoFn.len != 0) result.canBeChangedIntoFn = .initFromWasm(instance, canBeChangedIntoFn);
	if(getBlockTagsFn.len != 0) result.getBlockTagsFn = .initFromWasm(instance, getBlockTagsFn);
	result.init();
	rotationModes.put(id, result) catch unreachable;
}