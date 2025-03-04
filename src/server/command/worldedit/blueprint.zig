const std = @import("std");

const main = @import("root");
const User = main.server.User;
const vec = main.vec;
const Vec3i = vec.Vec3i;

const List = main.List;
const Block = main.blocks.Block;
const Blueprint = main.blueprint.Blueprint;
const NeverFailingAllocator = main.utils.NeverFailingAllocator;

pub const description = "Operate on blueprints.";
pub const usage = "/blueprint <save FILENAME|delete FILENAME|load FILENAME|list>";

const BlueprintSubCommand = enum {
	save,
	delete,
	load,
	list,
	other,
	empty,

	fn fromString(string: []const u8) BlueprintSubCommand {
		return std.meta.stringToEnum(BlueprintSubCommand, string) orelse {
			if(string.len == 0) return .empty;
			return .other;
		};
	}
};

const red = "#e3273d";
const blue = "#4287f5";
const white = "#ffffff";
const green = "#04c441";

pub fn execute(args: []const u8, source: *User) void {
	var argsList = List([]const u8).init(main.stackAllocator);

	var splitIterator = std.mem.splitSequence(u8, args, " ");
	while(splitIterator.next()) |a| {
		argsList.append(main.stackAllocator.dupe(u8, a));
	}
	defer {
		for(argsList.items) |arg| {
			main.stackAllocator.free(arg);
		}
		argsList.deinit();
	}

	if(argsList.items.len < 1) {
		source.sendMessage("{s}Not enough arguments for /blueprint, expected at least 1.", .{red});
		return;
	}
	const subcommand = BlueprintSubCommand.fromString(argsList.items[0]);
	_ = switch(subcommand) {
		.save => blueprintSave(argsList, source),
		.delete => blueprintDelete(argsList, source),
		.load => blueprintLoad(argsList, source),
		.list => blueprintList(argsList, source),
		.other => {
			source.sendMessage("{s}Unrecognized subcommand for /blueprint: '{s}'", .{red, argsList.items[0]});
		},
		.empty => {
			source.sendMessage("{s}Missing subcommand for **/blueprint**, usage: {s}{s} ", .{red, white, usage});
		},
	} catch |err| {
		source.sendMessage("{s}Error: {s}", .{red, @errorName(err)});
	};
}

fn blueprintSave(args: List([]const u8), source: *User) !void {
	if(args.items.len < 2) {
		source.sendMessage("{s}**/blueprint save** requires FILENAME argument.", .{red});
		return;
	}
	if(args.items.len >= 3) {
		source.sendMessage("{s}Too many arguments for **/blueprint save**. Expected 1 argument, FILENAME.", .{red});
		return;
	}
	source.mutex.lock();
	defer source.mutex.unlock();

	if(source.commandData.clipboard) |clipboard| {
		const storedBlueprint = clipboard.store(main.stackAllocator);
		defer main.stackAllocator.free(storedBlueprint);

		const fileName: []const u8 = ensureBlueprintExtension(main.stackAllocator, args.items[1]);
		defer main.stackAllocator.free(fileName);

		var cwd = std.fs.cwd();

		_ = cwd.makeDir("blueprints") catch null;

		var blueprintsDir = try cwd.openDir("blueprints", .{});
		defer blueprintsDir.close();

		std.log.info("{s}Saving clipboard to blueprint file: {s}", .{blue, fileName});
		source.sendMessage("{s}Saving clipboard to blueprint file: {s}", .{blue, fileName});

		try blueprintsDir.writeFile(.{
			.sub_path = fileName,
			.data = storedBlueprint,
			.flags = .{.lock = .exclusive},
		});
	} else {
		source.sendMessage("{s}Error: No clipboard content to save.", .{red});
	}
}

fn ensureBlueprintExtension(allocator: NeverFailingAllocator, fileName: []const u8) []const u8 {
	if(!std.ascii.endsWithIgnoreCase(fileName, ".blp")) {
		return std.fmt.allocPrint(allocator.allocator, "{s}.blp", .{fileName}) catch unreachable;
	} else {
		return allocator.dupe(u8, fileName);
	}
}

fn blueprintDelete(_: List([]const u8), source: *User) void {
	source.sendMessage("{s}/blueprint delete not implemented.", .{red});
}

fn blueprintList(_: List([]const u8), source: *User) !void {
	var cwd = std.fs.cwd();

	_ = cwd.makeDir("blueprints") catch null;

	var blueprintsDir = try cwd.openDir("blueprints", .{.iterate = true});
	defer blueprintsDir.close();

	var directoryIterator = blueprintsDir.iterate();
	var index: i32 = 0;

	while(try directoryIterator.next()) |entry| {
		if(entry.kind != .file) break;
		if(!std.ascii.endsWithIgnoreCase(entry.name, ".blp")) break;

		source.sendMessage("{s}{}{s} {s}", .{white, index, blue, entry.name});
		index += 1;
	}
}

fn blueprintLoad(args: List([]const u8), source: *User) !void {
	if(args.items.len < 2) {
		source.sendMessage("{s}**/blueprint load** requires FILENAME argument.", .{red});
		return;
	}
	if(args.items.len >= 3) {
		source.sendMessage("{s}Too many arguments for **/blueprint load**. Expected 1 argument, FILENAME.", .{red});
		return;
	}
	source.mutex.lock();
	defer source.mutex.unlock();

	const fileName: []const u8 = ensureBlueprintExtension(main.stackAllocator, args.items[1]);
	defer main.stackAllocator.free(fileName);

	var cwd = std.fs.cwd();

	_ = cwd.makeDir("blueprints") catch null;

	var blueprintsDir = try cwd.openDir("blueprints", .{});
	defer blueprintsDir.close();

	std.log.info("{s}Loading blueprint file: {s}", .{blue, fileName});
	source.sendMessage("{s}Loading blueprint file: {s}", .{blue, fileName});

	const storedBlueprint = try blueprintsDir.readFileAlloc(main.stackAllocator.allocator, fileName, std.math.maxInt(u32));
	defer main.stackAllocator.free(storedBlueprint);

	if(source.commandData.clipboard != null) {
		try source.commandData.clipboard.?.load(storedBlueprint);
	} else {
		source.commandData.clipboard = Blueprint.init(main.globalAllocator);
		try source.commandData.clipboard.?.load(storedBlueprint);
	}
}
