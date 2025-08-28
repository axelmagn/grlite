//!  in-memory sketch of graph db semantics
const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

pub const Graph = struct {
    gpa: Allocator,
    labels: Labels,

    pub const IdSpace = enum(u1) {
        label,
        edge,
    };

    pub const Id = packed struct(u32) {
        space: IdSpace,
        inner: u31,

        pub const nil = 0;
    };
};

pub const Label = []const u8;

pub const Labels = struct {
    next_id: Id = start_id,
    data: LabelMap = LabelMap.empty,

    pub const start_id: Id = 1;

    comptime {
        assert(Graph.Id.nil < start_id);
    }

    pub const Id = u32;
    pub const LabelMap = std.ArrayHashMapUnmanaged(
        Id,
        Label,
        struct {
            pub fn hash(_: @This(), k: Id) u32 {
                return k;
            }
            pub fn eql(_: @This(), k1: Id, k2: Id) bool {
                return k1 == k2;
            }
        },
        false,
    );

    pub fn deinit(self: *Labels, gpa: Allocator) void {
        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            gpa.free(entry.value_ptr.*);
        }
        self.data.deinit(gpa);
    }

    pub fn get(self: *Labels, id: *Id) ?Label {
        return self.data.get(id);
    }

    /// naively search labels for existing one
    pub fn search(self: *Labels, label: Label) ?Id {
        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            if (mem.eql(u8, label, entry.value_ptr.*)) return entry.key_ptr.*;
        }
        return null;
    }

    pub fn put(self: *Labels, label: Label, gpa: Allocator) mem.Error!Id {
        // dedupe
        if (self.search(label)) |id| return id;

        // store a locally managed copy of the data
        const inner_label = try gpa.dupe(u8, label);
        errdefer gpa.free(inner_label);

        // store the label under the next ID
        try self.data.put(gpa, self.next_id, inner_label);
        defer self.next_id += 1;
        return self.next_id;
    }

    pub fn remove(self: *Labels, id: Id, gpa: Allocator) bool {
        const label = self.get(id);
        if (label == null) return false;
        gpa.free(label.?);
        assert(self.data.swapRemove(id) == true);
        return true;
    }
};

// pub const Id = u32;
//
// pub const Key = struct {
//     space: KeySpace,
//     buf: []const u8,
//
//     pub fn deinit(self: Key, gpa: mem.Allocator) void {
//         gpa.free(self.buf);
//     }
//
//     pub fn dupe(key: Key, gpa: mem.Allocator) !Key {
//         return Key{
//             .space = key.space,
//             .buf = try gpa.dupe(u8, key.buf),
//         };
//     }
//
//     pub fn eql(self: Key, other: Key) bool {
//         return self.space == other.space and mem.eql(u8, self.buf, other.buf);
//     }
// };
//
// pub const KeySpace = u16;
//
// pub const Keys = struct {
//     gpa: mem.Allocator,
//     data: KeyList,
//
//     pub const Entry = struct {
//         id: Id,
//         key: Key,
//     };
//     pub const KeyList = std.ArrayList(Entry);
//
//     pub fn init(gpa: mem.Allocator) Keys {
//         return Keys{
//             .gpa = gpa,
//             .data = KeyList.empty,
//         };
//     }
//
//     pub fn deinit(self: *Keys) void {
//         for (self.data.items) |entry| {
//             entry.key.deinit(self.gpa);
//         }
//         self.data.deinit(self.gpa);
//     }
//
//     /// Add a key to the index, and assign it an ID.  If they key has already been added, dedupe it.
//     pub fn intern(self: *Keys, key: Key) !Id {
//         const inner_key = try key.dupe(self.gpa);
//         // dedupe
//         if (self.lookupByKey(key)) |id| return id;
//         // add new key entry
//         const entry = Entry{
//             .id = self.next_id,
//             .key = inner_key,
//         };
//         try self.data.append(self.gpa, entry);
//         defer self.next_id += 1;
//         return self.next_id;
//     }
//
//     /// remove a key from the index.  Asserts that ID assigned to a key.
//     pub fn remove(self: *Keys, id: Id) void {
//         for (0.., self.data.items) |i, entry| {
//             if (entry.id == id) {
//                 _ = self.data.swapRemove(i);
//                 entry.key.deinit(self.gpa);
//                 return;
//             }
//         }
//         unreachable;
//     }
//
//     /// look up the ID of a key in the graph.  Return null if not found.
//     pub fn lookupByKey(self: *Keys, key: Key) ?Id {
//         for (self.data.items) |entry| {
//             if (key.eql(entry.key)) return entry.id;
//         }
//         return null;
//     }
//
//     /// look up the key of an ID in the graph.  Return null if not found.
//     pub fn lookupById(self: *Keys, id: Id) ?Key {
//         for (self.data.items) |entry| {
//             if (id == entry.id) return entry.key;
//         }
//         return null;
//     }
// };
//
// pub const Edge = struct {
//     subject: Id,
//     predicate: Id,
//     object: Id,
// };
//
// pub const Edges = struct {
//     gpa: mem.Allocator,
//     // data: EdgeList,
//
//     pub const Entry = struct {
//         id: Id,
//         edge: Edge,
//     };
//
//     pub const EdgeList = std.ArrayList(Entry);
// };
//
// const Graph = struct {
//     keys: Keys,
//     edges: Edges,
//     next_id: Id = 1, // 0 is nil
//
//     pub fn init(gpa: mem.Allocator) Graph {
//         return Graph{
//             .keys = Keys.init(gpa),
//         };
//     }
//
//     pub fn deinit(self: *Graph) void {
//         self.keys.deinit();
//     }
// };
//
// test "key storage" {
//     const t = std.testing;
//
//     var k = Graph.Keys.init(t.allocator);
//     defer k.deinit();
//
//     const alice_key = Key{ .space = 0, .buf = "Alice" };
//     const alice_id = try k.intern(alice_key);
//     try t.expectEqual(1, alice_id);
//     try t.expectEqual(1, k.lookupByKey(alice_key));
//     try t.expect(alice_key.eql(k.lookupById(alice_id).?));
//     k.remove(alice_id);
//     try t.expectEqual(null, k.lookupByKey(alice_key));
//     try t.expectEqual(null, k.lookupById(alice_id));
// }
