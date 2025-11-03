const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const vec = main.vec;
const Vec3i = vec.Vec3i;

pub const CallbackList = struct {
	pub const ClientBlockCallback = Callback(struct {block: Block, blockPos: Vec3i}, struct{
		fn wrapper(instance: *main.wasm.WasmInstance, func: *main.wasm.c.wasm_func_t, args: anytype) Result {
			instance.currentSide = .client;
			return @enumFromInt(instance.invokeFunc(func, .{@as(u32, @intCast(@intFromPtr(args[0]))), @as(u32, @bitCast(args[1].block)), args[1].blockPos[0], args[1].blockPos[1], args[1].blockPos[2]}, u1) catch 0);
		}
	}.wrapper, @import("block/client/_list.zig"));
	pub const ServerBlockCallback = Callback(struct {block: Block, chunk: *main.chunk.ServerChunk, x: i32, y: i32, z: i32}, struct{
		fn wrapper(instance: *main.wasm.WasmInstance, func: *main.wasm.c.wasm_func_t, args: anytype) Result {
			instance.currentSide = .server;
			return @enumFromInt(instance.invokeFunc(func, .{@as(u32, @intCast(@intFromPtr(args[0]))), @as(u32, @bitCast(args[1].block)), args[1].x, args[1].y, args[1].z}, u1) catch 0);
		}
	}.wrapper, @import("block/server/_list.zig"));
	pub const BlockTouchCallback = Callback(struct {id: u32, source: Block, blockPos: Vec3i, deltaTime: f64}, struct{
		fn wrapper(instance: *main.wasm.WasmInstance, func: *main.wasm.c.wasm_func_t, args: anytype) Result {
			instance.currentSide = .client; // Change this when we get entities
			return @enumFromInt(instance.invokeFunc(func, .{@as(u32, @intCast(@intFromPtr(args[0]))), args[1].id, @as(u32, @bitCast(args[1].source)), args[1].blockPos[0], args[1].blockPos[1], args[1].blockPos[2], args[1].deltaTime}, u1) catch 0);
		}
	}.wrapper, @import("block/touch/_list.zig"));
};

pub const Result = enum(u1) {handled = 0, ignored = 1};

pub fn init() void {
	CallbackList.ClientBlockCallback.globalInit("initClientBlockCallback");
	CallbackList.ServerBlockCallback.globalInit("initServerBlockCallback");
	CallbackList.BlockTouchCallback.globalInit("initTouchBlockCallback");
}

const InitFunc = main.wasm.ModdableFunction(fn(zon: main.ZonElement) ?*anyopaque, struct{
	fn wrapper(instance: *main.wasm.WasmInstance, func: *main.wasm.c.wasm_func_t, args: anytype) ?*anyopaque {
		instance.currentSide = .client;
		const str = args[0].toStringEfficient(main.stackAllocator, "");
		defer main.stackAllocator.free(str);
		return @ptrFromInt(instance.invokeFunc(func, .{str}, u32) catch return null);
	}
}.wrapper);

fn Callback(_Params: type, wasmWrapper: anytype, list: type) type {
	return struct {
		data: *anyopaque,
		inner: RunFunc,

		pub const Params = _Params;
		pub const RunFunc = main.wasm.ModdableFunction(fn(self: *anyopaque, params: Params) Result, wasmWrapper);

		const VTable = struct {
			init: InitFunc,
			run: RunFunc,
		};

		var eventCreationMap: std.StringHashMapUnmanaged(VTable) = .{};

		fn globalInit(initWasmFunc: []const u8) void {
			inline for(@typeInfo(list).@"struct".decls) |decl| {
				const CallbackStruct = @field(list, decl.name);
				eventCreationMap.put(main.globalArena.allocator, main.globalArena.dupe(u8, decl.name), .{
					.init = .initFromCode(main.utils.castFunctionReturnToAnyopaque(CallbackStruct.init)),
					.run = .initFromCode(main.utils.castFunctionSelfToAnyopaque(CallbackStruct.run)),
				}) catch unreachable;
			}
			for(main.modding.mods.items) |mod| {
				mod.invoke(initWasmFunc, .{}, void) catch {};
			}
		}

		fn addFromWasm(instance: *main.wasm.WasmInstance, id: []const u8, initName: []const u8, runName: []const u8) void {
			eventCreationMap.put(main.globalArena.allocator, main.globalArena.dupe(u8, id), .{
				.init = .initFromWasm(instance, initName),
				.run = .initFromWasm(instance, runName),
			}) catch unreachable;
		}

		pub fn init(zon: main.ZonElement) ?@This() {
			const typ = zon.get(?[]const u8, "type", null) orelse {
				std.log.err("Missing field \"type\"", .{});
				return null;
			};
			const vtable = eventCreationMap.get(typ) orelse {
				std.log.err("Couldn't find block interact event {s}", .{typ});
				return null;
			};
			return .{
				.data = vtable.init.invoke(.{zon}) orelse return null,
				.inner = vtable.run,
			};
		}

		pub const noop: @This() = .{
			.data = undefined,
			.inner = .initFromCode(&noopCallback),
		};

		fn noopCallback(_: *anyopaque, _: Params) Result {
			return .ignored;
		}

		pub fn run(self: @This(), params: Params) Result {
			return self.inner.invoke(.{self.data, params});
		}

		pub fn isNoop(self: @This()) bool {
			return self.inner == .code and self.inner.code == &noopCallback;
		}
	};
}

pub fn registerCallbackWasm(instance: *main.wasm.WasmInstance, listName: []const u8, id: []const u8, initName: []const u8, runName: []const u8) void {
	const _listEnum = std.meta.stringToEnum(std.meta.DeclEnum(CallbackList), listName) orelse {
		std.log.err("Invalid callback list name: {s}\n", .{listName});
		return;
	};
	switch(_listEnum) {
		inline else => |listEnum| {
			@field(CallbackList, @tagName(listEnum)).addFromWasm(instance, id, initName, runName);
		}
	}
}