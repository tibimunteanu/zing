// Objective-C runtime bindings vendored from mitchellh/zig-objc.
// Flattened into one file so the engine does not depend on an external package.
//
// MIT License
//
// Copyright (c) 2023 Mitchell Hashimoto
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

const std = @import("std");
const objc = @This();

pub const c = @import("objc-c");

const objc_c = struct {
    pub const c = objc.c;
    pub const boolResult = objc.boolResult;
    pub const boolParam = objc.boolParam;
};

/// On some targets, Objective-C uses `i8` instead of `bool`.
/// This helper casts a target value type to `bool`.
pub fn boolResult(result: c.BOOL) bool {
    return switch (c.BOOL) {
        bool => result,
        i8 => result == 1,
        else => @compileError("unexpected boolean type"),
    };
}

/// On some targets, Objective-C uses `i8` instead of `bool`.
/// This helper casts a `bool` value to the target value type.
pub fn boolParam(param: bool) c.BOOL {
    return switch (c.BOOL) {
        bool => param,
        i8 => @intFromBool(param),
        else => @compileError("unexpected boolean type"),
    };
}

const autorelease = struct {
    pub const AutoreleasePool = opaque {
        /// Create a new autorelease pool. To clean it up, call deinit.
        pub inline fn init() *@This() {
            return @ptrCast(objc_autoreleasePoolPush().?);
        }

        pub inline fn deinit(self: *@This()) void {
            objc_autoreleasePoolPop(self);
        }
    };

    // I'm not sure if these are internal or not... they aren't in any headers,
    // but its how autorelease pools are implemented.
    extern "c" fn objc_autoreleasePoolPush() ?*anyopaque;
    extern "c" fn objc_autoreleasePoolPop(?*anyopaque) void;
};

const selpkg = struct {

    // Shorthand, equivalent to Sel.registerName
    pub inline fn sel(name: [:0]const u8) selpkg.Sel {
        return selpkg.Sel.registerName(name);
    }

    pub const Sel = struct {
        value: c.SEL,

        /// Registers a method with the Objective-C runtime system, maps the
        /// method name to a selector, and returns the selector value.
        pub fn registerName(name: [:0]const u8) @This() {
            return .{
                .value = c.sel_registerName(name.ptr),
            };
        }

        /// Returns the name of the method specified by a given selector.
        pub fn getName(self: @This()) [:0]const u8 {
            return std.mem.span(c.sel_getName(self.value));
        }
    };
};

const property = struct {
    pub const Property = extern struct {
        value: c.objc_property_t,

        /// Returns the name of a property.
        pub fn getName(self: @This()) [:0]const u8 {
            return std.mem.span(c.property_getName(self.value));
        }

        /// Returns the value of a property attribute given the attribute name.
        pub fn copyAttributeValue(self: @This(), attr: [:0]const u8) ?[:0]u8 {
            const ptr = c.property_copyAttributeValue(self.value, attr.ptr) orelse return null;
            return std.mem.span(ptr);
        }

        comptime {
            std.debug.assert(@sizeOf(@This()) == @sizeOf(c.objc_property_t));
            std.debug.assert(@alignOf(@This()) == @alignOf(c.objc_property_t));
        }
    };
};

const protocol = struct {
    const cpkg = objc_c;
    const boolParam = cpkg.boolParam;
    const boolResult = cpkg.boolResult;

    pub const Protocol = extern struct {
        value: *c.Protocol,

        pub fn conformsToProtocol(self: @This(), other: @This()) bool {
            return cpkg.boolResult(c.protocol_conformsToProtocol(self.value, other.value));
        }

        pub fn isEqual(self: @This(), other: @This()) bool {
            return cpkg.boolResult(c.protocol_isEqual(self.value, other.value));
        }

        pub fn getName(self: @This()) [:0]const u8 {
            return std.mem.span(c.protocol_getName(self.value));
        }

        pub fn getProperty(
            self: @This(),
            name: [:0]const u8,
            is_required: bool,
            is_instance: bool,
        ) ?objc.Property {
            return .{ .value = c.protocol_getProperty(
                self.value,
                name,
                cpkg.boolParam(is_required),
                cpkg.boolParam(is_instance),
            ) orelse return null };
        }

        comptime {
            std.debug.assert(@sizeOf(@This()) == @sizeOf([*c]c.Protocol));
            std.debug.assert(@alignOf(@This()) == @alignOf([*c]c.Protocol));
        }
    };

    pub fn getProtocol(name: [:0]const u8) ?protocol.Protocol {
        return .{ .value = c.objc_getProtocol(name) orelse return null };
    }
};

const iterator = struct {

    // From <Foundation/NSEnumerator.h>.
    const NSFastEnumerationState = extern struct {
        state: c_ulong = 0,
        itemsPtr: ?[*]objc.c.id = null,
        mutationsPtr: ?*c_ulong = null,
        extra: [5]c_ulong = [_]c_ulong{0} ** 5,
    };

    /// An iterator that uses the fast enumeration protocol[1] to iterate over
    /// objects in an Objective-C collection. This can be used with any object
    /// that conforms to the `NSFastEnumeration` protocol.
    ///
    /// [1]: Nhttps://developer.apple.com/documentation/foundation/nsfastenumeration
    pub const Iterator = struct {
        object: objc.Object,
        sel: objc.Sel,
        state: NSFastEnumerationState = .{},
        initial_mutations_value: ?c_ulong = null,
        // Clang compiles `for…in` loops with a size 16 buffer.
        buffer: [16]objc.c.id = [_]objc.c.id{null} ** 16,
        slice: []const objc.c.id = &.{},

        pub fn init(obj: objc.Object) iterator.Iterator {
            return .{
                .object = obj,
                .sel = objc.sel("countByEnumeratingWithState:objects:count:"),
            };
        }

        pub fn next(self: *@This()) ?objc.Object {
            if (self.slice.len == 0) {
                // Ask for some more objects.
                const count = self.object.msgSend(c_ulong, self.sel, .{
                    &self.state,
                    &self.buffer,
                    self.buffer.len,
                });
                if (self.initial_mutations_value) |value| {
                    // Call the mutation handler if the mutations value has
                    // changed since the start of iteration.
                    if (value != self.state.mutationsPtr.?.*) {
                        objc.c.objc_enumerationMutation(self.object.value);
                    }
                } else {
                    self.initial_mutations_value = self.state.mutationsPtr.?.*;
                }
                self.slice = self.state.itemsPtr.?[0..count];
            }

            if (self.slice.len == 0) return null;

            const first = self.slice[0];
            self.slice = self.slice[1..];
            return objc.Object.fromId(first);
        }
    };
};

const encoding = struct {
    const assert = std.debug.assert;
    const testing = std.testing;

    /// how much space do we need to encode this type?
    fn comptimeN(comptime T: type) usize {
        comptime {
            const objc_encoding = objc.Encoding.init(T);

            // Figure out how much space we need
            return std.fmt.count("{f}", .{objc_encoding});
        }
    }

    /// Encode a type into a comptime string.
    pub fn comptimeEncode(comptime T: type) [comptimeN(T):0]u8 {
        comptime {
            const objc_encoding = objc.Encoding.init(T);

            // Build our final signature
            var buf: [comptimeN(T) + 1]u8 = undefined;
            const result = std.fmt.bufPrint(buf[0 .. buf.len - 1], "{f}", .{objc_encoding}) catch unreachable;
            buf[result.len] = 0;

            return buf[0..result.len :0].*;
        }
    }

    /// Encoding union which parses type information and turns it into Obj-C
    /// runtime Type Encodings.
    ///
    /// https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html
    pub const Encoding = union(enum) {
        char,
        int,
        short,
        long,
        longlong,
        uchar,
        uint,
        ushort,
        ulong,
        ulonglong,
        float,
        double,
        bool,
        void,
        char_string,
        object,
        class,
        selector,
        array: struct { arr_type: type, len: usize },
        structure: struct { struct_type: type, show_type_spec: bool },
        @"union": struct { union_type: type, show_type_spec: bool },
        bitfield: u32,
        pointer: struct { ptr_type: type, size: std.builtin.Type.Pointer.Size },
        function: std.builtin.Type.Fn,
        unknown,

        pub fn init(comptime T: type) encoding.Encoding {
            return switch (T) {
                i8, c_char => .char,
                c_short => .short,
                i32, c_int => .int,
                c_long => .long,
                i64, c_longlong => .longlong,
                u8 => .uchar,
                c_ushort => .ushort,
                u32, c_uint => .uint,
                c_ulong => .ulong,
                u64, c_ulonglong => .ulonglong,
                f32 => .float,
                f64 => .double,
                bool => .bool,
                void, anyopaque => .void,
                [*c]u8, [*c]const u8 => .char_string,
                c.SEL, objc.Sel => .selector,
                c.Class, objc.Class => .class,
                c.id, objc.Object => .object,
                else => switch (@typeInfo(T)) {
                    .@"opaque" => .void,
                    .@"enum" => |m| .init(m.tag_type),
                    .array => |arr| .{ .array = .{ .len = arr.len, .arr_type = arr.child } },
                    .@"struct" => |m| switch (m.layout) {
                        .@"packed" => .init(m.backing_integer.?),
                        else => .{ .structure = .{ .struct_type = T, .show_type_spec = true } },
                    },
                    .@"union" => .{ .@"union" = .{
                        .union_type = T,
                        .show_type_spec = true,
                    } },
                    .optional => |m| switch (@typeInfo(m.child)) {
                        .pointer => |ptr| .{ .pointer = .{ .ptr_type = m.child, .size = ptr.size } },
                        else => @compileError("unsupported non-pointer optional type: " ++ @typeName(T)),
                    },
                    .pointer => |ptr| .{ .pointer = .{ .ptr_type = T, .size = ptr.size } },
                    .@"fn" => |fn_info| .{ .function = fn_info },
                    else => @compileError("unsupported type: " ++ @typeName(T)),
                },
            };
        }

        pub fn format(
            comptime self: @This(),
            writer: anytype,
        ) !void {
            switch (self) {
                .char => try writer.writeAll("c"),
                .int => try writer.writeAll("i"),
                .short => try writer.writeAll("s"),
                .long => try writer.writeAll("l"),
                .longlong => try writer.writeAll("q"),
                .uchar => try writer.writeAll("C"),
                .uint => try writer.writeAll("I"),
                .ushort => try writer.writeAll("S"),
                .ulong => try writer.writeAll("L"),
                .ulonglong => try writer.writeAll("Q"),
                .float => try writer.writeAll("f"),
                .double => try writer.writeAll("d"),
                .bool => try writer.writeAll("B"),
                .void => try writer.writeAll("v"),
                .char_string => try writer.writeAll("*"),
                .object => try writer.writeAll("@"),
                .class => try writer.writeAll("#"),
                .selector => try writer.writeAll(":"),
                .array => |a| {
                    try writer.print("[{}", .{a.len});
                    const encode_type = init(a.arr_type);
                    try encode_type.format(writer);
                    try writer.writeAll("]");
                },
                .structure => |s| {
                    const struct_info = @typeInfo(s.struct_type);
                    assert(struct_info.@"struct".layout == .@"extern");

                    // Strips the fully qualified type name to leave just the
                    // type name. Used in naming the Struct in an encoding.
                    var type_name_iter = std.mem.splitBackwardsScalar(u8, @typeName(s.struct_type), '.');
                    const type_name = type_name_iter.first();
                    try writer.print("{{{s}", .{type_name});

                    // if the encoding should show the internal type specification
                    // of the struct (determined by levels of pointer indirection)
                    if (s.show_type_spec) {
                        try writer.writeAll("=");
                        inline for (struct_info.@"struct".fields) |field| {
                            const field_encode = init(field.type);
                            try field_encode.format(writer);
                        }
                    }

                    try writer.writeAll("}");
                },
                .@"union" => |u| {
                    const union_info = @typeInfo(u.union_type);
                    assert(union_info.@"union".layout == .@"extern");

                    // Strips the fully qualified type name to leave just the
                    // type name. Used in naming the Union in an encoding
                    var type_name_iter = std.mem.splitBackwardsScalar(u8, @typeName(u.union_type), '.');
                    const type_name = type_name_iter.first();
                    try writer.print("({s}", .{type_name});

                    // if the encoding should show the internal type specification
                    // of the Union (determined by levels of pointer indirection)
                    if (u.show_type_spec) {
                        try writer.writeAll("=");
                        inline for (union_info.@"union".fields) |field| {
                            const field_encode = init(field.type);
                            try field_encode.format(writer);
                        }
                    }

                    try writer.writeAll(")");
                },
                .bitfield => |b| try writer.print("b{}", .{b}), // not sure if needed from Zig -> Obj-C
                .pointer => |p| {
                    switch (p.size) {
                        .one => {
                            // get the pointer info (count of levels of direction
                            // and the underlying type)
                            const pointer_info = indirectionCountAndType(p.ptr_type);
                            for (0..pointer_info.indirection_levels) |_| {
                                try writer.writeAll("^");
                            }

                            // create a new Encoding union from the pointers child
                            // type, giving an encoding of the underlying pointer type
                            comptime var child_encoding = init(pointer_info.child);

                            // if the indirection levels are greater than 1, for
                            // certain types that means getting rid of it's
                            // internal type specification
                            //
                            // https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html#//apple_ref/doc/uid/TP40008048-CH100
                            if (pointer_info.indirection_levels > 1) {
                                switch (child_encoding) {
                                    .structure => |*s| s.show_type_spec = false,
                                    .@"union" => |*u| u.show_type_spec = false,
                                    else => {},
                                }
                            }

                            // call this format function again, this time with the child type encoding
                            try child_encoding.format(writer);
                        },
                        else => @compileError("Pointer size not supported for encoding"),
                    }
                },
                .function => |fn_info| {
                    assert(std.meta.eql(fn_info.calling_convention, std.builtin.CallingConvention.c));

                    // Return type is first in a method encoding
                    const ret_type_enc = init(fn_info.return_type.?);
                    try ret_type_enc.format(writer);
                    inline for (fn_info.params) |param| {
                        const param_enc = init(param.type.?);
                        try param_enc.format(writer);
                    }
                },
                .unknown => {},
            }
        }
    };

    /// This comptime function gets the levels of indirection from a type. If the type is a pointer type it
    /// returns the underlying type from the pointer (the child) by walking the pointer to that child.
    /// Returns the type and 0 for count if the type isn't a pointer
    fn indirectionCountAndType(comptime T: type) struct {
        child: type,
        indirection_levels: comptime_int,
    } {
        var WalkType = T;
        var count: usize = 0;
        while (@typeInfo(WalkType) == .pointer) : (count += 1) {
            WalkType = @typeInfo(WalkType).pointer.child;
        }

        return .{ .child = WalkType, .indirection_levels = count };
    }

    fn encodingMatchesType(comptime T: type, expected_encoding: []const u8) !void {
        var buf: [200]u8 = undefined;
        const enc = encoding.Encoding.init(T);
        const enc_string = try std.fmt.bufPrint(&buf, "{f}", .{enc});
        try testing.expectEqualStrings(expected_encoding, enc_string);
    }
};

const msg_send = struct {
    const builtin = @import("builtin");
    const assert = std.debug.assert;

    /// Returns a struct that implements the msgSend function for type T.
    pub fn MsgSend(comptime T: type) type {
        // 1. T should be a struct
        // 2. T should have a field "value" that can be an "id" (same size)

        return struct {
            /// Invoke a selector on the target, i.e. an instance method on an
            /// object or a class method on a class. The args should be a tuple.
            pub fn msgSend(
                target: T,
                comptime Return: type,
                sel_raw: anytype,
                args: anytype,
            ) Return {
                // Our one special-case: If the return type is our own Object
                // type then we wrap it.
                const is_object = Return == objc.Object;

                // Our actual return value is an "id" if we are using one of
                // our built-in types (see above). Otherwise, we trust the caller.
                const RealReturn = if (is_object) c.id else Return;

                // We accept multiple types for sel but we need to turn it into
                // an objc.sel ultimately.
                const selector: objc.Sel = switch (@TypeOf(sel_raw)) {
                    objc.Sel => sel_raw,
                    else => objc.sel(sel_raw),
                };

                // Build our function type and call it
                const Fn = MsgSendFn(RealReturn, @TypeOf(target.value), @TypeOf(args));
                const msg_send_fn = comptime msgSendPtr(RealReturn, false);
                const msg_send_ptr: *const Fn = @ptrCast(@alignCast(msg_send_fn));

                // Unwrap any Object types in args to their underlying c.id
                const unwrapped_args = buildUnwrappedArgs(args);
                const result = @call(.auto, msg_send_ptr, .{ target.value, selector.value } ++ unwrapped_args);

                if (!is_object) return result;
                return .{ .value = result };
            }

            /// Invoke a selector on the superclass.
            pub fn msgSendSuper(
                target: T,
                superclass: objc.Class,
                comptime Return: type,
                sel_raw: anytype,
                args: anytype,
            ) Return {
                // See msgSend for in depth comments on all of this. This is
                // effectively the same logic.
                const is_object = Return == objc.Object;
                const RealReturn = if (is_object) c.id else Return;
                const selector: objc.Sel = switch (@TypeOf(sel_raw)) {
                    objc.Sel => sel_raw,
                    else => objc.sel(sel_raw),
                };

                const Fn = MsgSendFn(RealReturn, *c.objc_super, @TypeOf(args));
                const msg_send_fn = comptime msgSendPtr(RealReturn, true);
                const msg_send_ptr: *const Fn = @ptrCast(@alignCast(msg_send_fn));
                var super: c.objc_super =
                    if (comptime @hasField(c.objc_super, "super_class"))
                        .{
                            .receiver = target.value,
                            .super_class = superclass.value,
                        }
                    else
                        .{
                            .receiver = target.value,
                            .class = superclass.value,
                        };

                // Unwrap any Object types in args to their underlying c.id
                const unwrapped_args = buildUnwrappedArgs(args);
                const result = @call(.auto, msg_send_ptr, .{ &super, selector.value } ++ unwrapped_args);

                if (!is_object) return result;
                return .{ .value = result };
            }

            /// Returns the objc_msgSend or objc_msgSendSuper pointer for the
            /// given return type.
            fn msgSendPtr(
                comptime Return: type,
                comptime super: bool,
            ) *const fn () callconv(.c) void {
                // See objc/message.h. The high-level is that depending on the
                // target architecture and return type, we must use a different
                // objc_msgSend function.
                return switch (builtin.target.cpu.arch) {
                    // Aarch64 uses objc_msgSend for everything. Hurray!
                    .aarch64 => if (super) &c.objc_msgSendSuper else &c.objc_msgSend,

                    // x86_64 depends on the return type...
                    .x86_64 => switch (@typeInfo(Return)) {
                        // Most types use objc_msgSend
                        inline .int,
                        .bool,
                        .@"enum",
                        .pointer,
                        .void,
                        => if (super) &c.objc_msgSendSuper else &c.objc_msgSend,

                        .optional => |opt| opt: {
                            assert(@typeInfo(opt.child) == .pointer);
                            break :opt if (super) &c.objc_msgSendSuper else &c.objc_msgSend;
                        },

                        // Structs must use objc_msgSend_stret.
                        // NOTE: This is probably WAY more complicated... we only
                        // call this if the struct is NOT returned as a register.
                        // And that depends on the size of the struct. But I don't
                        // know what the breakpoint actually is for that. This SO
                        // answer says 16 bytes so I'm going to use that but I have
                        // no idea...
                        .@"struct" => blk: {
                            if (@sizeOf(Return) > 16) {
                                break :blk if (super)
                                    &c.objc_msgSendSuper_stret
                                else
                                    &c.objc_msgSend_stret;
                            } else {
                                break :blk if (super)
                                    &c.objc_msgSendSuper
                                else
                                    &c.objc_msgSend;
                            }
                        },

                        // Floats use objc_msgSend_fpret for f64 on x86_64,
                        // but normal msgSend for other bit sizes. i386 has
                        // more complex rules but we don't support i386 at the time
                        // of this comment and probably never will since all i386
                        // Apple models are discontinued at this point.
                        .float => |float| switch (float.bits) {
                            64 => if (super) &c.objc_msgSendSuper_fpret else &c.objc_msgSend_fpret,
                            else => if (super) &c.objc_msgSendSuper else &c.objc_msgSend,
                        },

                        // Otherwise we log in case we need to add a new case above
                        else => {
                            @compileLog(@typeInfo(Return));
                            @compileError("unsupported return type for objc runtime on x86_64");
                        },
                    },

                    else => @compileError("unsupported objc architecture"),
                };
            }
        };
    }

    /// This returns a function body type for `obj_msgSend` that matches
    /// the given return type, target type, and arguments tuple type.
    ///
    /// obj_msgSend is a really interesting function, because it doesn't act
    /// like a typical function. You have to call it with the C ABI as if you're
    /// calling the true target function, not as a varargs C function. Therefore
    /// you have to cast obj_msgSend to a function pointer type of the final
    /// destination function, then call that.
    ///
    /// Example: you have an ObjC function like this:
    ///
    ///     @implementation Foo
    ///     - (void)log: (float)x { /* stuff */ }
    ///
    /// If you call it like this, it won't work (you'll get garbage):
    ///
    ///     objc_msgSend(obj, @selector(log:), (float)PI);
    ///
    /// You have to call it like this:
    ///
    ///     ((void (*)(id, SEL, float))objc_msgSend)(obj, @selector(log:), M_PI);
    ///
    /// This comptime function returns the function body type that can be used
    /// to cast and call for the proper C ABI behavior.
    fn MsgSendFn(
        comptime Return: type,
        comptime Target: type,
        comptime Args: type,
    ) type {
        const argsInfo = @typeInfo(Args).@"struct";
        assert(argsInfo.is_tuple);

        // Target must always be an "id". Lots of types (Class, Object, etc.)
        // are an "id" so we just make sure the sizes match for ABI reasons.
        assert(@sizeOf(Target) == @sizeOf(c.id));

        // Build up our argument types for @Fn
        var param_types: [argsInfo.fields.len + 2]type = undefined;
        param_types[0] = Target;
        param_types[1] = c.SEL;
        for (argsInfo.fields, 0..) |field, i| param_types[i + 2] = unwrapType(field.type);

        return @Fn(&param_types, &@splat(.{}), Return, .{ .@"callconv" = .c });
    }

    fn UnwrappedArgs(comptime Args: type) type {
        const fields = @typeInfo(Args).@"struct".fields;
        var types: [fields.len]type = undefined;
        for (fields, 0..) |field, i| types[i] = unwrapType(field.type);
        return @Tuple(&types);
    }

    /// Maps objc wrapper types to their underlying C types for use in @Fn signatures,
    /// and validates that all other types are C-ABI compatible.
    fn unwrapType(comptime T: type) type {
        // Unwrap our objc.Object type
        if (T == objc.Object) return c.id;

        // Unwrap any other objc wrapper (Class, Sel, etc.) — identified by having
        // a single 'value' field of pointer size. Return the actual field type
        // rather than c.id, since Class and Sel have distinct pointer types.
        if (@typeInfo(T) == .@"struct") {
            const info = @typeInfo(T).@"struct";
            for (info.fields) |field| {
                if (std.mem.eql(u8, field.name, "value") and @sizeOf(field.type) == @sizeOf(c.id)) {
                    return field.type;
                }
            }
        }

        // Validate that the remaining type is safe to pass over the C ABI.
        // Previously (pre-0.16), passing a non-C-compatible type like []const u8
        // would silently compile but segfault at runtime via objc_msgSend.
        // These checks turn that into a compile error.
        switch (@typeInfo(T)) {
            .int, .float, .bool, .void => {},
            .@"enum" => {},
            .pointer => {},
            .optional => |opt| {
                if (@typeInfo(opt.child) != .pointer)
                    @compileError("msgSend: " ++ @typeName(T) ++ " — optional must wrap a pointer");
            },
            .@"struct" => |s| {
                if (s.layout != .@"extern" and s.layout != .@"packed")
                    @compileError("msgSend: " ++ @typeName(T) ++ " — struct must be extern or packed");
            },
            .@"union" => |u| {
                if (u.layout != .@"extern")
                    @compileError("msgSend: " ++ @typeName(T) ++ " — union must be extern");
            },
            else => @compileError("msgSend: " ++ @typeName(T) ++ " — not C-ABI compatible"),
        }

        return T;
    }

    inline fn buildUnwrappedArgs(args: anytype) UnwrappedArgs(@TypeOf(args)) {
        const fields = @typeInfo(@TypeOf(args)).@"struct".fields;
        var result: UnwrappedArgs(@TypeOf(args)) = undefined;
        inline for (fields, 0..) |_, i| {
            result[i] = if (unwrapType(@TypeOf(args[i])) != @TypeOf(args[i]))
                args[i].value
            else
                args[i];
        }
        return result;
    }
};

const object = struct {
    const cpkg = objc_c;
    const boolResult = cpkg.boolResult;
    const MsgSend = msg_send.MsgSend;
    const Iterator = iterator.Iterator;

    /// Object is an instance of a class.
    pub const Object = struct {
        value: c.id,

        // Implement msgSend
        const message_sender = MsgSend(@This());
        pub const msgSend = message_sender.msgSend;
        pub const msgSendSuper = message_sender.msgSendSuper;

        /// Convert a raw "id" into an Object. id must fit the size of the
        /// normal C "id" type (i.e. a `usize`).
        pub fn fromId(id: anytype) @This() {
            if (@sizeOf(@TypeOf(id)) != @sizeOf(c.id)) {
                @compileError("invalid id type");
            }

            // Some pointers in Objective-C are "tagged pointers", which
            // may be used for small objects and literals (NSNumber, NSString).
            // It's an internal implementation detail that replaces heap
            // allocation with direct encoding within the pointer itself.
            // This may result in UNALIGNED POINTERS!
            const ptr: c.id = blk: {
                @setRuntimeSafety(false);
                break :blk @ptrCast(@alignCast(id));
            };

            return .{ .value = ptr };
        }

        /// Returns the class of an object.
        pub fn getClass(self: @This()) ?objc.Class {
            return objc.Class{
                .value = c.object_getClass(self.value) orelse return null,
            };
        }

        /// Returns the class name of a given object.
        pub fn getClassName(self: @This()) [:0]const u8 {
            return std.mem.span(c.object_getClassName(self.value));
        }

        /// Set a property. This is a helper around getProperty and is
        /// strictly less performant than doing it manually. Consider doing
        /// this manually if performance is critical.
        pub fn setProperty(self: @This(), comptime n: [:0]const u8, v: anytype) void {
            const cls = self.getClass().?;
            const setter = setter: {
                // See getProperty for why we do this.
                if (cls.getProperty(n)) |prop| {
                    if (prop.copyAttributeValue("S")) |val| {
                        defer objc.free(val);
                        break :setter objc.sel(val);
                    }
                }

                break :setter objc.sel(
                    "set" ++
                        [1]u8{std.ascii.toUpper(n[0])} ++
                        n[1..n.len] ++
                        ":",
                );
            };

            self.msgSend(void, setter, .{v});
        }

        /// Get a property. This is a helper around Class.getProperty and is
        /// strictly less performant than doing it manually. Consider doing
        /// this manually if performance is critical.
        pub fn getProperty(self: @This(), comptime T: type, comptime n: [:0]const u8) T {
            const cls = self.getClass().?;
            const getter = getter: {
                // Sometimes a property is not a property because it has been
                // overloaded or something. I've found numerous occasions the
                // Apple docs are just wrong, so we try to read it as a property
                // but if we can't then we just call it as-is.
                if (cls.getProperty(n)) |prop| {
                    if (prop.copyAttributeValue("G")) |val| {
                        defer objc.free(val);
                        break :getter objc.sel(val);
                    }
                }

                break :getter objc.sel(n);
            };

            return self.msgSend(T, getter, .{});
        }

        pub fn copy(self: @This(), size: usize) @This() {
            return fromId(c.object_copy(self.value, size));
        }

        pub fn dispose(self: @This()) void {
            _ = c.object_dispose(self.value);
        }

        pub fn isClass(self: @This()) bool {
            return cpkg.boolResult(c.object_isClass(self.value));
        }

        pub fn getInstanceVariable(self: @This(), name: [:0]const u8) @This() {
            const ivar = c.object_getInstanceVariable(self.value, name, null);
            return fromId(c.object_getIvar(self.value, ivar));
        }

        pub fn setInstanceVariable(self: @This(), name: [:0]const u8, val: @This()) void {
            const ivar = c.object_getInstanceVariable(self.value, name, null);
            c.object_setIvar(self.value, ivar, val.value);
        }

        pub fn retain(self: @This()) @This() {
            return fromId(objc_retain(self.value));
        }

        pub fn release(self: @This()) void {
            objc_release(self.value);
        }

        /// Return an iterator for this object. The object must implement the
        /// `NSFastEnumeration` protocol.
        pub fn iterate(self: @This()) iterator.Iterator {
            return iterator.Iterator.init(self);
        }
    };

    extern "c" fn objc_retain(objc.c.id) objc.c.id;
    extern "c" fn objc_release(objc.c.id) void;

    fn retainCount(obj: object.Object) c_ulong {
        return obj.msgSend(c_ulong, objc.Sel.registerName("retainCount"), .{});
    }
};

const class = struct {
    const assert = std.debug.assert;
    const cpkg = objc_c;
    const boolResult = cpkg.boolResult;
    const MsgSend = msg_send.MsgSend;

    pub const Class = struct {
        value: c.Class,

        // Implement msgSend
        const message_sender = MsgSend(@This());
        pub const msgSend = message_sender.msgSend;
        pub const msgSendSuper = message_sender.msgSendSuper;

        // Returns a property with a given name of a given class.
        pub fn getProperty(self: @This(), name: [:0]const u8) ?objc.Property {
            return objc.Property{
                .value = c.class_getProperty(self.value, name.ptr) orelse return null,
            };
        }

        /// Describes the properties declared by a class. This must be freed.
        pub fn copyPropertyList(self: @This()) []objc.Property {
            var count: c_uint = undefined;
            const list = @as([*c]objc.Property, @ptrCast(c.class_copyPropertyList(self.value, &count)));
            if (count == 0) return list[0..0];
            return list[0..count];
        }

        /// Describes the protocols adopted by a class. This must be freed.
        pub fn copyProtocolList(self: @This()) []objc.Protocol {
            var count: c_uint = undefined;
            const list = @as([*c]objc.Protocol, @ptrCast(c.class_copyProtocolList(self.value, &count)));
            if (count == 0) return list[0..0];
            return list[0..count];
        }

        pub fn isMetaClass(self: @This()) bool {
            return cpkg.boolResult(c.class_isMetaClass(self.value));
        }

        pub fn getInstanceSize(self: @This()) usize {
            return c.class_getInstanceSize(self.value);
        }

        pub fn respondsToSelector(self: @This(), selector: objc.Sel) bool {
            return cpkg.boolResult(c.class_respondsToSelector(self.value, selector.value));
        }

        pub fn conformsToProtocol(self: @This(), proto: objc.Protocol) bool {
            return cpkg.boolResult(c.class_conformsToProtocol(self.value, &proto.value));
        }

        // currently only allows for overriding methods previously defined, e.g. by a superclass.
        // imp should be a function with C calling convention
        // whose first two arguments are a `c.id` and a `c.SEL`.
        pub fn replaceMethod(self: @This(), name: [:0]const u8, imp: anytype) void {
            const fn_info = @typeInfo(@TypeOf(imp)).@"fn";
            assert(std.meta.eql(fn_info.calling_convention, std.builtin.CallingConvention.c));
            assert(fn_info.is_var_args == false);
            assert(fn_info.params.len >= 2);
            assert(fn_info.params[0].type == c.id);
            assert(fn_info.params[1].type == c.SEL);
            _ = c.class_replaceMethod(self.value, objc.sel(name).value, @ptrCast(&imp), null);
        }

        // allows adding new methods; returns true on success.
        // imp should be a function with C calling convention
        // whose first two arguments are a `c.id` and a `c.SEL`.
        pub fn addMethod(self: @This(), name: [:0]const u8, imp: anytype) bool {
            const Fn = @TypeOf(imp);
            const fn_info = @typeInfo(Fn).@"fn";
            assert(std.meta.eql(fn_info.calling_convention, std.builtin.CallingConvention.c));
            assert(fn_info.is_var_args == false);
            assert(fn_info.params.len >= 2);
            assert(fn_info.params[0].type == c.id);
            assert(fn_info.params[1].type == c.SEL);
            const fn_encoding = comptime objc.comptimeEncode(Fn);
            return cpkg.boolResult(c.class_addMethod(
                self.value,
                objc.sel(name).value,
                @ptrCast(&imp),
                &fn_encoding,
            ));
        }

        // only call this function between allocateClassPair and registerClassPair
        // this adds an Ivar of type `id`.
        pub fn addIvar(self: @This(), name: [:0]const u8) bool {
            // The return type is i8 when we're cross compiling, unsure why.
            const result = c.class_addIvar(self.value, name, @sizeOf(c.id), @alignOf(c.id), "@");
            return cpkg.boolResult(result);
        }
    };

    pub fn getClass(name: [:0]const u8) ?class.Class {
        return .{ .value = c.objc_getClass(name.ptr) orelse return null };
    }

    pub fn getMetaClass(name: [:0]const u8) ?class.Class {
        return .{ .value = c.objc_getMetaClass(name) orelse return null };
    }

    // begin by calling this function, then call registerClassPair on the result when you are finished
    pub fn allocateClassPair(superclass: ?class.Class, name: [:0]const u8) ?class.Class {
        return .{ .value = c.objc_allocateClassPair(
            if (superclass) |cls| cls.value else null,
            name.ptr,
            0,
        ) orelse return null };
    }

    pub fn registerClassPair(klass: class.Class) void {
        c.objc_registerClassPair(klass.value);
    }

    pub fn disposeClassPair(klass: class.Class) void {
        c.objc_disposeClassPair(klass.value);
    }
};

const block = struct {
    const assert = std.debug.assert;
    const Allocator = std.mem.Allocator;

    // We have to use the raw C allocator for all heap allocation in here
    // because the objc runtime expects `malloc` to be used. If you don't use
    // malloc you'll get segfaults because the objc runtime will try to free
    // the memory with `free`.
    const alloc = std.heap.raw_c_allocator;

    /// Creates a new block type with captured (closed over) values.
    ///
    /// The CapturesArg is the a struct of captured values that will become
    /// available to the block. The Args is a tuple of types that are additional
    /// invocation-time arguments to the function. The Return param is the return
    /// type of the function.
    ///
    /// Within the CapturesArg, only `objc.c.id` values will be automatically
    /// memory managed (retained and released) when the block is copied.
    /// If you are passing through NSObjects, you should use the `objc.c.id`
    /// type and recreate a richer Zig type on the other side.
    ///
    /// The function that must be implemented is available as the `Fn` field.
    /// The first argument to the function is always a pointer to the `Context`
    /// type (see field in the struct). This has the captured values.
    ///
    /// The captures struct is always available as the `Captures` field which
    /// makes it easy to use an inline type definition for the argument and
    /// reference the type in a named fashion later.
    ///
    /// The returned block type can be initialized and invoked multiple times
    /// for different captures and arguments.
    ///
    /// See the tests for an example.
    pub fn Block(
        comptime CapturesArg: type,
        comptime Args: anytype,
        comptime Return: type,
    ) type {
        return struct {
            const Self = @This();
            const captures_info = @typeInfo(Captures).@"struct";
            const InvokeFn = FnType(anyopaque);
            const descriptor: Descriptor = .{
                .reserved = 0,
                .size = @sizeOf(Context),
                .copy_helper = &descCopyHelper,
                .dispose_helper = &descDisposeHelper,
                .signature = &objc.comptimeEncode(InvokeFn),
            };

            /// This is the function type that is called back.
            pub const Fn = FnType(Context);

            /// The captures type, so it can be easily referenced again.
            pub const Captures = CapturesArg;

            /// This is the block context sent as the first paramter to the function.
            pub const Context = BlockContext(Captures, InvokeFn);

            /// Create a new block context. The block context is what is passed
            /// (by reference) to functions that request a block.
            ///
            /// Note that if the captures contain reference types (like
            /// NSObject), they will NOT be retained/released UNTIL the block
            /// is copied. A block copy happens automatically when the block
            /// is copied to a function that expects a block in ObjC.
            ///
            /// If you want to manualy copy a block, you can use the `copy`
            /// function but you must pair it with a `dispose` function. This
            /// should only be done for blocks that are not passed to external
            /// functions where the runtime will automatically copy them (C,
            /// C++, ObjC, etc.).
            pub fn init(captures: Captures, func: *const Fn) Context {
                // The block starts as a stack-allocated block. We let the
                // runtime copy it to the heap. It doesn't seem to be advisable
                // to allocate it on the heap directly since the way refcounting
                // is done and so on is all private API.
                var ctx: Context = undefined;
                ctx.isa = NSConcreteStackBlock;
                ctx.flags = .{
                    .copy_dispose = true,
                    .stret = @typeInfo(Return) == .@"struct",
                    .signature = true,
                };
                ctx.invoke = @ptrCast(func);
                ctx.descriptor = &descriptor;
                inline for (captures_info.fields) |field| {
                    @field(ctx, field.name) = @field(captures, field.name);
                }

                return ctx;
            }

            /// Invoke the block with the given arguments. The arguments are
            /// the arguments to pass to the function beyond the captured scope.
            pub fn invoke(ctx: *const Context, args: anytype) Return {
                return @call(
                    .auto,
                    ctx.invoke,
                    .{ctx} ++ args,
                );
            }

            /// Copies the given context by either literally copying it
            /// to the heap or increasing the reference count. This must be
            /// paired with a `release` call to release the block.
            pub fn copy(ctx: *const Context) Allocator.Error!*Context {
                const copied = _Block_copy(@ptrCast(@alignCast(ctx))) orelse
                    return error.OutOfMemory;
                return @ptrCast(@alignCast(copied));
            }

            /// Release a copied block context. This must only be called on
            /// contexts returned by the `copy` function. If you pass a block
            /// context that was not copied, this will crash.
            pub fn release(ctx: *const Context) void {
                assert(@intFromPtr(ctx.isa) == @intFromPtr(NSConcreteMallocBlock));
                _Block_release(@ptrCast(@alignCast(ctx)));
            }

            fn descCopyHelper(dst: *anyopaque, src: *anyopaque) callconv(.c) void {
                const real_dst: *Context = @ptrCast(@alignCast(dst));
                const real_src: *Context = @ptrCast(@alignCast(src));
                inline for (captures_info.fields) |field| {
                    if (field.type == objc.c.id) {
                        _Block_object_assign(
                            @ptrCast(&@field(real_dst, field.name)),
                            @field(real_src, field.name),
                            .object,
                        );
                    }
                }
            }

            fn descDisposeHelper(src: *anyopaque) callconv(.c) void {
                const real_src: *Context = @ptrCast(@alignCast(src));
                inline for (captures_info.fields) |field| {
                    if (field.type == objc.c.id) {
                        _Block_object_dispose(
                            @field(real_src, field.name),
                            .object,
                        );
                    }
                }
            }

            /// Creates a function type for the invocation function, but alters
            /// the first arg. The first arg is a pointer so from an ABI perspective
            /// this is always the same and can be safely casted.
            fn FnType(comptime ContextArg: type) type {
                var param_types: [Args.len + 1]type = undefined;
                param_types[0] = *const ContextArg;
                for (Args, 1..) |Arg, i| param_types[i] = Arg;

                return @Fn(&param_types, &@splat(.{}), Return, .{ .@"callconv" = .c });
            }
        };
    }

    /// This is the type of a block structure that is passed as the first
    /// argument to any block invocation. See Block.
    fn BlockContext(comptime Captures: type, comptime InvokeFn: type) type {
        const captures_info = @typeInfo(Captures).@"struct";
        var fields: [captures_info.fields.len + 5]std.builtin.Type.StructField = undefined;
        fields[0] = .{
            .name = "isa",
            .type = ?*anyopaque,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(*anyopaque),
        };
        fields[1] = .{
            .name = "flags",
            .type = BlockFlags,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(c_int),
        };
        fields[2] = .{
            .name = "reserved",
            .type = c_int,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(c_int),
        };
        fields[3] = .{
            .name = "invoke",
            .type = *const InvokeFn,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @typeInfo(*const InvokeFn).pointer.alignment,
        };
        fields[4] = .{
            .name = "descriptor",
            .type = *const Descriptor,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(*Descriptor),
        };

        for (captures_info.fields, 5..) |capture, i| {
            switch (capture.type) {
                comptime_int => @compileError("capture should not be a comptime_int, try using @as"),
                comptime_float => @compileError("capture should not be a comptime_float, try using @as"),
                else => {},
            }
            fields[i] = .{ .name = capture.name, .type = capture.type, .default_value_ptr = null, .is_comptime = false, .alignment = capture.alignment };
        }

        var field_names: [fields.len][]const u8 = undefined;
        var field_types: [fields.len]type = undefined;
        var field_attrs: [fields.len]std.builtin.Type.StructField.Attributes = undefined;
        for (fields, 0..) |field, i| {
            field_names[i] = field.name;
            field_types[i] = field.type;
            field_attrs[i] = .{ .@"align" = field.alignment };
        }

        return @Struct(.@"extern", null, &field_names, &field_types, &field_attrs);
    }

    // Pointer to opaque instead of anyopaque: https://github.com/ziglang/zig/issues/18461
    const NSConcreteStackBlock = @extern(*opaque {}, .{ .name = "_NSConcreteStackBlock" });
    const NSConcreteMallocBlock = @extern(*opaque {}, .{ .name = "_NSConcreteMallocBlock" });

    // https://github.com/llvm/llvm-project/blob/734d31a464e204db699c1cf9433494926deb2aa2/compiler-rt/lib/BlocksRuntime/Block_private.h#L101-L108
    const BlockFieldFlags = enum(c_int) {
        object = 3, // BLOCK_FIELD_IS_OBJECT
        block = 7, // BLOCK_FIELD_IS_BLOCK
        byref = 8, // BLOCK_FIELD_IS_BYREF
        weak = 16, // BLOCK_FIELD_IS_WEAK
        byref_caller = 128, // BLOCK_BYREF_CALLER
    };

    extern "c" fn _Block_copy(src: *const anyopaque) callconv(.c) ?*anyopaque;
    extern "c" fn _Block_release(src: *const anyopaque) callconv(.c) void;
    extern "c" fn _Block_object_assign(dst: *anyopaque, src: *const anyopaque, flag: BlockFieldFlags) void;
    extern "c" fn _Block_object_dispose(src: *const anyopaque, flag: BlockFieldFlags) void;

    const Descriptor = extern struct {
        reserved: c_ulong = 0,
        size: c_ulong,
        copy_helper: *const fn (dst: *anyopaque, src: *anyopaque) callconv(.c) void,
        dispose_helper: *const fn (src: *anyopaque) callconv(.c) void,
        signature: ?[*:0]const u8,
    };

    const BlockFlags = packed struct(c_int) {
        _unused: u23 = 0,
        noescape: bool = false,
        _unused_2: u1 = 0,
        copy_dispose: bool = false,
        ctor: bool = false,
        _unused_3: u1 = 0,
        global: bool = false,
        stret: bool = false,
        signature: bool = false,
        _unused_4: u1 = 0,
    };
};

pub const AutoreleasePool = autorelease.AutoreleasePool;
pub const Block = block.Block;
pub const Class = class.Class;
pub const getClass = class.getClass;
pub const getMetaClass = class.getMetaClass;
pub const allocateClassPair = class.allocateClassPair;
pub const registerClassPair = class.registerClassPair;
pub const disposeClassPair = class.disposeClassPair;
pub const Encoding = encoding.Encoding;
pub const comptimeEncode = encoding.comptimeEncode;
pub const Iterator = iterator.Iterator;
pub const Object = object.Object;
pub const Property = property.Property;
pub const Protocol = protocol.Protocol;
pub const getProtocol = protocol.getProtocol;
pub const sel = selpkg.sel;
pub const Sel = selpkg.Sel;

/// This just calls the C allocator free. Some things need to be freed
/// and this is how they can be freed for objc.
pub inline fn free(ptr: anytype) void {
    std.heap.c_allocator.free(ptr);
}
