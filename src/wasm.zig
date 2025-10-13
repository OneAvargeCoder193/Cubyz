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
	instance: *c.wasm_instance_t,
	exportTypes: c.wasm_exporttype_vec_t,
	importTypes: c.wasm_importtype_vec_t,
	exports: c.wasm_extern_vec_t,
	memory: ?*c.wasm_memory_t,
	currentSide: main.utils.Side,
	env: Env,
	importList: ?[]?*c.wasm_extern_t,

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
		return out;
	}

	pub fn deinit(self: *WasmInstance, allocator: main.heap.NeverFailingAllocator) void {
		c.wasm_module_delete(self.module);
		c.wasm_instance_delete(self.instance);
		c.wasm_exporttype_vec_delete(&self.exportTypes);
		c.wasm_extern_vec_delete(&self.exports);
		allocator.destroy(self);
		if(self.importList) |importList| {
			main.globalAllocator.free(importList);
		}
	}

	pub fn instantiate(self: *WasmInstance) !void {
		var imports: c.wasm_extern_vec_t = undefined;
		c.wasm_extern_vec_new(&imports, self.importList.?.len, self.importList.?.ptr);
		defer {
			c.wasm_extern_vec_delete(&imports);
			main.globalAllocator.free(self.importList.?);
			self.importList = null;
		}
		self.instance = c.wasm_instance_new(store, self.module, &imports, null) orelse {
			const err = main.stackAllocator.alloc(u8, @intCast(c.wasmer_last_error_length()));
			_ = c.wasmer_last_error_message(err.ptr, @intCast(err.len));
			std.log.err("{s}\n", .{err});
			return error.WasmInstanceError;
		};
		c.wasm_instance_exports(self.instance, &self.exports);
		self.memory = c.wasm_extern_as_memory(self.getExport("memory"));
	}

	pub fn addImport(self: *WasmInstance, name: []const u8, func: c.wasm_func_callback_with_env_t) !void {
		const importIndex = self.getImport(name) orelse return error.ImportNotFound;
		const importData = self.importTypes.data[importIndex];
		const importType = if(c.wasm_importtype_type(importData)) |ptr| @constCast(ptr) else null;
		const func_type = c.wasm_externtype_as_functype(importType);
		const function = c.wasm_func_new_with_env(store, func_type, func, &self.env, null);
		self.importList.?[importIndex] = c.wasm_func_as_extern(function);
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

	pub fn getExport(self: *WasmInstance, name: []const u8) ?*c.wasm_extern_t {
		for(0..self.exports.size) |i| {
			const exportType = self.exportTypes.data[i];
			var exportNameVec = c.wasm_exporttype_name(exportType).*;
			const exportName = exportNameVec.data[0..exportNameVec.size];
			if(std.mem.eql(u8, name, exportName)) {
				return self.exports.data[i];
			}
		}
		return null;
	}

	pub fn invoke(self: *WasmInstance, name: []const u8, args: []c.wasm_val_t, ret: []c.wasm_val_t) !void {
		const externValue = self.getExport(name) orelse return error.FunctionDoesNotExist;
		const func = c.wasm_extern_as_func(externValue) orelse return error.ExportNotFunction;
		var argVec: c.wasm_val_vec_t = .{.data = args.ptr, .size = args.len};
		var retVec: c.wasm_val_vec_t = .{.data = ret.ptr, .size = ret.len};
		if(c.wasm_func_call(func, &argVec, &retVec)) |trap| {
			printError("Failed to call function: {s}\n", trap);
		}
	}

	pub fn alloc(self: *WasmInstance, amount: usize) !usize {
		var args = [_]c.wasm_val_t{
			.{.kind = c.WASM_I32, .of = .{.@"i32" = @intCast(amount)}},
		};
		var ret: [1]c.wasm_val_t = undefined;
		try self.invoke("alloc", &args, &ret);
		return @intCast(ret[0].of.i32);
	}

	pub fn free(self: *WasmInstance, ptr: usize, len: usize) !void {
		var args = [_]c.wasm_val_t{
			.{.kind = c.WASM_I32, .of = .{.@"i32" = @intCast(ptr)}},
			.{.kind = c.WASM_I32, .of = .{.@"i32" = @intCast(len)}},
		};
		var ret: [0]c.wasm_val_t = undefined;
		try self.invoke("free", &args, &ret);
	}
};

fn printError(comptime format: []const u8, trap: *c.wasm_trap_t) void {
	defer c.wasm_trap_delete(trap);

	var message: c.wasm_byte_vec_t = undefined;
	defer c.wasm_byte_vec_delete(&message);
	c.wasm_trap_message(trap, &message);
	std.log.err(format, .{message.data[0..message.size]});
}