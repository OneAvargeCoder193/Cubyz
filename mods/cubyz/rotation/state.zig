const std = @import("std");

const main = @import("main");
const blocks = main.blocks;
const Block = blocks.Block;
const Neighbor = main.chunk.Neighbor;
const ModelIndex = main.models.ModelIndex;
const rotation = main.rotation;
const Degrees = rotation.Degrees;
const vec = main.vec;
const Mat4f = vec.Mat4f;
const Vec3f = vec.Vec3f;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;

var models: std.StringHashMap(ModelIndex) = undefined;

pub fn init() void {
	models = .init(main.globalAllocator.allocator);
}

pub fn deinit() void {
	models.deinit();
}

pub fn reset() void {
	models.clearRetainingCapacity();
}

pub fn createBlockModel(_: Block, _: *u16, zon: ZonElement) ModelIndex {
	const modelId = zon.as([]const u8, "cubyz:cube");
	if(models.get(modelId)) |modelIndex| return modelIndex;

	const baseModel = main.models.getModelIndex(modelId).model();
	var quadList = main.List(main.models.QuadInfo).init(main.stackAllocator);
	defer quadList.deinit();
	baseModel.getRawFaces(&quadList);

	var modelIndex: ModelIndex = undefined;
	for(0..16) |i| {
		for(quadList.items) |*quad| {
			quad.textureSlot = @intCast(i);
		}
		const index = main.models.Model.init(quadList.items);
		if(i == 0) {
			modelIndex = index;
		}
	}
	models.put(modelId, modelIndex) catch unreachable;
	return modelIndex;
}

pub fn model(block: Block) ModelIndex {
	return blocks.meshes.modelIndexStart(block).add(block.data & 15);
}

pub fn generateData(_: *main.game.World, _: Vec3i, _: Vec3f, _: Vec3f, _: Vec3i, _: ?Neighbor, _: *Block, _: Block, blockPlacing: bool) bool {
	return blockPlacing;
}
