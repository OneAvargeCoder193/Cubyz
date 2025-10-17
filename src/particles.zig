const std = @import("std");

const main = @import("main");
const chunk_meshing = @import("renderer/chunk_meshing.zig");
const graphics = @import("graphics.zig");
const SSBO = graphics.SSBO;
const TextureArray = graphics.TextureArray;
const Shader = graphics.Shader;
const Image = graphics.Image;
const c = graphics.c;
const game = @import("game.zig");
const ZonElement = @import("zon.zig").ZonElement;
const random = @import("random.zig");
const vec = @import("vec.zig");
const Mat4f = vec.Mat4f;
const Vec3d = vec.Vec3d;
const Vec4d = vec.Vec4d;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const Vec3i = vec.Vec3i;

var seed: u64 = undefined;

var arena = main.heap.NeverFailingArenaAllocator.init(main.globalAllocator);
const arenaAllocator = arena.allocator();

pub const ParticleManager = struct {
	var particleTypesSSBO: SSBO = undefined;
	var types: main.List(ParticleType) = undefined;
	var textures: main.List(Image) = undefined;
	var emissionTextures: main.List(Image) = undefined;

	var textureArray: TextureArray = undefined;
	var emissionTextureArray: TextureArray = undefined;

	const ParticleIndex = u16;
	var particleTypeHashmap: std.StringHashMapUnmanaged(ParticleIndex) = .{};

	pub fn init() void {
		types = .init(arenaAllocator);
		textures = .init(arenaAllocator);
		emissionTextures = .init(arenaAllocator);
		textureArray = .init();
		emissionTextureArray = .init();
		particleTypesSSBO = SSBO.init();
		ParticleSystem.init();
	}

	pub fn deinit() void {
		types.deinit();
		textures.deinit();
		emissionTextures.deinit();
		textureArray.deinit();
		emissionTextureArray.deinit();
		particleTypeHashmap.deinit(arenaAllocator.allocator);
		ParticleSystem.deinit();
		particleTypesSSBO.deinit();
		arena.deinit();
	}

	pub fn register(assetsFolder: []const u8, id: []const u8, zon: ZonElement) void {
		const textureId = zon.get(?[]const u8, "texture", null) orelse {
			std.log.err("Particle texture id was not specified for {s} ({s})", .{id, assetsFolder});
			return;
		};

		const particleType = readTextureDataAndParticleType(assetsFolder, textureId);

		particleTypeHashmap.put(arenaAllocator.allocator, id, @intCast(types.items.len)) catch unreachable;
		types.append(particleType);

		std.log.debug("Registered particle type: {s}", .{id});
	}
	fn readTextureDataAndParticleType(assetsFolder: []const u8, textureId: []const u8) ParticleType {
		var typ: ParticleType = undefined;

		const base = readTexture(assetsFolder, textureId, ".png", Image.defaultImage, .isMandatory);
		const emission = readTexture(assetsFolder, textureId, "_emission.png", Image.emptyImage, .isOptional);
		const hasEmission = (emission.imageData.ptr != Image.emptyImage.imageData.ptr);
		const baseAnimationFrameCount = base.height/base.width;
		const emissionAnimationFrameCount = emission.height/emission.width;

		typ.frameCount = @floatFromInt(baseAnimationFrameCount);
		typ.startFrame = @floatFromInt(textures.items.len);
		typ.size = @as(f32, @floatFromInt(base.width))/16;

		var isBaseBroken = false;
		var isEmissionBroken = false;

		if(base.height%base.width != 0) {
			std.log.err("Particle base texture has incorrect dimensions ({}x{}) expected height to be multiple of width for {s} ({s})", .{base.width, base.height, textureId, assetsFolder});
			isBaseBroken = true;
		}
		if(hasEmission and emission.height%emission.width != 0) {
			std.log.err("Particle emission texture has incorrect dimensions ({}x{}) expected height to be multiple of width for {s} ({s})", .{base.width, base.height, textureId, assetsFolder});
			isEmissionBroken = true;
		}
		if(hasEmission and baseAnimationFrameCount != emissionAnimationFrameCount) {
			std.log.err("Particle base texture and emission texture frame count mismatch ({} vs {}) for {s} ({s})", .{baseAnimationFrameCount, emissionAnimationFrameCount, textureId, assetsFolder});
			isEmissionBroken = true;
		}

		createAnimationFrames(&textures, baseAnimationFrameCount, base, isBaseBroken);
		createAnimationFrames(&emissionTextures, baseAnimationFrameCount, emission, isBaseBroken or isEmissionBroken or !hasEmission);

		return typ;
	}

	fn readTexture(assetsFolder: []const u8, textureId: []const u8, suffix: []const u8, default: graphics.Image, status: enum {isOptional, isMandatory}) graphics.Image {
		var splitter = std.mem.splitScalar(u8, textureId, ':');
		const mod = splitter.first();
		const id = splitter.rest();

		const gameAssetsPath = std.fmt.allocPrint(main.stackAllocator.allocator, "assets/{s}/particles/textures/{s}{s}", .{mod, id, suffix}) catch unreachable;
		defer main.stackAllocator.free(gameAssetsPath);

		const worldAssetsPath = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}/{s}/particles/textures/{s}{s}", .{assetsFolder, mod, id, suffix}) catch unreachable;
		defer main.stackAllocator.free(worldAssetsPath);

		return graphics.Image.readFromFile(arenaAllocator, worldAssetsPath) catch graphics.Image.readFromFile(arenaAllocator, gameAssetsPath) catch {
			if(status == .isMandatory) std.log.err("Particle texture not found in {s} and {s}.", .{worldAssetsPath, gameAssetsPath});
			return default;
		};
	}

	fn createAnimationFrames(container: *main.List(Image), frameCount: usize, image: Image, isBroken: bool) void {
		for(0..frameCount) |i| {
			container.append(if(isBroken) image else extractAnimationSlice(image, i));
		}
	}

	fn extractAnimationSlice(image: Image, frameIndex: usize) Image {
		const frameCount = image.height/image.width;
		const frameHeight = image.height/frameCount;
		const startHeight = frameHeight*frameIndex;
		const endHeight = frameHeight*(frameIndex + 1);
		var result = image;
		result.height = @intCast(frameHeight);
		result.imageData = result.imageData[startHeight*image.width .. endHeight*image.width];
		return result;
	}

	pub fn generateTextureArray() void {
		textureArray.generate(textures.items, true, true);
		emissionTextureArray.generate(emissionTextures.items, true, false);

		particleTypesSSBO.bufferData(ParticleType, ParticleManager.types.items);
		particleTypesSSBO.bind(16);
	}
};

pub const ParticleSystem = struct {
	pub const maxCapacity: u32 = 524288;
	var particleCount: u32 = 0;
	var properties: EmitterProperties = undefined;
	var previousPlayerPos: Vec3d = undefined;

	var particleInputSSBO: SSBO = undefined;
	var particleOutputSSBO: SSBO = undefined;

	var pipeline: graphics.Pipeline = undefined;
	const UniformStruct = struct {
		projectionAndViewMatrix: c_int,
		billboardMatrix: c_int,
		ambientLight: c_int,
		playerPosition: c_int,
	};
	var uniforms: UniformStruct = undefined;

	var updatePipeline: graphics.ComputePipeline = undefined;
	const UpdateUniformStruct = struct {
		maxCapacity: c_int,
		deltaTime: c_int,
	};
	var updateUniforms: UpdateUniformStruct = undefined;
	const CreateUniformStruct = struct {
		maxCapacity: c_int,
	};
	var createUniforms: CreateUniformStruct = undefined;
	var createPipeline: graphics.ComputePipeline = undefined;
	var drawCountBuffer: c_uint = undefined;

	pub fn init() void {
		pipeline = graphics.Pipeline.init(
			"assets/cubyz/shaders/particles/particles.vert",
			"assets/cubyz/shaders/particles/particles.frag",
			"",
			&uniforms,
			.{},
			.{.depthTest = true, .depthWrite = true},
			.{.attachments = &.{.noBlending}},
		);
		updatePipeline = graphics.ComputePipeline.init(
			"assets/cubyz/shaders/particles/update.comp",
			"",
			&updateUniforms,
		);
		createPipeline = graphics.ComputePipeline.init(
			"assets/cubyz/shaders/particles/create.comp",
			"",
			&createUniforms,
		);

		properties = EmitterProperties{
			.gravity = .{0, 0, -2},
			.drag = 0.2,
			.lifeTimeMin = 10,
			.lifeTimeMax = 10,
			.velMin = 0.1,
			.velMax = 0.3,
			.rotVelMin = std.math.pi*0.2,
			.rotVelMax = std.math.pi*0.6,
			.randomizeRotationOnSpawn = true,
		};
		particleInputSSBO = SSBO.init();
		particleInputSSBO.createDynamicBuffer(Particle, maxCapacity);
		
		particleOutputSSBO = SSBO.init();
		particleOutputSSBO.createDynamicBuffer(Particle, maxCapacity);

		c.glGenBuffers(1, &drawCountBuffer);
		c.glBindBuffer(c.GL_ATOMIC_COUNTER_BUFFER, drawCountBuffer);
		c.glBufferData(c.GL_ATOMIC_COUNTER_BUFFER, @sizeOf(c_uint), null, c.GL_DYNAMIC_DRAW);
		c.glBindBufferBase(c.GL_ATOMIC_COUNTER_BUFFER, 0, drawCountBuffer);

		seed = @bitCast(@as(i64, @truncate(std.time.nanoTimestamp())));
	}

	pub fn deinit() void {
		pipeline.deinit();
		updatePipeline.deinit();
		createPipeline.deinit();
		particleInputSSBO.deinit();
		particleOutputSSBO.deinit();
		c.glDeleteBuffers(1, &drawCountBuffer);
	}

	pub fn update(deltaTime: f32) void {
		particleInputSSBO.bind(13);
		particleOutputSSBO.bind(14);

		if(main.random.nextFloat(&seed) < 0.1) {
			createPipeline.bind();
			c.glUniform1ui(createUniforms.maxCapacity, maxCapacity);
			c.glDispatchCompute(1, 1, 1);
			c.glMemoryBarrier(c.GL_SHADER_STORAGE_BARRIER_BIT | c.GL_ATOMIC_COUNTER_BARRIER_BIT);
		}

		c.glGetBufferSubData(c.GL_ATOMIC_COUNTER_BUFFER, 0, @sizeOf(u32), &particleCount);

		var zero: c_uint = 0;
		c.glBindBuffer(c.GL_ATOMIC_COUNTER_BUFFER, drawCountBuffer);
		c.glClearBufferData(c.GL_ATOMIC_COUNTER_BUFFER, c.GL_R32UI, c.GL_RED_INTEGER, c.GL_UNSIGNED_INT, &zero);
		c.glBindBufferBase(c.GL_ATOMIC_COUNTER_BUFFER, 0, drawCountBuffer);

		if(particleCount > 0) {
			updatePipeline.bind();
			c.glUniform1ui(updateUniforms.maxCapacity, maxCapacity);
			c.glUniform1f(updateUniforms.deltaTime, deltaTime);
			c.glDispatchCompute(@intCast(@divFloor(particleCount + 63, 64)), 1, 1);
			c.glMemoryBarrier(c.GL_SHADER_STORAGE_BARRIER_BIT | c.GL_ATOMIC_COUNTER_BARRIER_BIT);
			std.mem.swap(SSBO, &particleInputSSBO, &particleOutputSSBO);
		}

		c.glGetBufferSubData(c.GL_ATOMIC_COUNTER_BUFFER, 0, @sizeOf(u32), &particleCount);
	}

	pub fn render(projectionMatrix: Mat4f, viewMatrix: Mat4f, ambientLight: Vec3f, playerPos: Vec3d) void {
		pipeline.bind(null);
		particleInputSSBO.bind(13);

		const projectionAndViewMatrix = Mat4f.mul(projectionMatrix, viewMatrix);
		c.glUniformMatrix4fv(uniforms.projectionAndViewMatrix, 1, c.GL_TRUE, @ptrCast(&projectionAndViewMatrix));
		c.glUniform3fv(uniforms.ambientLight, 1, @ptrCast(&ambientLight));
		const playerPosition: Vec3f = @floatCast(playerPos);
		c.glUniform3fv(uniforms.playerPosition, 1, @ptrCast(&playerPosition));

		const billboardMatrix = Mat4f.rotationZ(-game.camera.rotation[2] + std.math.pi*0.5)
			.mul(Mat4f.rotationY(game.camera.rotation[0] - std.math.pi*0.5));
		c.glUniformMatrix4fv(uniforms.billboardMatrix, 1, c.GL_TRUE, @ptrCast(&billboardMatrix));

		c.glActiveTexture(c.GL_TEXTURE0);
		ParticleManager.textureArray.bind();
		c.glActiveTexture(c.GL_TEXTURE1);
		ParticleManager.emissionTextureArray.bind();

		c.glBindVertexArray(chunk_meshing.vao);

		for(0..std.math.divCeil(u32, particleCount, chunk_meshing.maxQuadsInIndexBuffer) catch unreachable) |_| {
			c.glDrawElements(c.GL_TRIANGLES, @intCast(particleCount*6), c.GL_UNSIGNED_INT, null);
		}
	}

	pub fn getParticleCount() u32 {
		return particleCount;
	}
};

pub const EmitterProperties = struct {
	gravity: Vec3f = @splat(0),
	drag: f32 = 0,
	velMin: f32 = 0,
	velMax: f32 = 0,
	rotVelMin: f32 = 0,
	rotVelMax: f32 = 0,
	lifeTimeMin: f32 = 0,
	lifeTimeMax: f32 = 0,
	randomizeRotationOnSpawn: bool = false,
};

pub const DirectionMode = union(enum(u8)) {
	// The particle goes in the direction away from the center
	spread: void,
	// The particle goes in a random direction
	scatter: void,
	// The particle goes in the specified direction
	direction: Vec3f,
};

pub const Emitter = struct {
	typ: u16 = 0,
	collides: bool,

	pub const SpawnPoint = struct {
		mode: DirectionMode,
		position: Vec3d,

		pub fn spawn(self: SpawnPoint) struct {Vec3d, Vec3f} {
			const particlePos = self.position;
			const speed: Vec3f = @splat(ParticleSystem.properties.velMin + random.nextFloat(&seed)*ParticleSystem.properties.velMax);
			const dir: Vec3f = switch(self.mode) {
				.direction => |dir| dir,
				.scatter, .spread => vec.normalize(random.nextFloatVectorSigned(3, &seed)),
			};
			const particleVel = dir*speed;

			return .{particlePos, particleVel};
		}
	};

	pub const SpawnSphere = struct {
		radius: f32,
		mode: DirectionMode,
		position: Vec3d,

		pub fn spawn(self: SpawnSphere) struct {Vec3d, Vec3f} {
			const spawnPos: Vec3f = @splat(self.radius);
			var offsetPos: Vec3f = undefined;
			while(true) {
				offsetPos = random.nextFloatVectorSigned(3, &seed);
				if(vec.lengthSquare(offsetPos) <= 1) break;
			}
			const particlePos = self.position + @as(Vec3d, @floatCast(offsetPos*spawnPos));
			const speed: Vec3f = @splat(ParticleSystem.properties.velMin + random.nextFloat(&seed)*ParticleSystem.properties.velMax);
			const dir: Vec3f = switch(self.mode) {
				.direction => |dir| dir,
				.scatter => vec.normalize(random.nextFloatVectorSigned(3, &seed)),
				.spread => @floatCast(offsetPos),
			};
			const particleVel = dir*speed;

			return .{particlePos, particleVel};
		}
	};

	pub const SpawnCube = struct {
		size: Vec3f,
		mode: DirectionMode,
		position: Vec3d,

		pub fn spawn(self: SpawnCube) struct {Vec3d, Vec3f} {
			const spawnPos: Vec3f = self.size;
			const offsetPos: Vec3f = random.nextFloatVectorSigned(3, &seed);
			const particlePos = self.position + @as(Vec3d, @floatCast(offsetPos*spawnPos));
			const speed: Vec3f = @splat(ParticleSystem.properties.velMin + random.nextFloat(&seed)*ParticleSystem.properties.velMax);
			const dir: Vec3f = switch(self.mode) {
				.direction => |dir| dir,
				.scatter => vec.normalize(random.nextFloatVectorSigned(3, &seed)),
				.spread => vec.normalize(@as(Vec3f, @floatCast(offsetPos))),
			};
			const particleVel = dir*speed;

			return .{particlePos, particleVel};
		}
	};

	pub fn init(id: []const u8, collides: bool) Emitter {
		const emitter = Emitter{
			.typ = ParticleManager.particleTypeHashmap.get(id) orelse 0,
			.collides = collides,
		};

		return emitter;
	}

	pub fn spawnParticles(_: Emitter, _: u32, comptime T: type, _: T) void {
		
	}
};

pub const ParticleType = struct {
	frameCount: f32,
	startFrame: f32,
	size: f32,
};

pub const Particle = struct {
	posAndRotation: Vec4f,
	lifeRatio: f32 = 1,
	light: u32 = 0,
	typ: u32,
	// 4 bytes left for use
};

pub const ParticleLocal = struct {
	velAndRotationVel: Vec4f,
	lifeVelocity: f32,
	collides: bool,
};
