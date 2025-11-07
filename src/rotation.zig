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

	pub const CanBeChangedInto = union(enum) {
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
			return instance.invokeFunc(func, .{args[0], @intFromEnum(args[1])}, u16) catch unreachable;
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
			const index = instance.invokeFunc(func, .{@as(u32, @bitCast(args[0])), data, textAlloc}, u32) catch unreachable;
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
			instance.setMemory(u32, data, @bitCast(args[6].*));
			defer args[6].* = @bitCast(instance.getMemory(u32, data));
			return instance.invokeFunc(func, .{args[1][0], args[1][1], args[1][2], args[2][0], args[2][1], args[2][2], args[3][0], args[3][1], args[3][2], args[4][0], args[4][1], args[4][2], args[5] != null, if(args[5]) |neighbor| @intFromEnum(neighbor) else 0, data, @as(u32, @bitCast(args[7])), args[8]}, bool) catch unreachable;
		}
	}.wrapper) = .initFromCode(&DefaultFunctions.generateData),

	/// Updates data of a placed block if the RotationMode dependsOnNeighbors.
	updateDataFn: main.wasm.ModdableFunction(fn(block: *Block, neighbor: Neighbor, neighborBlock: Block) bool, struct{
		fn wrapper(instance: *main.wasm.WasmInstance, func: *main.wasm.c.wasm_func_t, args: anytype) bool {
			instance.currentSide = .client;
			const data = instance.alloc(@sizeOf(u32));
			defer instance.free(data, @sizeOf(u32));
			instance.setMemory(u32, data, @bitCast(args[0].*));
			defer args[0].* = @bitCast(instance.getMemory(u32, data));
			return instance.invokeFunc(func, .{data, @intFromEnum(args[1]), @as(u32, @bitCast(args[2]))}, bool) catch unreachable;
		}
	}.wrapper) = .initFromCode(&DefaultFunctions.updateData),

	modifyBlockFn: main.wasm.ModdableFunction(fn(block: *Block, newType: u16) bool, struct{
		fn wrapper(instance: *main.wasm.WasmInstance, func: *main.wasm.c.wasm_func_t, args: anytype) bool {
			instance.currentSide = .client;
			const data = instance.alloc(@sizeOf(u32));
			defer instance.free(data, @sizeOf(u32));
			instance.setMemory(u32, data, @bitCast(args[0].*));
			defer args[0].* = @bitCast(instance.getMemory(u32, data));
			return instance.invokeFunc(func, .{data, args[1]}, bool) catch unreachable;
		}
	}.wrapper) = .initFromCode(&DefaultFunctions.modifyBlock),

	rayIntersectionFn: main.wasm.ModdableFunction(fn(block: Block, item: ?main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f) ?RayIntersectionResult, struct{
		fn wrapper(instance: *main.wasm.WasmInstance, _: *main.wasm.c.wasm_func_t, _: anytype) ?RayIntersectionResult {
			instance.currentSide = .client;
			@panic("rayIntersection is not implemented for wasm mods.");
		}
	}.wrapper) = .initFromCode(&DefaultFunctions.rayIntersection),

	onBlockBreakingFn: main.wasm.ModdableFunction(fn(item: ?main.items.Item, relativePlayerPos: Vec3f, playerDir: Vec3f, currentData: *Block) void, struct{
		fn wrapper(instance: *main.wasm.WasmInstance, _: *main.wasm.c.wasm_func_t, _: anytype) void {
			instance.currentSide = .client;
			@panic("onBlockBreaking is not implemented for wasm mods.");
		}
	}.wrapper) = .initFromCode(&DefaultFunctions.onBlockBreaking),

	canBeChangedIntoFn: main.wasm.ModdableFunction(fn(oldBlock: Block, newBlock: Block, item: main.items.ItemStack, shouldDropSourceBlockOnSuccess: *bool) CanBeChangedInto, struct{
		fn wrapper(instance: *main.wasm.WasmInstance, _: *main.wasm.c.wasm_func_t, _: anytype) CanBeChangedInto {
			instance.currentSide = .client;
			@panic("canBeChangedInto is not implemented for wasm mods.");
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
		if(@hasDecl(Mode, field.name)) {
			if(@typeInfo(field.type) != .@"fn") {
				@field(result, field.name) = @field(Mode, field.name);
			} else if(field.type == @TypeOf(@field(Mode, field.name))) {
				@field(result, field.name ++ "Fn") = .initFromCode(@field(Mode, field.name));
			} else {
				@field(result, field.name ++ "Fn") = .initFromCode(&@field(Mode, field.name));
			}
		}
	}
	result.init();
	rotationModes.putNoClobber(id, result) catch unreachable;
}
