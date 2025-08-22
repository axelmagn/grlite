//!  in-memory sketch of graph db semantics
const std = @import("std");
const array_list = std.array_list;
const mem = std.mem;
const Allocator = std.mem.Allocator;

const Id = u64;

const Key = struct {
    space: KeySpace,
    buf: []u8,

    pub fn deinit(self: *Key, gpa: mem.Allocator) void {
        gpa.free(self.buf);
    }

    pub fn dupe(gpa: mem.Allocator, key: Key) !Key {
        return Key{
            .space = key.space,
            .buf = try gpa.dupe(key.buf),
        };
    }
};

const KeySpace = u16;

const Graph = struct {
    gpa: mem.Allocator,
    next_id: Id = 1, // 0 is nil

    keys: KeyList,

    pub const KeyEntry = struct {
        id: Id,
        key: Key,
    };
    pub const KeyList = array_list.ArrayList(KeyEntry, null);

    pub fn init(gpa: mem.Allocator) Graph {
        return Graph{
            .gpa = gpa,
            .keys = KeyList.empty,
        };
    }

    pub fn deinit(self: *Graph) void {
        for (self.keys.items) |key| {
            key.deinit(self.gpa);
        }
        self.keys.deinit(self.gpa);
    }
};
