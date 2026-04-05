const std = @import("std");

const main = @import("main");
const Array2D = main.utils.Array2D;
const random = main.random;
const ZonElement = main.ZonElement;
const terrain = main.server.terrain;
const MapFragment = terrain.SurfaceMap.MapFragment;
const noise = terrain.noise;
const FractalNoise = noise.FractalNoise;
const RandomlyWeightedFractalNoise = noise.RandomlyWeightedFractalNoise;
const PerlinNoise = noise.PerlinNoise;
const ErosionNoise = noise.ErosionNoise;
const vec = main.vec;
const Vec2f = vec.Vec2f;

pub const id = "cubyz:mapgen_v2";

pub fn init(parameters: ZonElement) void {
	_ = parameters;
}

/// Assumes the 2 points are at tᵢ = (0, 1)
fn interpolationWeights(t: f32, interpolation: terrain.biomes.Interpolation) Vec2f {
	switch (interpolation) {
		.none => {
			if (t < 0.5) {
				return .{1, 0};
			} else {
				return .{0, 1};
			}
		},
		.linear => {
			return .{1 - t, t};
		},
		.square => {
			if (t < 0.5) {
				const tSqr = 2*t*t;
				return .{1 - tSqr, tSqr};
			} else {
				const tSqr = 2*(1 - t)*(1 - t);
				return .{tSqr, 1 - tSqr};
			}
		},
	}
}

pub fn generateMapFragment(map: *MapFragment, _: u64) void {
	const scaledSize = MapFragment.mapSize;
	const mapSize = scaledSize*map.pos.voxelSize;
	// const biomeSize = MapFragment.biomeSize;
	// const offset = 32;
	// const biomePositions = terrain.ClimateMap.getBiomeMap(main.stackAllocator, map.pos.wx -% offset*biomeSize, map.pos.wy -% offset*biomeSize, mapSize + 2*offset*biomeSize, mapSize + 2*offset*biomeSize);
	// defer biomePositions.deinit(main.stackAllocator);
	// var seed = random.initSeed2D(worldSeed, .{map.pos.wx, map.pos.wy});
	// random.scrambleSeed(&seed);
	// seed ^= seed >> 16;

	// const heightMap = ErosionNoise.generateErosionHeightmap(main.stackAllocator, scaledSize, scaledSize, worldSeed);
	// defer heightMap.deinit(main.stackAllocator);

	// const baseMap = PerlinNoise.generateSmoothNoise(main.stackAllocator, map.pos.wx, map.pos.wy, 512 * map.pos.voxelSize, 512 * map.pos.voxelSize, 512, 32, worldSeed ^ 157839765839495820, map.pos.voxelSize, 0.5);
	// defer baseMap.deinit(main.stackAllocator);
	const heightMap = ErosionNoise.generateErosionHeightmap(main.stackAllocator, map.pos.wx, map.pos.wy, mapSize, mapSize, 64.0, map.pos.voxelSize);
	defer heightMap.deinit(main.stackAllocator);

	var x: u31 = 0;
	while (x < map.heightMap.len) : (x += 1) {
		var y: u31 = 0;
		while (y < map.heightMap.len) : (y += 1) {
			const height = heightMap.get(x, y) * 4.0;
			map.heightMap[x][y] = @intFromFloat(height);
			// std.debug.print("{d}\n", .{height});
			map.biomeMap[x][y] = main.server.terrain.biomes.getById("cubyz:grassland");
		}
	}
}
