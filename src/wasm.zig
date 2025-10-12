const std = @import("std");

pub const c = @cImport({
	@cInclude("wasm.h");
	@cInclude("wasmer.h");
});

const main = @import("main");

pub const WasmContext = struct {
	engine: ?*c.wasm_engine_t,
	store: ?*c.wasm_store_t,

	pub fn init() !WasmContext {
		const engine = c.wasm_engine_new() orelse return error.WasmInitError;
		const store = c.wasm_store_new(engine) orelse return error.WasmInitError;
		return .{
			.engine = engine,
			.store = store,
		};
	}

	pub fn deinit(self: WasmContext) void {
		c.wasm_engine_delete(self.engine);
		c.wasm_store_delete(self.store);
	}
};

pub const WasmInstance = struct {
	context: WasmContext,
	module: ?*c.wasm_module_t,
	instance: *c.wasm_instance_t,
	exportTypes: c.wasm_exporttype_vec_t,
	exports: c.wasm_extern_vec_t,

	pub fn init(context: WasmContext, file: std.fs.File, imports: c.wasm_extern_vec_t) !WasmInstance {
		var out: WasmInstance = .{
			.context = context,
			.module = undefined,
			.instance = undefined,
			.exportTypes = undefined,
			.exports = undefined,
		};
		const data = try file.readToEndAllocOptions(main.stackAllocator.allocator, std.math.maxInt(usize), null, .of(u8), 0);
		defer main.stackAllocator.free(data);
		var byteVec: c.wasm_byte_vec_t = .{.data = data.ptr, .size = data.len};
		out.module = c.wasm_module_new(context.store, &byteVec) orelse return error.WasmModuleError;
		out.instance = c.wasm_instance_new(context.store, out.module, &imports, null) orelse return error.WasmInstanceError;
		c.wasm_module_exports(out.module, &out.exportTypes);
		c.wasm_instance_exports(out.instance, &out.exports);
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
			defer c.wasm_name_delete(&exportNameVec);
			const exportName = exportNameVec.data[0..exportNameVec.size];
			if(std.mem.eql(u8, name, exportName)) {
				return self.exports.data[i];
			}
		}
		return null;
	}

	pub fn invoke(self: *WasmInstance, name: []const u8, args: []c.wasm_val_t, ret: []c.wasm_val_t) !void {
		const func = c.wasm_extern_as_func(self.getExtern(name) orelse return error.FunctionDoesNotExist) orelse return error.ExportNotFunction;
		var argVec: c.wasm_val_vec_t = .{.data = args.ptr, .size = args.len};
		var retVec: c.wasm_val_vec_t = .{.data = ret.ptr, .size = ret.len};
		if(c.wasm_func_call(func, &argVec, &retVec)) |trap| {
			printError("Failed to call function: {s}\n", trap);
		}
	}
};

fn printError(comptime format: []const u8, trap: *c.wasm_trap_t) void {
	defer c.wasm_trap_delete(trap);

	var message: c.wasm_byte_vec_t = undefined;
	defer c.wasm_byte_vec_delete(&message);
	c.wasm_trap_message(trap, &message);
	std.log.err(format, .{message.data[0..message.size]});
}