const std = @import("std");

pub fn generate(comptime T: type, allocator: std.mem.Allocator, rng: std.Random, max_size: u32) !T {
    return switch (@typeInfo(T)) {
        .int => |int_info| {
            if (int_info.signedness == .signed) {
                const max_val = @min(@as(i64, max_size), std.math.maxInt(T));
                const min_val = @max(-@as(i64, max_size), std.math.minInt(T));
                return @intCast(rng.intRangeLessThan(i64, min_val, max_val + 1));
            }
            const max_val = @min(@as(u64, max_size), std.math.maxInt(T));
            return @intCast(rng.uintLessThan(u64, max_val + 1));
        },
        .float => |float_info| switch (float_info.bits) {
            32 => @as(T, rng.float(f32)) * @as(f32, @floatFromInt(max_size)),
            64 => @as(T, rng.float(f64)) * @as(f64, @floatFromInt(max_size)),
            else => @compileError("Unsupported float type"),
        },
        .bool => rng.boolean(),
        .array => |array_info| {
            var result: T = undefined;
            for (&result) |*elem| {
                elem.* = try generate(array_info.child, allocator, rng, max_size);
            }
            return result;
        },
        .pointer => |ptr_info| {
            if (ptr_info.size != .Slice) @compileError("Only slices are supported for generation");
            if (ptr_info.child == u8) {
                const len = rng.uintLessThan(usize, @min(max_size, 64)) + 1;
                const bytes = try allocator.alloc(u8, len);
                for (bytes) |*byte| byte.* = rng.intRangeAtMost(u8, 32, 126);
                return bytes;
            }
            const len = rng.uintLessThan(usize, @min(max_size, 16)) + 1;
            const slice = try allocator.alloc(ptr_info.child, len);
            for (slice) |*elem| {
                elem.* = try generate(ptr_info.child, allocator, rng, max_size);
            }
            return slice;
        },
        .optional => |opt_info| if (rng.boolean()) try generate(opt_info.child, allocator, rng, max_size) else null,
        .@"struct" => |struct_info| {
            var result: T = undefined;
            if (struct_info.is_tuple) {
                inline for (struct_info.fields, 0..) |field, i| {
                    result[i] = try generate(field.type, allocator, rng, max_size);
                }
            } else {
                inline for (struct_info.fields) |field| {
                    @field(result, field.name) = try generate(field.type, allocator, rng, max_size);
                }
            }
            return result;
        },
        else => @compileError("Unsupported type for Zion test generation: " ++ @typeName(T)),
    };
}

pub fn deinit(comptime T: type, value: T, allocator: std.mem.Allocator) void {
    switch (@typeInfo(T)) {
        .pointer => |ptr_info| {
            if (ptr_info.size == .Slice) {
                if (ptr_info.child == u8 or @typeInfo(ptr_info.child) == .int or @typeInfo(ptr_info.child) == .float or @typeInfo(ptr_info.child) == .bool) {
                    allocator.free(value);
                } else {
                    for (value) |elem| deinit(ptr_info.child, elem, allocator);
                    allocator.free(value);
                }
            }
        },
        .@"struct" => |struct_info| {
            if (struct_info.is_tuple) {
                inline for (struct_info.fields, 0..) |field, i| deinit(field.type, value[i], allocator);
            } else {
                inline for (struct_info.fields) |field| deinit(field.type, @field(value, field.name), allocator);
            }
        },
        .array => |array_info| for (value) |elem| deinit(array_info.child, elem, allocator),
        .optional => |opt_info| if (value) |unwrapped| deinit(opt_info.child, unwrapped, allocator),
        else => {},
    }
}
