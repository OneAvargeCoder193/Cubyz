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
	exports: c.wasm_extern_vec_t,
	memory: ?*c.wasm_memory_t,

	pub const Env = struct {
		instance: *WasmInstance,
	};

	pub fn init(file: std.fs.File, imports: c.wasm_extern_vec_t) !WasmInstance {
		var out: WasmInstance = .{
			.module = undefined,
			.instance = undefined,
			.exportTypes = undefined,
			.exports = undefined,
			.memory = undefined,
		};
		const data = try file.readToEndAlloc(main.stackAllocator.allocator, std.math.maxInt(usize));
		defer main.stackAllocator.free(data);
		var byteVec: c.wasm_byte_vec_t = .{.data = data.ptr, .size = data.len};
		out.module = c.wasm_module_new(store, &byteVec) orelse {
			const err = main.stackAllocator.alloc(u8, @intCast(c.wasmer_last_error_length()));
			_ = c.wasmer_last_error_message(err.ptr, @intCast(err.len));
			std.debug.print("{s}\n", .{err});
			return error.WasmModuleError;
		};
		out.instance = c.wasm_instance_new(store, out.module, &imports, null) orelse {
			const err = main.stackAllocator.alloc(u8, @intCast(c.wasmer_last_error_length()));
			_ = c.wasmer_last_error_message(err.ptr, @intCast(err.len));
			std.debug.print("{s}\n", .{err});
			return error.WasmInstanceError;
		};
		c.wasm_module_exports(out.module, &out.exportTypes);
		c.wasm_instance_exports(out.instance, &out.exports);
		out.memory = c.wasm_extern_as_memory(out.getExtern("memory"));
		return out;
	}

	pub fn deinit(self: *WasmInstance) void {
		c.wasm_module_delete(self.module);
		c.wasm_instance_delete(self.instance);
		c.wasm_exporttype_vec_delete(&self.exportTypes);
		c.wasm_extern_vec_delete(&self.exports);
	}

	pub fn getExtern(self: *WasmInstance, name: []const u8) ?*c.wasm_extern_t {
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
		const externValue = self.getExtern(name) orelse return error.FunctionDoesNotExist;
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