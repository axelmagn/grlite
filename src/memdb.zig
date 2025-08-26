//!  in-memory sketch of graph db semantics
const std = @import("std");
const array_list = std.array_list;
const mem = std.mem;

const Id = u32;

const Key = struct {
    space: KeySpace,
    buf: []const u8,

    pub fn deinit(self: Key, gpa: mem.Allocator) void {
        gpa.free(self.buf);
    }

    pub fn dupe(key: Key, gpa: mem.Allocator) !Key {
        return Key{
            .space = key.space,
            .buf = try gpa.dupe(u8, key.buf),
        };
    }

    pub fn eql(self: Key, other: Key) bool {
        return self.space == other.space and mem.eql(u8, self.buf, other.buf);
    }
};

const KeySpace = u16;

const Graph = struct {
    keys: Keys,

    pub const Keys = struct {
        gpa: mem.Allocator,
        data: KeyList,
        next_id: Id = 1, // 0 is nil

        pub const KeyEntry = struct {
            id: Id,
            key: Key,
        };
        pub const KeyList = std.ArrayList(KeyEntry);

        pub fn init(gpa: mem.Allocator) Keys {
            return Keys{
                .gpa = gpa,
                .data = KeyList.empty,
            };
        }

        pub fn deinit(self: *Keys) void {
            for (self.data.items) |entry| {
                entry.key.deinit(self.gpa);
            }
            self.data.deinit(self.gpa);
        }

        /// Add a key to the index, and assign it an ID.  If they key has already been added, dedupe it.
        pub fn intern(self: *Keys, key: Key) !Id {
            const inner_key = try key.dupe(self.gpa);
            // dedupe
            if (self.lookupByKey(key)) |id| return id;
            // add new key entry
            const entry = KeyEntry{
                .id = self.next_id,
                .key = inner_key,
            };
            try self.data.append(self.gpa, entry);
            defer self.next_id += 1;
            return self.next_id;
        }

        /// remove a key from the index.  Asserts that ID assigned to a key.
        pub fn remove(self: *Keys, id: Id) void {
            for (0.., self.data.items) |i, entry| {
                if (entry.id == id) {
                    _ = self.data.swapRemove(i);
                    entry.key.deinit(self.gpa);
                    return;
                }
            }
            unreachable;
        }

        /// look up the ID of a key in the graph.  Return null if not found.
        pub fn lookupByKey(self: *Keys, key: Key) ?Id {
            for (self.data.items) |entry| {
                if (key.eql(entry.key)) return entry.id;
            }
            return null;
        }

        /// look up the key of an ID in the graph.  Return null if not found.
        pub fn lookupById(self: *Keys, id: Id) ?Key {
            for (self.data.items) |entry| {
                if (id == entry.id) return entry.key;
            }
            return null;
        }
    };

    pub fn init(gpa: mem.Allocator) Graph {
        return Graph{
            .keys = Keys.init(gpa),
        };
    }

    pub fn deinit(self: *Graph) void {
        self.keys.deinit();
    }
};

test "key storage" {
    const t = std.testing;

    var k = Graph.Keys.init(t.allocator);
    defer k.deinit();

    const alice_key = Key{ .space = 0, .buf = "Alice" };
    const alice_id = try k.intern(alice_key);
    try t.expectEqual(1, alice_id);
    try t.expectEqual(1, k.lookupByKey(alice_key));
    try t.expect(alice_key.eql(k.lookupById(alice_id).?));
    k.remove(alice_id);
    try t.expectEqual(null, k.lookupByKey(alice_key));
    try t.expectEqual(null, k.lookupById(alice_id));
}
