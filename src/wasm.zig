const std = @import("std");

pub const c = @cImport({
	@cInclude("wasm.h");
	@cInclude("wasmer.h");
});

const main = @import("main");

pub var engine: ?*c.wasm_engine_t = undefined;
pub var store: ?*c.wasm_store_t = undefined;

pub fn init() !void {
	engine = c.wasm_engine_new() orelse return error.WasmInitError;
	store = c.wasm_store_new(engine) orelse return error.WasmInitError;
}

pub fn deinit() void {
	c.wasm_engine_delete(engine);
	c.wasm_store_delete(store);
}

pub const WasmInstance = struct {
	module: ?*c.wasm_module_t,
	instanciated: bool = false,
	instance: *c.wasm_instance_t,
	exportTypes: c.wasm_exporttype_vec_t,
	importTypes: c.wasm_importtype_vec_t,
	exports: c.wasm_extern_vec_t,
	memory: ?*c.wasm_memory_t,
	currentSide: main.utils.Side,
	env: Env,
	importList: []?*c.wasm_extern_t,

	pub const Env = struct {
		instance: *WasmInstance,
	};

	pub fn init(allocator: main.heap.NeverFailingAllocator, file: std.fs.File) !*WasmInstance {
		var out: *WasmInstance = allocator.create(WasmInstance);
		out.env.instance = out;
		const data = try file.readToEndAlloc(main.stackAllocator.allocator, std.math.maxInt(usize));
		defer main.stackAllocator.free(data);
		var byteVec: c.wasm_byte_vec_t = .{.data = data.ptr, .size = data.len};
		out.module = c.wasm_module_new(store, &byteVec) orelse {
			const err = main.stackAllocator.alloc(u8, @intCast(c.wasmer_last_error_length()));
			_ = c.wasmer_last_error_message(err.ptr, @intCast(err.len));
			std.log.err("{s}\n", .{err});
			return error.WasmModuleError;
		};
		c.wasm_module_exports(out.module, &out.exportTypes);
		c.wasm_module_imports(out.module, &out.importTypes);
		out.importList = main.globalAllocator.alloc(?*c.wasm_extern_t, out.importTypes.size);
		@memset(out.importList, null);
		return out;
	}

	pub fn deinit(self: *WasmInstance, allocator: main.heap.NeverFailingAllocator) void {
		c.wasm_module_delete(self.module);
		if(self.instanciated) {
			c.wasm_instance_delete(self.instance);
			c.wasm_exporttype_vec_delete(&self.exportTypes);
			c.wasm_extern_vec_delete(&self.exports);
			main.globalAllocator.free(self.importList);
		}
		allocator.destroy(self);
	}

	pub fn instantiate(self: *WasmInstance) !void {
		var imports: c.wasm_extern_vec_t = undefined;
		c.wasm_extern_vec_new(&imports, self.importList.len, self.importList.ptr);
		defer c.wasm_extern_vec_delete(&imports);
		self.instance = c.wasm_instance_new(store, self.module, &imports, null) orelse {
			const err = main.stackAllocator.alloc(u8, @intCast(c.wasmer_last_error_length()));
			_ = c.wasmer_last_error_message(err.ptr, @intCast(err.len));
			std.log.err("{s}\n", .{err});
			return error.WasmInstanceError;
		};
		self.instanciated = true;
		c.wasm_instance_exports(self.instance, &self.exports);
		self.memory = c.wasm_extern_as_memory(self.exports.data[self.getExport("memory") orelse return]);
	}

	fn getNumberArgs(comptime T: type) comptime_int {
		return switch(@typeInfo(T)) {
			.@"void" => 0,
			.bool => 1,
			.int => 1,
			.float => 1,
			.pointer => |ptr| switch(ptr.size) {
				.slice => 2,
				else => std.debug.panic("Illegal type {s} inside wasm import\n", .{@typeName(T)})
			},
			else => std.debug.panic("Illegal type {s} inside wasm import\n", .{@typeName(T)}),
		};
	}

	fn typeToValType(comptime T: type) [getNumberArgs(T)]c.wasm_valkind_t {
		return switch(@typeInfo(T)) {
			.@"void" => [_]c.wasm_valkind_t{},
			.bool => [_]c.wasm_valkind_t{c.WASM_I32},
			.int => |int| switch(int.bits) {
				32 => [_]c.wasm_valkind_t{c.WASM_I32},
				64 => [_]c.wasm_valkind_t{c.WASM_I64},
				else => std.debug.panic("Found illegal type {s} inside wasm import\n", .{@typeName(T)}),
			},
			.float => |float| switch(float.bits) {
				32 => [_]c.wasm_valkind_t{c.WASM_F32},
				64 => [_]c.wasm_valkind_t{c.WASM_F64},
				else => std.debug.panic("Found illegal type {s} inside wasm import\n", .{@typeName(T)}),
			},
			.pointer => |ptr| switch(ptr.size) {
				.slice => [_]c.wasm_valkind_t{c.WASM_I32, c.WASM_I32},
				else => std.debug.panic("Illegal type {s} inside wasm import\n", .{@typeName(T)}),
			},
			else => std.debug.panic("Illegal type {s} inside wasm import\n", .{@typeName(T)}),
		};
	}

	fn wasmToValue(self: *WasmInstance, comptime T: type, vals: [getNumberArgs(T)]c.wasm_val_t) T {
		return switch(@typeInfo(T)) {
			.void => {},
			.bool => vals[0].of.i32 != 0,
			.int => |int| switch(int.bits) {
				32 => @as(T, @bitCast(vals[0].of.i32)),
				64 => @as(T, @bitCast(vals[0].of.i64)),
				else => std.debug.panic("Found illegal type {s} inside wasm import\n", .{@typeName(T)}),
			},
			.float => |float| switch(float.bits) {
				32 => vals[0].of.f32,
				64 => vals[0].of.f64,
				else => std.debug.panic("Found illegal type {s} inside wasm import\n", .{@typeName(T)}),
			},
			.pointer => |ptr| switch(ptr.size) {
				.slice => self.createSliceFromWasm(vals[0], vals[1]) catch unreachable,
				else => std.debug.panic("Illegal type {s} inside wasm import\n", .{@typeName(T)}),
			},
			else => std.debug.panic("Illegal type {s} inside wasm import\n", .{@typeName(T)}),
		};
	}

	fn valueToWasm(self: *WasmInstance, comptime T: type, val: T) [getNumberArgs(T)]c.wasm_val_t {
		return switch(@typeInfo(T)) {
			.void => [_]c.wasm_val_t{},
			.bool => [_]c.wasm_val_t{.{.kind = c.WASM_I32, .of = .{.i32 = @intFromBool(val)}}},
			.int => |int| switch(int.bits) {
				32 => [_]c.wasm_val_t{.{.kind = c.WASM_I32, .of = .{.i32 = @bitCast(val)}}},
				64 => [_]c.wasm_val_t{.{.kind = c.WASM_I64, .of = .{.i64 = @bitCast(val)}}},
				else => std.debug.panic("Found illegal type {s} inside wasm import\n", .{@typeName(T)}),
			},
			.float => |float| switch(float.bits) {
				32 => [_]c.wasm_val_t{.{.kind = c.WASM_F32, .of = .{.f32 = val}}},
				64 => [_]c.wasm_val_t{.{.kind = c.WASM_F64, .of = .{.f64 = val}}},
				else => std.debug.panic("Found illegal type {s} inside wasm import\n", .{@typeName(T)}),
			},
			.pointer => |ptr| switch(ptr.size) {
				.slice => self.createWasmFromSlice(val),
				else => std.debug.panic("Illegal type {s} inside wasm import\n", .{@typeName(T)}),
			},
			else => std.debug.panic("Illegal type {s} inside wasm import\n", .{@typeName(T)}),
		};
	}

	pub fn addImport(self: *WasmInstance, name: []const u8, comptime func: anytype) !void {
		std.debug.assert(@typeInfo(@TypeOf(func)) == .@"fn");
		const retValTypes: [getNumberArgs(@typeInfo(@TypeOf(func)).@"fn".return_type.?)]c.wasm_valkind_t = comptime blk: {
			const args = typeToValType(@typeInfo(@TypeOf(func)).@"fn".return_type.?);
			if(args.len == 2) {
				std.debug.panic("Illegal return value in wasm {s}\n", .{@typeName(@typeInfo(@TypeOf(func)).@"fn".return_type.?)});
			} else if (args.len == 1) {
				break :blk [_]c.wasm_valkind_t{args[0]};
			}
			break :blk [_]c.wasm_valkind_t{};
		};
		const argValTypes = comptime blk: {
			var num = 0;
			for(@typeInfo(@TypeOf(func)).@"fn".params[1..]) |param| {
				num += getNumberArgs(param.type.?);
			}
			var arguments: [num]c.wasm_valkind_t = undefined;
			num = 0;
			for(@typeInfo(@TypeOf(func)).@"fn".params[1..]) |param| {
				const argNumber = getNumberArgs(param.type.?);
				arguments[num..][0..argNumber].* = typeToValType(param.type.?);
				num += argNumber;
			}
			break :blk arguments;
		};
		var valTypes: [argValTypes.len]?*c.wasm_valtype_t = undefined;
		for(0..argValTypes.len) |i| {
			valTypes[i] = c.wasm_valtype_new(argValTypes[i]);
		}
		var retTypes: [retValTypes.len]?*c.wasm_valtype_t = undefined;
		for(0..retValTypes.len) |i| {
			retTypes[i] = c.wasm_valtype_new(retValTypes[i]);
		}
		const wrapper = struct {
			pub fn wrapped(env: ?*anyopaque, args: [*c]const c.wasm_val_vec_t, rets: [*c]c.wasm_val_vec_t) callconv(.c) ?*c.wasm_trap_t {
				const instance = @as(*main.wasm.WasmInstance.Env, @ptrCast(@alignCast(env.?))).instance;
				const ArgTuple, const types = comptime blk: {
					var types: [@typeInfo(@TypeOf(func)).@"fn".params.len]type = undefined;
					for(@typeInfo(@TypeOf(func)).@"fn".params, 0..) |param, i| {
						types[i] = param.type.?;
					}
					break :blk .{std.meta.Tuple(&types), types};
				};
				var arguments: ArgTuple = undefined;
				arguments[0] = instance;
				comptime var num = 0;
				inline for(@typeInfo(@TypeOf(func)).@"fn".params[1..], 1..) |param, i| {
					const argNumber = getNumberArgs(param.type.?);
					arguments[i] = instance.wasmToValue(types[i], args.*.data[num..][0..argNumber].*);
					num += argNumber;
				}
				const res = @call(.auto, func, arguments);
				if(@typeInfo(@TypeOf(func)).@"fn".return_type.? != void) {
					const out = instance.valueToWasm(@typeInfo(@TypeOf(func)).@"fn".return_type.?, res);
					c.wasm_val_vec_new(rets, out.len, &out);
				}
				return null;
			}
		}.wrapped;
		try self.addImportImpl(name, &wrapper, valTypes, retTypes);
	}

	fn addImportImpl(self: *WasmInstance, name: []const u8, func: c.wasm_func_callback_with_env_t, args: anytype, rets: anytype) !void {
		std.debug.assert(@typeInfo(@TypeOf(args)).array.child == ?*c.wasm_valtype_t);
		std.debug.assert(@typeInfo(@TypeOf(rets)).array.child == ?*c.wasm_valtype_t);
		const importIndex = self.getImport(name) orelse return error.ImportNotFound;
		var argVec: c.wasm_valtype_vec_t = undefined;
		c.wasm_valtype_vec_new(&argVec, args.len, &args);
		var retVec: c.wasm_valtype_vec_t = undefined;
		c.wasm_valtype_vec_new(&retVec, rets.len, &rets);
		const funcType = c.wasm_functype_new(&argVec, &retVec);
		const function = c.wasm_func_new_with_env(store, funcType, func, &self.env, null);
		self.importList[importIndex] = c.wasm_func_as_extern(function);
	}

	pub fn getImport(self: *WasmInstance, name: []const u8) ?usize {
		for(0..self.importTypes.size) |i| {
			const importType = self.importTypes.data[i];
			var importNameVec = c.wasm_importtype_name(importType).*;
			const importName = importNameVec.data[0..importNameVec.size];
			if(std.mem.eql(u8, name, importName)) {
				return i;
			}
		}
		return null;
	}

	pub fn getExport(self: *WasmInstance, name: []const u8) ?usize {
		for(0..self.exports.size) |i| {
			const exportType = self.exportTypes.data[i];
			var exportNameVec = c.wasm_exporttype_name(exportType).*;
			const exportName = exportNameVec.data[0..exportNameVec.size];
			if(std.mem.eql(u8, name, exportName)) {
				return i;
			}
		}
		return null;
	}

	pub fn invoke(self: *WasmInstance, comptime name: []const u8, args: anytype, comptime Return: type) !Return {
		comptime var len = 0;
		inline for(args) |arg| {
			len += getNumberArgs(@TypeOf(arg));
		}
		var arguments: [len]c.wasm_val_t = undefined;
		len = 0;
		inline for(args) |arg| {
			const argNumber = getNumberArgs(@TypeOf(arg));
			arguments[len..][0..argNumber].* = self.valueToWasm(@TypeOf(arg), arg);
			len += argNumber;
		}
		var ret = try self.invokeImpl(name, &arguments);
		return self.wasmToValue(Return, ret[0..getNumberArgs(Return)].*);
	}

	pub fn invokeImpl(self: *WasmInstance, name: []const u8, args: []c.wasm_val_t) ![]c.wasm_val_t {
		const externIndex = self.getExport(name) orelse return error.FunctionDoesNotExist;
		const externValue = self.exports.data[externIndex];
		const func = c.wasm_extern_as_func(externValue) orelse return error.ExportNotFunction;
		const funcType = c.wasm_func_type(func);
		var argVec: c.wasm_val_vec_t = .{.data = args.ptr, .size = args.len};
		const size = c.wasm_functype_results(funcType).*.size;
		var retVec: c.wasm_val_vec_t = undefined;
		c.wasm_val_vec_new_uninitialized(&retVec, size);
		if(c.wasm_func_call(func, &argVec, &retVec)) |trap| {
			printError("Failed to call function: {s}\n", trap);
		}
		return retVec.data[0..retVec.size];
	}

	pub fn alloc(self: *WasmInstance, amount: u32) !u32 {
		if(amount == 0) return 0;
		return try self.invoke("alloc", .{amount}, u32);
	}

	pub fn free(self: *WasmInstance, ptr: u32, len: u32) !void {
		if(len == 0) return;
		try self.invoke("free", .{ptr, len}, void);
	}

	fn createSliceFromWasm(self: *WasmInstance, start: c.wasm_val_t, len: c.wasm_val_t) ![]u8 {
		if(start.kind != c.WASM_I32) return error.TypeMustBeI32;
		if(len.kind != c.WASM_I32) return error.TypeMustBeI32;
		if(start.of.i32 < 0 or len.of.i32 <= 0) return &.{};
		const memory = c.wasm_memory_data(self.memory);
		return memory[@intCast(start.of.i32)..@intCast(start.of.i32 + len.of.i32)];
	}

	fn createWasmFromSlice(self: *WasmInstance, slice: []const u8) [2]c.wasm_val_t {
		const memory = c.wasm_memory_data(self.memory);
		const allocated = self.alloc(@intCast(slice.len)) catch unreachable;
		@memcpy(memory[allocated..allocated + slice.len], slice);
		return [_]c.wasm_val_t{
			.{.kind = c.WASM_I32, .of = .{.i32 = @bitCast(allocated)}},
			.{.kind = c.WASM_I32, .of = .{.i32 = @intCast(slice.len)}}
		};
	}

	pub fn setMemory(self: *WasmInstance, T: type, val: T, ptr: u32) void {
		const memory = c.wasm_memory_data(self.memory);
		std.mem.writeInt(std.meta.Int(.unsigned, @bitSizeOf(T)), memory[ptr..][0..@sizeOf(T)], @bitCast(val), .little);
	}

	pub fn getMemory(self: *WasmInstance, T: type, ptr: u32) T {
		const memory = c.wasm_memory_data(self.memory);
		return @bitCast(std.mem.readInt(std.meta.Int(.unsigned, @bitSizeOf(T)), memory[ptr..][0..@sizeOf(T)], .little));
	}
};

fn printError(comptime format: []const u8, trap: *c.wasm_trap_t) void {
	defer c.wasm_trap_delete(trap);

	var message: c.wasm_byte_vec_t = undefined;
	defer c.wasm_byte_vec_delete(&message);
	c.wasm_trap_message(trap, &message);
	std.log.err(format, .{message.data[0..message.size]});
}