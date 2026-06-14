//! Linux system tray implementation using DBus (StatusNotifierItem protocol).
//!
//! Implements the `org.kde.StatusNotifierItem` and `com.canonical.dbusmenu`
//! DBus interfaces directly — no GTK dependency.
//!
//! Dependencies: `libdbus-1-dev`
//!
//! ```bash
//! sudo apt install libdbus-1-dev
//! ```

const std = @import("std");
const MenuItem = @import("../systray.zig").MenuItem;
const builtin = @import("builtin");

// ── libdbus-1 constants ────────────────────────────────────────────────

const DBUS_TYPE_INVALID = @as(c_int, 0);
const DBUS_TYPE_BOOLEAN = @as(c_int, 'b');
const DBUS_TYPE_BYTE = @as(c_int, 'y');
const DBUS_TYPE_INT32 = @as(c_int, 'i');
const DBUS_TYPE_UINT32 = @as(c_int, 'u');
const DBUS_TYPE_STRING = @as(c_int, 's');
const DBUS_TYPE_OBJECT_PATH = @as(c_int, 'o');
const DBUS_TYPE_SIGNATURE = @as(c_int, 'g');
const DBUS_TYPE_ARRAY = @as(c_int, 'a');
const DBUS_TYPE_VARIANT = @as(c_int, 'v');
const DBUS_TYPE_STRUCT = @as(c_int, '(');
const DBUS_TYPE_DICT_ENTRY = @as(c_int, '{');

const DBUS_HANDLER_RESULT_HANDLED: c_int = 0;
const DBUS_HANDLER_RESULT_NOT_YET_HANDLED: c_int = 1;
const DBUS_HANDLER_RESULT_NEED_MEMORY: c_int = 2;

const DBUS_DISPATCH_DATA_REMAINS: c_int = 0;
const DBUS_DISPATCH_COMPLETE: c_int = 1;
const DBUS_DISPATCH_NEED_MEMORY: c_int = 2;

const DBUS_NAME_FLAG_DO_NOT_QUEUE: u32 = 4;

const DBUS_BUS_SESSION: c_int = 0;

// ── libdbus-1 type declarations ────────────────────────────────────────

const DBusConnection = opaque {};
const DBusMessage = opaque {};

const DBusHandlerResult = c_int;
const DBusDispatchStatus = c_int;
const dbus_bool_t = c_int;

const DBusError = extern struct {
    name: ?[*:0]const u8,
    message: ?[*:0]const u8,
    dummy: u8,
    padding1: [24]u8 = undefined,
};

const DBusMessageIter = extern struct {
    dummy1: ?*anyopaque = null,
    dummy2: ?*anyopaque = null,
    dummy3: u32 = 0,
    dummy4: c_int = 0,
    dummy5: c_int = 0,
    dummy6: c_int = 0,
    dummy7: c_int = 0,
    dummy8: c_int = 0,
    dummy9: c_int = 0,
    dummy10: c_int = 0,
    dummy11: c_int = 0,
    padding1: c_int = 0,
    padding2: ?*anyopaque = null,
    padding3: ?*anyopaque = null,
};

const DBusObjectPathVTable = extern struct {
    unregister_function: ?*const fn (*DBusConnection, ?*anyopaque) callconv(.C) void,
    message_function: ?*const fn (*DBusConnection, ?*DBusMessage, ?*anyopaque) callconv(.C) DBusHandlerResult,
    dbus_internal_padding1: ?*anyopaque = null,
    dbus_internal_padding2: ?*anyopaque = null,
    dbus_internal_padding3: ?*anyopaque = null,
    dbus_internal_padding4: ?*anyopaque = null,
};

// ── libdbus-1 extern declarations ─────────────────────────────────────

extern "dbus-1" fn dbus_bus_get(bus: c_int, err: ?*DBusError) ?*DBusConnection;
extern "dbus-1" fn dbus_connection_unref(conn: *DBusConnection) void;
extern "dbus-1" fn dbus_connection_ref(conn: *DBusConnection) void;
extern "dbus-1" fn dbus_connection_read_write(conn: *DBusConnection, timeout_ms: c_int) dbus_bool_t;
extern "dbus-1" fn dbus_connection_dispatch(conn: *DBusConnection) DBusDispatchStatus;
extern "dbus-1" fn dbus_connection_flush(conn: *DBusConnection) dbus_bool_t;
extern "dbus-1" fn dbus_connection_send(conn: *DBusConnection, msg: *DBusMessage, serial: ?*u32) dbus_bool_t;
extern "dbus-1" fn dbus_connection_add_filter(conn: *DBusConnection, filter: ?*const fn (*DBusConnection, *DBusMessage, ?*anyopaque) callconv(.C) DBusHandlerResult, data: ?*anyopaque, free_data: ?*const fn (?*anyopaque) callconv(.C) void) void;
extern "dbus-1" fn dbus_connection_register_object_path(conn: *DBusConnection, path: [*:0]const u8, vtable: *const DBusObjectPathVTable, data: ?*anyopaque) dbus_bool_t;
extern "dbus-1" fn dbus_bus_request_name(conn: *DBusConnection, name: [*:0]const u8, flags: u32, err: ?*DBusError) c_int;
extern "dbus-1" fn dbus_bus_add_match(conn: *DBusConnection, rule: [*:0]const u8, err: ?*DBusError) void;
extern "dbus-1" fn dbus_message_new_method_return(msg: *DBusMessage) ?*DBusMessage;
extern "dbus-1" fn dbus_message_new_signal(path: [*:0]const u8, iface: [*:0]const u8, name: [*:0]const u8) ?*DBusMessage;
extern "dbus-1" fn dbus_message_new_error(msg: *DBusMessage, name: [*:0]const u8, fmt: [*:0]const u8) ?*DBusMessage;
extern "dbus-1" fn dbus_message_unref(msg: *DBusMessage) void;
extern "dbus-1" fn dbus_message_is_method_call(msg: *DBusMessage, iface: ?[*:0]const u8, method: ?[*:0]const u8) dbus_bool_t;
extern "dbus-1" fn dbus_message_is_signal(msg: *DBusMessage, iface: ?[*:0]const u8, signal: ?[*:0]const u8) dbus_bool_t;
extern "dbus-1" fn dbus_message_get_path(msg: *DBusMessage) ?[*:0]const u8;
extern "dbus-1" fn dbus_message_get_interface(msg: *DBusMessage) ?[*:0]const u8;
extern "dbus-1" fn dbus_message_get_member(msg: *DBusMessage) ?[*:0]const u8;
extern "dbus-1" fn dbus_message_iter_init_append(msg: *DBusMessage, iter: *DBusMessageIter) void;
extern "dbus-1" fn dbus_message_iter_append_basic(iter: *DBusMessageIter, type_: c_int, val: *const anyopaque) dbus_bool_t;
extern "dbus-1" fn dbus_message_iter_open_container(iter: *DBusMessageIter, type_: c_int, contained: ?[*:0]const u8, sub: *DBusMessageIter) dbus_bool_t;
extern "dbus-1" fn dbus_message_iter_close_container(iter: *DBusMessageIter, sub: *DBusMessageIter) dbus_bool_t;
extern "dbus-1" fn dbus_message_iter_init(msg: *DBusMessage, iter: *DBusMessageIter) dbus_bool_t;
extern "dbus-1" fn dbus_message_iter_get_arg_type(iter: *DBusMessageIter) c_int;
extern "dbus-1" fn dbus_message_iter_get_basic(iter: *DBusMessageIter, val: *anyopaque) void;
extern "dbus-1" fn dbus_message_iter_recurse(iter: *DBusMessageIter, sub: *DBusMessageIter) void;
extern "dbus-1" fn dbus_message_iter_next(iter: *DBusMessageIter) dbus_bool_t;
extern "dbus-1" fn dbus_error_init(err: *DBusError) void;
extern "dbus-1" fn dbus_error_is_set(err: *DBusError) dbus_bool_t;
extern "dbus-1" fn dbus_error_free(err: *DBusError) void;
extern "dbus-1" fn dbus_free(ptr: *anyopaque) void;
extern "dbus-1" fn dbus_message_new_method_call(destination: [*:0]const u8, path: [*:0]const u8, iface: [*:0]const u8, method: [*:0]const u8) ?*DBusMessage;

// ── Constants ─────────────────────────────────────────────────────────

const NOTIFIER_IFACE = "org.kde.StatusNotifierItem";
const NOTIFIER_PATH = "/StatusNotifierItem";
const MENU_IFACE = "com.canonical.dbusmenu";
const MENU_PATH = "/StatusNotifierItem/menu";
const PROPERTIES_IFACE = "org.freedesktop.DBus.Properties";
const INTROSPECTABLE_IFACE = "org.freedesktop.DBus.Introspectable";
const WATCHER_SERVICE = "org.kde.StatusNotifierWatcher";
const WATCHER_PATH = "/StatusNotifierWatcher";
const WATCHER_IFACE = "org.kde.StatusNotifierWatcher";

// ── Menu node tree ────────────────────────────────────────────────────

const MenuNode = struct {
    id: i32,
    is_separator: bool = false,
    label: ?[]const u8 = null,
    enabled: bool = true,
    visible: bool = true,
    toggle_type: ?[]const u8 = null,
    toggle_state: i32 = 0,
    icon_data: ?std.ArrayList(u8) = null,
    children_display: ?[]const u8 = null,
    children: std.ArrayList(*MenuNode),
};

// ── Global state ──────────────────────────────────────────────────────

var global_conn: ?*DBusConnection = null;
var global_menu_root: ?*MenuNode = null;
var global_menu_items: std.ArrayListUnmanaged(*MenuItem) = .{ .items = &.{}, .capacity = 0 };
var global_menu_nodes: std.ArrayListUnmanaged(*MenuNode) = .{ .items = &.{}, .capacity = 0 };
var global_next_id: u32 = 1;
var global_menu_version: u32 = 0;
var global_quit_flag: bool = false;
var global_allocator: std.mem.Allocator = undefined;
var global_current_tray: ?*anyopaque = null;
var global_icon_bytes: ?std.ArrayList(u8) = null;
var global_tooltip: ?[]const u8 = null;

// ── Menu node helpers ─────────────────────────────────────────────────

fn nextId() u32 {
    const id = global_next_id;
    global_next_id += 1;
    return id;
}

fn createMenuNode(id: i32) !*MenuNode {
    const node = try global_allocator.create(MenuNode);
    node.* = .{
        .id = id,
        .children = std.ArrayList(*MenuNode).init(global_allocator),
    };
    try global_menu_nodes.append(global_allocator, node);
    return node;
}

fn findMenuNode(id: i32, parent: *MenuNode) ?*MenuNode {
    if (parent.id == id) return parent;
    for (parent.children.items) |child| {
        if (child.id == id) return child;
        const found = findMenuNode(id, child);
        if (found) |f| return f;
    }
    return null;
}

fn removeMenuNode(id: i32, parent: *MenuNode) bool {
    for (parent.children.items, 0..) |child, i| {
        if (child.id == id) {
            _ = parent.children.orderedRemove(i);
            return true;
        }
        if (removeMenuNode(id, child)) return true;
    }
    return false;
}

fn bumpMenuVersion() void {
    global_menu_version += 1;
}

fn sendLayoutUpdated() void {
    bumpMenuVersion();
    const conn = global_conn orelse return;
    const sig = dbus_message_new_signal(MENU_PATH, MENU_IFACE, "LayoutUpdated") orelse return;
    defer dbus_message_unref(sig);

    var iter: DBusMessageIter = undefined;
    dbus_message_iter_init_append(sig, &iter);

    const rev = global_menu_version;
    _ = dbus_message_iter_append_basic(&iter, DBUS_TYPE_UINT32, @as(*const anyopaque, @ptrCast(&rev)));
    const zero: i32 = 0;
    _ = dbus_message_iter_append_basic(&iter, DBUS_TYPE_INT32, @as(*const anyopaque, @ptrCast(&zero)));

    _ = dbus_connection_send(conn, sig, null);
    _ = dbus_connection_flush(conn);
}

fn sendItemsPropertiesUpdated(id: i32, node: *MenuNode) void {
    const conn = global_conn orelse return;
    const sig = dbus_message_new_signal(MENU_PATH, MENU_IFACE, "ItemsPropertiesUpdated") orelse return;
    defer dbus_message_unref(sig);

    var root_iter: DBusMessageIter = undefined;
    dbus_message_iter_init_append(sig, &root_iter);

    // updatedProps: a(ia{sv}) — array of struct {int32, dict{string->variant}}
    {
        var arr_iter: DBusMessageIter = undefined;
        _ = dbus_message_iter_open_container(&root_iter, DBUS_TYPE_ARRAY, "(ia{sv})", &arr_iter);
        {
            var struct_iter: DBusMessageIter = undefined;
            _ = dbus_message_iter_open_container(&arr_iter, DBUS_TYPE_STRUCT, null, &struct_iter);
            _ = dbus_message_iter_append_basic(&struct_iter, DBUS_TYPE_INT32, @as(*const anyopaque, @ptrCast(&id)));

            // properties dict
            var dict_iter: DBusMessageIter = undefined;
            _ = dbus_message_iter_open_container(&struct_iter, DBUS_TYPE_ARRAY, "{sv}", &dict_iter);
            appendNodeProperties(&dict_iter, node) catch {};
            _ = dbus_message_iter_close_container(&struct_iter, &dict_iter);

            _ = dbus_message_iter_close_container(&arr_iter, &struct_iter);
        }
        _ = dbus_message_iter_close_container(&root_iter, &arr_iter);
    }

    // removedProps: a(ias) — empty
    {
        var arr_iter: DBusMessageIter = undefined;
        _ = dbus_message_iter_open_container(&root_iter, DBUS_TYPE_ARRAY, "(ias)", &arr_iter);
        _ = dbus_message_iter_close_container(&root_iter, &arr_iter);
    }

    _ = dbus_connection_send(conn, sig, null);
    _ = dbus_connection_flush(conn);
}

fn appendNodeProperties(dict_iter: *DBusMessageIter, node: *MenuNode) !void {
    // label
    if (node.label) |label| {
        try appendDictVariantString(dict_iter, "label", label);
    }
    // enabled
    try appendDictVariantBool(dict_iter, "enabled", node.enabled);
    // visible
    try appendDictVariantBool(dict_iter, "visible", node.visible);

    if (node.is_separator) {
        try appendDictVariantString(dict_iter, "type", "separator");
    } else {
        try appendDictVariantString(dict_iter, "type", "");
        if (node.toggle_type) |tt| {
            if (tt.len > 0) {
                try appendDictVariantString(dict_iter, "toggle-type", tt);
                try appendDictVariantInt32(dict_iter, "toggle-state", node.toggle_state);
            }
        }
    }

    if (node.icon_data) |*icon| {
        if (icon.items.len > 0) {
            var entry_iter: DBusMessageIter = undefined;
            _ = dbus_message_iter_open_container(dict_iter, DBUS_TYPE_DICT_ENTRY, null, &entry_iter);
            const key = "icon-data";
            _ = dbus_message_iter_append_basic(&entry_iter, DBUS_TYPE_STRING, @as(*const anyopaque, @ptrCast(&key)));
            var var_iter: DBusMessageIter = undefined;
            _ = dbus_message_iter_open_container(&entry_iter, DBUS_TYPE_VARIANT, "ay", &var_iter);
            var arr_iter: DBusMessageIter = undefined;
            _ = dbus_message_iter_open_container(&var_iter, DBUS_TYPE_ARRAY, "y", &arr_iter);
            for (icon.items) |byte| {
                _ = dbus_message_iter_append_basic(&arr_iter, DBUS_TYPE_BYTE, @as(*const anyopaque, @ptrCast(&byte)));
            }
            _ = dbus_message_iter_close_container(&var_iter, &arr_iter);
            _ = dbus_message_iter_close_container(&entry_iter, &var_iter);
            _ = dbus_message_iter_close_container(dict_iter, &entry_iter);
        }
    }

    if (node.children_display) |cd| {
        try appendDictVariantString(dict_iter, "children-display", cd);
    }
}

fn appendDictVariantString(iter: *DBusMessageIter, key: []const u8, val: []const u8) !void {
    var entry_iter: DBusMessageIter = undefined;
    _ = dbus_message_iter_open_container(iter, DBUS_TYPE_DICT_ENTRY, null, &entry_iter);
    const key_z = try std.heap.c_allocator.dupeZ(u8, key);
    defer std.heap.c_allocator.free(key_z);
    _ = dbus_message_iter_append_basic(&entry_iter, DBUS_TYPE_STRING, @as(*const anyopaque, @ptrCast(&key_z)));
    var var_iter: DBusMessageIter = undefined;
    _ = dbus_message_iter_open_container(&entry_iter, DBUS_TYPE_VARIANT, "s", &var_iter);
    const val_z = try std.heap.c_allocator.dupeZ(u8, val);
    defer std.heap.c_allocator.free(val_z);
    _ = dbus_message_iter_append_basic(&var_iter, DBUS_TYPE_STRING, @as(*const anyopaque, @ptrCast(&val_z)));
    _ = dbus_message_iter_close_container(&entry_iter, &var_iter);
    _ = dbus_message_iter_close_container(iter, &entry_iter);
}

fn appendDictVariantBool(iter: *DBusMessageIter, key: []const u8, val: bool) !void {
    var entry_iter: DBusMessageIter = undefined;
    _ = dbus_message_iter_open_container(iter, DBUS_TYPE_DICT_ENTRY, null, &entry_iter);
    const key_z = try std.heap.c_allocator.dupeZ(u8, key);
    defer std.heap.c_allocator.free(key_z);
    _ = dbus_message_iter_append_basic(&entry_iter, DBUS_TYPE_STRING, @as(*const anyopaque, @ptrCast(&key_z)));
    var var_iter: DBusMessageIter = undefined;
    _ = dbus_message_iter_open_container(&entry_iter, DBUS_TYPE_VARIANT, "b", &var_iter);
    const b: u32 = if (val) 1 else 0;
    _ = dbus_message_iter_append_basic(&var_iter, DBUS_TYPE_BOOLEAN, @as(*const anyopaque, @ptrCast(&b)));
    _ = dbus_message_iter_close_container(&entry_iter, &var_iter);
    _ = dbus_message_iter_close_container(iter, &entry_iter);
}

fn appendDictVariantInt32(iter: *DBusMessageIter, key: []const u8, val: i32) !void {
    var entry_iter: DBusMessageIter = undefined;
    _ = dbus_message_iter_open_container(iter, DBUS_TYPE_DICT_ENTRY, null, &entry_iter);
    const key_z = try std.heap.c_allocator.dupeZ(u8, key);
    defer std.heap.c_allocator.free(key_z);
    _ = dbus_message_iter_append_basic(&entry_iter, DBUS_TYPE_STRING, @as(*const anyopaque, @ptrCast(&key_z)));
    var var_iter: DBusMessageIter = undefined;
    _ = dbus_message_iter_open_container(&entry_iter, DBUS_TYPE_VARIANT, "i", &var_iter);
    _ = dbus_message_iter_append_basic(&var_iter, DBUS_TYPE_INT32, @as(*const anyopaque, @ptrCast(&val)));
    _ = dbus_message_iter_close_container(&entry_iter, &var_iter);
    _ = dbus_message_iter_close_container(iter, &entry_iter);
}

// ── DBus message builders ─────────────────────────────────────────────

fn buildErrorResponse(msg: *DBusMessage, name: [*:0]const u8, text: [*:0]const u8) ?*DBusMessage {
    return dbus_message_new_error(msg, name, text);
}

fn sendReply(_: *DBusMessage, reply: *DBusMessage) void {
    _ = dbus_connection_send(global_conn.?, reply, null);
    _ = dbus_connection_flush(global_conn.?);
    dbus_message_unref(reply);
}

fn buildStringReply(msg: *DBusMessage, val: [*:0]const u8) ?*DBusMessage {
    const reply = dbus_message_new_method_return(msg) orelse return null;
    var iter: DBusMessageIter = undefined;
    dbus_message_iter_init_append(reply, &iter);
    _ = dbus_message_iter_append_basic(&iter, DBUS_TYPE_STRING, @as(*const anyopaque, @ptrCast(&val)));
    return reply;
}

fn buildBoolReply(msg: *DBusMessage, val: bool) ?*DBusMessage {
    const reply = dbus_message_new_method_return(msg) orelse return null;
    var iter: DBusMessageIter = undefined;
    dbus_message_iter_init_append(reply, &iter);
    const b: u32 = if (val) 1 else 0;
    _ = dbus_message_iter_append_basic(&iter, DBUS_TYPE_BOOLEAN, @as(*const anyopaque, @ptrCast(&b)));
    return reply;
}

fn buildVariantReply(msg: *DBusMessage, type_sig: [*:0]const u8, val_ptr: *const anyopaque) ?*DBusMessage {
    const reply = dbus_message_new_method_return(msg) orelse return null;
    var iter: DBusMessageIter = undefined;
    dbus_message_iter_init_append(reply, &iter);
    var var_iter: DBusMessageIter = undefined;
    _ = dbus_message_iter_open_container(&iter, DBUS_TYPE_VARIANT, type_sig, &var_iter);
    _ = dbus_message_iter_append_basic(&var_iter, @as(c_int, type_sig[0]), val_ptr);
    _ = dbus_message_iter_close_container(&iter, &var_iter);
    return reply;
}

// ── Introspection XML ─────────────────────────────────────────────────

const INTROSPECT_XML =
    \\<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
    \\ "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
    \\<node name="/StatusNotifierItem">
    \\  <interface name="org.freedesktop.DBus.Introspectable">
    \\    <method name="Introspect">
    \\      <arg name="data" direction="out" type="s"/>
    \\    </method>
    \\  </interface>
    \\  <interface name="org.freedesktop.DBus.Properties">
    \\    <method name="Get">
    \\      <arg name="interface" direction="in" type="s"/>
    \\      <arg name="property" direction="in" type="s"/>
    \\      <arg name="value" direction="out" type="v"/>
    \\    </method>
    \\    <method name="GetAll">
    \\      <arg name="interface" direction="in" type="s"/>
    \\      <arg name="properties" direction="out" type="a{sv}"/>
    \\    </method>
    \\    <method name="Set">
    \\      <arg name="interface" direction="in" type="s"/>
    \\      <arg name="property" direction="in" type="s"/>
    \\      <arg name="value" direction="in" type="v"/>
    \\    </method>
    \\  </interface>
    \\  <interface name="org.kde.StatusNotifierItem">
    \\    <property name="Category" type="s" access="read"/>
    \\    <property name="Id" type="s" access="read"/>
    \\    <property name="Title" type="s" access="read"/>
    \\    <property name="Status" type="s" access="read"/>
    \\    <property name="WindowId" type="i" access="read"/>
    \\    <property name="IconThemePath" type="s" access="read"/>
    \\    <property name="Menu" type="o" access="read"/>
    \\    <property name="ItemIsMenu" type="b" access="read"/>
    \\    <property name="IconName" type="s" access="read"/>
    \\    <property name="IconPixmap" type="a(iiay)" access="read"/>
    \\    <property name="ToolTip" type="(sa(iiay)ss)" access="read"/>
    \\    <method name="ContextMenu">
    \\      <arg name="x" type="i" direction="in"/>
    \\      <arg name="y" type="i" direction="in"/>
    \\    </method>
    \\    <method name="Activate">
    \\      <arg name="x" type="i" direction="in"/>
    \\      <arg name="y" type="i" direction="in"/>
    \\    </method>
    \\    <method name="SecondaryActivate">
    \\      <arg name="x" type="i" direction="in"/>
    \\      <arg name="y" type="i" direction="in"/>
    \\    </method>
    \\    <method name="Scroll">
    \\      <arg name="delta" type="i" direction="in"/>
    \\      <arg name="orientation" type="s" direction="in"/>
    \\    </method>
    \\    <signal name="NewTitle"/>
    \\    <signal name="NewIcon"/>
    \\    <signal name="NewAttentionIcon"/>
    \\    <signal name="NewOverlayIcon"/>
    \\    <signal name="NewToolTip"/>
    \\    <signal name="NewStatus">
    \\      <arg name="status" type="s"/>
    \\    </signal>
    \\    <signal name="NewMenu"/>
    \\  </interface>
    \\  <node name="menu"/>
    \\</node>
;

const MENU_INTROSPECT_XML =
    \\<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
    \\ "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
    \\<node name="/StatusNotifierItem/menu">
    \\  <interface name="org.freedesktop.DBus.Introspectable">
    \\    <method name="Introspect">
    \\      <arg name="data" direction="out" type="s"/>
    \\    </method>
    \\  </interface>
    \\  <interface name="org.freedesktop.DBus.Properties">
    \\    <method name="Get">
    \\      <arg name="interface" direction="in" type="s"/>
    \\      <arg name="property" direction="in" type="s"/>
    \\      <arg name="value" direction="out" type="v"/>
    \\    </method>
    \\    <method name="GetAll">
    \\      <arg name="interface" direction="in" type="s"/>
    \\      <arg name="properties" direction="out" type="a{sv}"/>
    \\    </method>
    \\    <method name="Set">
    \\      <arg name="interface" direction="in" type="s"/>
    \\      <arg name="property" direction="in" type="s"/>
    \\      <arg name="value" direction="in" type="v"/>
    \\    </method>
    \\  </interface>
    \\  <interface name="com.canonical.dbusmenu">
    \\    <property name="Version" type="u" access="read"/>
    \\    <property name="TextDirection" type="s" access="read"/>
    \\    <property name="Status" type="s" access="read"/>
    \\    <property name="IconThemePath" type="as" access="read"/>
    \\    <method name="GetLayout">
    \\      <arg name="parentId" type="i" direction="in"/>
    \\      <arg name="recursionDepth" type="i" direction="in"/>
    \\      <arg name="propertyNames" type="as" direction="in"/>
    \\      <arg name="revision" type="u" direction="out"/>
    \\      <arg name="layout" type="(ia{sv}av)" direction="out"/>
    \\    </method>
    \\    <method name="GetGroupProperties">
    \\      <arg name="ids" type="ai" direction="in"/>
    \\      <arg name="propertyNames" type="as" direction="in"/>
    \\      <arg name="properties" type="a(ia{sv})" direction="out"/>
    \\    </method>
    \\    <method name="GetProperty">
    \\      <arg name="id" type="i" direction="in"/>
    \\      <arg name="name" type="s" direction="in"/>
    \\      <arg name="value" type="v" direction="out"/>
    \\    </method>
    \\    <method name="Event">
    \\      <arg name="id" type="i" direction="in"/>
    \\      <arg name="eventId" type="s" direction="in"/>
    \\      <arg name="data" type="v" direction="in"/>
    \\      <arg name="timestamp" type="u" direction="in"/>
    \\    </method>
    \\    <method name="EventGroup">
    \\      <arg name="events" type="a(isvu)" direction="in"/>
    \\      <arg name="idErrors" type="ai" direction="out"/>
    \\    </method>
    \\    <method name="AboutToShow">
    \\      <arg name="id" type="i" direction="in"/>
    \\      <arg name="needUpdate" type="b" direction="out"/>
    \\    </method>
    \\    <method name="AboutToShowGroup">
    \\      <arg name="ids" type="ai" direction="in"/>
    \\      <arg name="updatesNeeded" type="ai" direction="out"/>
    \\      <arg name="idErrors" type="ai" direction="out"/>
    \\    </method>
    \\    <signal name="LayoutUpdated">
    \\      <arg name="revision" type="u"/>
    \\      <arg name="parent" type="i"/>
    \\    </signal>
    \\    <signal name="ItemsPropertiesUpdated">
    \\      <arg name="updatedProps" type="a(ia{sv})"/>
    \\      <arg name="removedProps" type="a(ias)"/>
    \\    </signal>
    \\  </interface>
    \\</node>
;

// ── Method handlers ───────────────────────────────────────────────────

fn handleIntrospect(msg: *DBusMessage) void {
    const path = dbus_message_get_path(msg) orelse return;
    const xml = if (std.mem.eql(u8, std.mem.span(path), MENU_PATH))
        MENU_INTROSPECT_XML
    else
        INTROSPECT_XML;
    const reply = buildStringReply(msg, xml) orelse return;
    sendReply(msg, reply);
}

fn handlePropertiesGet(msg: *DBusMessage) void {
    var iter: DBusMessageIter = undefined;
    if (dbus_message_iter_init(msg, &iter) == 0) return;

    if (dbus_message_iter_get_arg_type(&iter) != DBUS_TYPE_STRING) return;
    var iface_ptr: [*:0]const u8 = undefined;
    dbus_message_iter_get_basic(&iter, @as(*anyopaque, @ptrCast(&iface_ptr)));
    dbus_message_iter_next(&iter);

    if (dbus_message_iter_get_arg_type(&iter) != DBUS_TYPE_STRING) return;
    var prop_ptr: [*:0]const u8 = undefined;
    dbus_message_iter_get_basic(&iter, @as(*anyopaque, @ptrCast(&prop_ptr)));

    const prop = std.mem.span(prop_ptr);
    const iface = std.mem.span(iface_ptr);

    const reply = getPropertyValue(msg, iface, prop) orelse
        buildErrorResponse(msg, "org.freedesktop.DBus.Error.InvalidArgs", "Unknown property") orelse return;
    sendReply(msg, reply);
}

fn getPropertyValue(msg: *DBusMessage, iface: []const u8, prop: []const u8) ?*DBusMessage {
    if (std.mem.eql(u8, iface, NOTIFIER_IFACE)) {
        if (std.mem.eql(u8, prop, "Category")) {
            return buildVariantReply(msg, "s", @as(*const anyopaque, @ptrCast(&@as([*:0]const u8, "ApplicationStatus"))));
        }
        if (std.mem.eql(u8, prop, "Id")) {
            return buildVariantReply(msg, "s", @as(*const anyopaque, @ptrCast(&@as([*:0]const u8, "zigtray"))));
        }
        if (std.mem.eql(u8, prop, "Title")) {
            const title = if (global_tooltip) |t| t else "";
            const z = std.heap.c_allocator.dupeZ(u8, title) catch return null;
            defer std.heap.c_allocator.free(z);
            return buildVariantReply(msg, "s", @as(*const anyopaque, @ptrCast(&z)));
        }
        if (std.mem.eql(u8, prop, "Status")) {
            return buildVariantReply(msg, "s", @as(*const anyopaque, @ptrCast(&@as([*:0]const u8, "Active"))));
        }
        if (std.mem.eql(u8, prop, "WindowId")) {
            const zero: i32 = 0;
            return buildVariantReply(msg, "i", @as(*const anyopaque, @ptrCast(&zero)));
        }
        if (std.mem.eql(u8, prop, "IconThemePath")) {
            return buildVariantReply(msg, "s", @as(*const anyopaque, @ptrCast(&@as([*:0]const u8, ""))));
        }
        if (std.mem.eql(u8, prop, "Menu")) {
            return buildVariantReply(msg, "o", @as(*const anyopaque, @ptrCast(&@as([*:0]const u8, MENU_PATH))));
        }
        if (std.mem.eql(u8, prop, "ItemIsMenu")) {
            const b: u32 = 0;
            return buildVariantReply(msg, "b", @as(*const anyopaque, @ptrCast(&b)));
        }
        if (std.mem.eql(u8, prop, "IconName")) {
            return buildVariantReply(msg, "s", @as(*const anyopaque, @ptrCast(&@as([*:0]const u8, ""))));
        }
        if (std.mem.eql(u8, prop, "IconPixmap")) {
            return buildIconPixmapReply(msg);
        }
        if (std.mem.eql(u8, prop, "ToolTip")) {
            return buildToolTipReply(msg);
        }
    }

    if (std.mem.eql(u8, iface, MENU_IFACE)) {
        if (std.mem.eql(u8, prop, "Version")) {
            const v: u32 = 0;
            return buildVariantReply(msg, "u", @as(*const anyopaque, @ptrCast(&v)));
        }
        if (std.mem.eql(u8, prop, "TextDirection")) {
            return buildVariantReply(msg, "s", @as(*const anyopaque, @ptrCast(&@as([*:0]const u8, "ltr"))));
        }
        if (std.mem.eql(u8, prop, "Status")) {
            return buildVariantReply(msg, "s", @as(*const anyopaque, @ptrCast(&@as([*:0]const u8, "normal"))));
        }
        if (std.mem.eql(u8, prop, "IconThemePath")) {
            const reply = dbus_message_new_method_return(msg) orelse return null;
            var iter: DBusMessageIter = undefined;
            dbus_message_iter_init_append(reply, &iter);
            var var_iter: DBusMessageIter = undefined;
            _ = dbus_message_iter_open_container(&iter, DBUS_TYPE_VARIANT, "as", &var_iter);
            var arr_iter: DBusMessageIter = undefined;
            _ = dbus_message_iter_open_container(&var_iter, DBUS_TYPE_ARRAY, "s", &arr_iter);
            _ = dbus_message_iter_close_container(&var_iter, &arr_iter);
            _ = dbus_message_iter_close_container(&iter, &var_iter);
            return reply;
        }
    }

    return null;
}

fn buildIconPixmapReply(msg: *DBusMessage) ?*DBusMessage {
    const reply = dbus_message_new_method_return(msg) orelse return null;
    var iter: DBusMessageIter = undefined;
    dbus_message_iter_init_append(reply, &iter);

    var var_iter: DBusMessageIter = undefined;
    _ = dbus_message_iter_open_container(&iter, DBUS_TYPE_VARIANT, "a(iiay)", &var_iter);
    var arr_iter: DBusMessageIter = undefined;
    _ = dbus_message_iter_open_container(&var_iter, DBUS_TYPE_ARRAY, "(iiay)", &arr_iter);

    if (global_icon_bytes) |*icon| {
        if (icon.items.len > 0) {
            var struct_iter: DBusMessageIter = undefined;
            _ = dbus_message_iter_open_container(&arr_iter, DBUS_TYPE_STRUCT, null, &struct_iter);
            const w: i32 = 16;
            const h: i32 = 16;
            _ = dbus_message_iter_append_basic(&struct_iter, DBUS_TYPE_INT32, @as(*const anyopaque, @ptrCast(&w)));
            _ = dbus_message_iter_append_basic(&struct_iter, DBUS_TYPE_INT32, @as(*const anyopaque, @ptrCast(&h)));
            var data_arr_iter: DBusMessageIter = undefined;
            _ = dbus_message_iter_open_container(&struct_iter, DBUS_TYPE_ARRAY, "y", &data_arr_iter);
            for (icon.items) |byte| {
                _ = dbus_message_iter_append_basic(&data_arr_iter, DBUS_TYPE_BYTE, @as(*const anyopaque, @ptrCast(&byte)));
            }
            _ = dbus_message_iter_close_container(&struct_iter, &data_arr_iter);
            _ = dbus_message_iter_close_container(&arr_iter, &struct_iter);
        }
    }

    _ = dbus_message_iter_close_container(&var_iter, &arr_iter);
    _ = dbus_message_iter_close_container(&iter, &var_iter);
    return reply;
}

fn buildToolTipReply(msg: *DBusMessage) ?*DBusMessage {
    const reply = dbus_message_new_method_return(msg) orelse return null;
    var iter: DBusMessageIter = undefined;
    dbus_message_iter_init_append(reply, &iter);

    var var_iter: DBusMessageIter = undefined;
    _ = dbus_message_iter_open_container(&iter, DBUS_TYPE_VARIANT, "(sa(iiay)ss)", &var_iter);

    // Struct: (sa(iiay)ss)
    var struct_iter: DBusMessageIter = undefined;
    _ = dbus_message_iter_open_container(&var_iter, DBUS_TYPE_STRUCT, null, &struct_iter);

    // s: name (tooltip title)
    const tooltip = if (global_tooltip) |t| t else "";
    const z = std.heap.c_allocator.dupeZ(u8, tooltip) catch {
        return null;
    };
    defer std.heap.c_allocator.free(z);
    _ = dbus_message_iter_append_basic(&struct_iter, DBUS_TYPE_STRING, @as(*const anyopaque, @ptrCast(&z)));

    // a(iiay): icon pixmap (empty)
    var icon_arr_iter: DBusMessageIter = undefined;
    _ = dbus_message_iter_open_container(&struct_iter, DBUS_TYPE_ARRAY, "(iiay)", &icon_arr_iter);
    _ = dbus_message_iter_close_container(&struct_iter, &icon_arr_iter);

    // s: title (empty)
    const empty1: [*:0]const u8 = "";
    _ = dbus_message_iter_append_basic(&struct_iter, DBUS_TYPE_STRING, @as(*const anyopaque, @ptrCast(&empty1)));

    // s: description (empty)
    const empty2: [*:0]const u8 = "";
    _ = dbus_message_iter_append_basic(&struct_iter, DBUS_TYPE_STRING, @as(*const anyopaque, @ptrCast(&empty2)));

    _ = dbus_message_iter_close_container(&var_iter, &struct_iter);
    _ = dbus_message_iter_close_container(&iter, &var_iter);
    return reply;
}

fn handlePropertiesGetAll(msg: *DBusMessage) void {
    var iter: DBusMessageIter = undefined;
    if (dbus_message_iter_init(msg, &iter) == 0) return;

    if (dbus_message_iter_get_arg_type(&iter) != DBUS_TYPE_STRING) return;
    var iface_ptr: [*:0]const u8 = undefined;
    dbus_message_iter_get_basic(&iter, @as(*anyopaque, @ptrCast(&iface_ptr)));
    const iface = std.mem.span(iface_ptr);

    const reply = dbus_message_new_method_return(msg) orelse return;
    defer dbus_message_unref(reply);

    var reply_iter: DBusMessageIter = undefined;
    dbus_message_iter_init_append(reply, &reply_iter);

    var dict_iter: DBusMessageIter = undefined;
    _ = dbus_message_iter_open_container(&reply_iter, DBUS_TYPE_ARRAY, "{sv}", &dict_iter);

    if (std.mem.eql(u8, iface, NOTIFIER_IFACE)) {
        appendStatusNotifierProperties(&dict_iter) catch {};
    } else if (std.mem.eql(u8, iface, MENU_IFACE)) {
        appendMenuProperties(&dict_iter) catch {};
    }

    _ = dbus_message_iter_close_container(&reply_iter, &dict_iter);
    sendReply(msg, reply);
}

fn appendStatusNotifierProperties(dict_iter: *DBusMessageIter) !void {
    try appendDictVariantString(dict_iter, "Category", "ApplicationStatus");
    try appendDictVariantString(dict_iter, "Id", "zigtray");
    const title = if (global_tooltip) |t| t else "";
    try appendDictVariantString(dict_iter, "Title", title);
    try appendDictVariantString(dict_iter, "Status", "Active");

    // WindowId: 0
    {
        var entry_iter: DBusMessageIter = undefined;
        _ = dbus_message_iter_open_container(dict_iter, DBUS_TYPE_DICT_ENTRY, null, &entry_iter);
        const key = "WindowId";
        _ = dbus_message_iter_append_basic(&entry_iter, DBUS_TYPE_STRING, @as(*const anyopaque, @ptrCast(&key)));
        var var_iter: DBusMessageIter = undefined;
        _ = dbus_message_iter_open_container(&entry_iter, DBUS_TYPE_VARIANT, "i", &var_iter);
        const zero: i32 = 0;
        _ = dbus_message_iter_append_basic(&var_iter, DBUS_TYPE_INT32, @as(*const anyopaque, @ptrCast(&zero)));
        _ = dbus_message_iter_close_container(&entry_iter, &var_iter);
        _ = dbus_message_iter_close_container(dict_iter, &entry_iter);
    }

    try appendDictVariantString(dict_iter, "IconThemePath", "");
    try appendDictVariantString(dict_iter, "IconName", "");

    // Menu: object path
    {
        var entry_iter: DBusMessageIter = undefined;
        _ = dbus_message_iter_open_container(dict_iter, DBUS_TYPE_DICT_ENTRY, null, &entry_iter);
        const key = "Menu";
        _ = dbus_message_iter_append_basic(&entry_iter, DBUS_TYPE_STRING, @as(*const anyopaque, @ptrCast(&key)));
        var var_iter: DBusMessageIter = undefined;
        _ = dbus_message_iter_open_container(&entry_iter, DBUS_TYPE_VARIANT, "o", &var_iter);
        const menu_path: [*:0]const u8 = MENU_PATH;
        _ = dbus_message_iter_append_basic(&var_iter, DBUS_TYPE_OBJECT_PATH, @as(*const anyopaque, @ptrCast(&menu_path)));
        _ = dbus_message_iter_close_container(&entry_iter, &var_iter);
        _ = dbus_message_iter_close_container(dict_iter, &entry_iter);
    }

    // ItemIsMenu: false
    {
        var entry_iter: DBusMessageIter = undefined;
        _ = dbus_message_iter_open_container(dict_iter, DBUS_TYPE_DICT_ENTRY, null, &entry_iter);
        const key = "ItemIsMenu";
        _ = dbus_message_iter_append_basic(&entry_iter, DBUS_TYPE_STRING, @as(*const anyopaque, @ptrCast(&key)));
        var var_iter: DBusMessageIter = undefined;
        _ = dbus_message_iter_open_container(&entry_iter, DBUS_TYPE_VARIANT, "b", &var_iter);
        const b: u32 = 0;
        _ = dbus_message_iter_append_basic(&var_iter, DBUS_TYPE_BOOLEAN, @as(*const anyopaque, @ptrCast(&b)));
        _ = dbus_message_iter_close_container(&entry_iter, &var_iter);
        _ = dbus_message_iter_close_container(dict_iter, &entry_iter);
    }
}

fn appendMenuProperties(dict_iter: *DBusMessageIter) !void {
    // Version: uint32 0
    {
        var entry_iter: DBusMessageIter = undefined;
        _ = dbus_message_iter_open_container(dict_iter, DBUS_TYPE_DICT_ENTRY, null, &entry_iter);
        const key = "Version";
        _ = dbus_message_iter_append_basic(&entry_iter, DBUS_TYPE_STRING, @as(*const anyopaque, @ptrCast(&key)));
        var var_iter: DBusMessageIter = undefined;
        _ = dbus_message_iter_open_container(&entry_iter, DBUS_TYPE_VARIANT, "u", &var_iter);
        const v: u32 = 0;
        _ = dbus_message_iter_append_basic(&var_iter, DBUS_TYPE_UINT32, @as(*const anyopaque, @ptrCast(&v)));
        _ = dbus_message_iter_close_container(&entry_iter, &var_iter);
        _ = dbus_message_iter_close_container(dict_iter, &entry_iter);
    }
    try appendDictVariantString(dict_iter, "TextDirection", "ltr");
    try appendDictVariantString(dict_iter, "Status", "normal");
}

fn handleActivate(_: *DBusMessage) void {
    // Left click on tray icon — no special action on Linux DBus
}

fn handleContextMenu(_: *DBusMessage) void {
    // Right click — the host shows the menu via GetLayout
}

fn handleSecondaryActivate(_: *DBusMessage) void {}

fn handleScroll(_: *DBusMessage) void {}

fn handleGetLayout(msg: *DBusMessage) void {
    var iter: DBusMessageIter = undefined;
    if (dbus_message_iter_init(msg, &iter) == 0) return;

    // Read parentId (int32), recursionDepth (int32), propertyNames (as)
    if (dbus_message_iter_get_arg_type(&iter) != DBUS_TYPE_INT32) return;
    var parent_id: i32 = undefined;
    dbus_message_iter_get_basic(&iter, @as(*anyopaque, @ptrCast(&parent_id)));
    dbus_message_iter_next(&iter);

    if (dbus_message_iter_get_arg_type(&iter) != DBUS_TYPE_INT32) return;
    var recursion_depth: i32 = undefined;
    dbus_message_iter_get_basic(&iter, @as(*anyopaque, @ptrCast(&recursion_depth)));

    const reply = dbus_message_new_method_return(msg) orelse return;
    defer dbus_message_unref(reply);

    var reply_iter: DBusMessageIter = undefined;
    dbus_message_iter_init_append(reply, &reply_iter);

    // revision: uint32
    const rev = global_menu_version;
    _ = dbus_message_iter_append_basic(&reply_iter, DBUS_TYPE_UINT32, @as(*const anyopaque, @ptrCast(&rev)));

    // layout: (ia{sv}av)
    var layout_struct: DBusMessageIter = undefined;
    _ = dbus_message_iter_open_container(&reply_iter, DBUS_TYPE_STRUCT, null, &layout_struct);

    const node = if (parent_id == 0)
        global_menu_root
    else if (global_menu_root) |root|
        findMenuNode(parent_id, root)
    else
        null;

    if (node) |n| {
        appendMenuNodeToIter(&layout_struct, n, recursion_depth) catch {};
    } else {
        // empty layout
        const zero: i32 = 0;
        _ = dbus_message_iter_append_basic(&layout_struct, DBUS_TYPE_INT32, @as(*const anyopaque, @ptrCast(&zero)));
        var dict_iter: DBusMessageIter = undefined;
        _ = dbus_message_iter_open_container(&layout_struct, DBUS_TYPE_ARRAY, "{sv}", &dict_iter);
        _ = dbus_message_iter_close_container(&layout_struct, &dict_iter);
        var child_arr_iter: DBusMessageIter = undefined;
        _ = dbus_message_iter_open_container(&layout_struct, DBUS_TYPE_ARRAY, "v", &child_arr_iter);
        _ = dbus_message_iter_close_container(&layout_struct, &child_arr_iter);
    }

    _ = dbus_message_iter_close_container(&reply_iter, &layout_struct);
    sendReply(msg, reply);
}

fn appendMenuNodeToIter(struct_iter: *DBusMessageIter, node: *MenuNode, depth: i32) !void {
    // id: int32
    _ = dbus_message_iter_append_basic(struct_iter, DBUS_TYPE_INT32, @as(*const anyopaque, @ptrCast(&node.id)));

    // properties: a{sv}
    var dict_iter: DBusMessageIter = undefined;
    _ = dbus_message_iter_open_container(struct_iter, DBUS_TYPE_ARRAY, "{sv}", &dict_iter);
    try appendNodeProperties(&dict_iter, node);
    _ = dbus_message_iter_close_container(struct_iter, &dict_iter);

    // children: av
    var child_arr_iter: DBusMessageIter = undefined;
    _ = dbus_message_iter_open_container(struct_iter, DBUS_TYPE_ARRAY, "v", &child_arr_iter);

    if (depth == 0) {
        // No children
    } else if (depth < 0) {
        // Include all children recursively (-1)
        for (node.children.items) |child| {
            var child_var: DBusMessageIter = undefined;
            _ = dbus_message_iter_open_container(&child_arr_iter, DBUS_TYPE_VARIANT, "(ia{sv}av)", &child_var);
            var child_struct: DBusMessageIter = undefined;
            _ = dbus_message_iter_open_container(&child_var, DBUS_TYPE_STRUCT, null, &child_struct);
            try appendMenuNodeToIter(&child_struct, child, depth);
            _ = dbus_message_iter_close_container(&child_var, &child_struct);
            _ = dbus_message_iter_close_container(&child_arr_iter, &child_var);
        }
    } else {
        // Include children up to depth
        for (node.children.items) |child| {
            var child_var: DBusMessageIter = undefined;
            _ = dbus_message_iter_open_container(&child_arr_iter, DBUS_TYPE_VARIANT, "(ia{sv}av)", &child_var);
            var child_struct: DBusMessageIter = undefined;
            _ = dbus_message_iter_open_container(&child_var, DBUS_TYPE_STRUCT, null, &child_struct);
            try appendMenuNodeToIter(&child_struct, child, depth - 1);
            _ = dbus_message_iter_close_container(&child_var, &child_struct);
            _ = dbus_message_iter_close_container(&child_arr_iter, &child_var);
        }
    }

    _ = dbus_message_iter_close_container(struct_iter, &child_arr_iter);
}

fn handleGetGroupProperties(msg: *DBusMessage) void {
    const reply = dbus_message_new_method_return(msg) orelse return;
    defer dbus_message_unref(reply);

    var reply_iter: DBusMessageIter = undefined;
    dbus_message_iter_init_append(reply, &reply_iter);

    // Return empty array a(ia{sv})
    var arr_iter: DBusMessageIter = undefined;
    _ = dbus_message_iter_open_container(&reply_iter, DBUS_TYPE_ARRAY, "(ia{sv})", &arr_iter);
    _ = dbus_message_iter_close_container(&reply_iter, &arr_iter);

    sendReply(msg, reply);
}

fn handleGetProperty(msg: *DBusMessage) void {
    var iter: DBusMessageIter = undefined;
    if (dbus_message_iter_init(msg, &iter) == 0) return;

    if (dbus_message_iter_get_arg_type(&iter) != DBUS_TYPE_INT32) return;
    var _id: i32 = undefined;
    dbus_message_iter_get_basic(&iter, @as(*anyopaque, @ptrCast(&_id)));
    dbus_message_iter_next(&iter);

    if (dbus_message_iter_get_arg_type(&iter) != DBUS_TYPE_STRING) return;
    var name_ptr: [*:0]const u8 = undefined;
    dbus_message_iter_get_basic(&iter, @as(*anyopaque, @ptrCast(&name_ptr)));

    // Return empty variant
    const reply = dbus_message_new_method_return(msg) orelse return;
    defer dbus_message_unref(reply);
    var reply_iter: DBusMessageIter = undefined;
    dbus_message_iter_init_append(reply, &reply_iter);
    var var_iter: DBusMessageIter = undefined;
    _ = dbus_message_iter_open_container(&reply_iter, DBUS_TYPE_VARIANT, "s", &var_iter);
    const empty: [*:0]const u8 = "";
    _ = dbus_message_iter_append_basic(&var_iter, DBUS_TYPE_STRING, @as(*const anyopaque, @ptrCast(&empty)));
    _ = dbus_message_iter_close_container(&reply_iter, &var_iter);
    sendReply(msg, reply);
}

fn handleEvent(msg: *DBusMessage) void {
    var iter: DBusMessageIter = undefined;
    if (dbus_message_iter_init(msg, &iter) == 0) return;

    if (dbus_message_iter_get_arg_type(&iter) != DBUS_TYPE_INT32) return;
    var id: i32 = undefined;
    dbus_message_iter_get_basic(&iter, @as(*anyopaque, @ptrCast(&id)));
    dbus_message_iter_next(&iter);

    if (dbus_message_iter_get_arg_type(&iter) != DBUS_TYPE_STRING) return;
    var event_ptr: [*:0]const u8 = undefined;
    dbus_message_iter_get_basic(&iter, @as(*anyopaque, @ptrCast(&event_ptr)));

    const event = std.mem.span(event_ptr);

    if (std.mem.eql(u8, event, "clicked")) {
        for (global_menu_items.items) |item| {
            if (item.id == @as(u32, @intCast(id))) {
                if (item.is_checkable) {
                    item.checked = !item.checked;
                    if (global_menu_root) |root| {
                        if (findMenuNode(id, root)) |node| {
                            node.toggle_state = if (item.checked) 1 else 0;
                            sendItemsPropertiesUpdated(id, node);
                        }
                    }
                }
                if (item.callback) |cb| cb(item.ctx);
                break;
            }
        }
    }

    const reply = dbus_message_new_method_return(msg) orelse return;
    sendReply(msg, reply);
}

fn handleEventGroup(msg: *DBusMessage) void {
    const reply = dbus_message_new_method_return(msg) orelse return;
    defer dbus_message_unref(reply);
    var reply_iter: DBusMessageIter = undefined;
    dbus_message_iter_init_append(reply, &reply_iter);
    var arr_iter: DBusMessageIter = undefined;
    _ = dbus_message_iter_open_container(&reply_iter, DBUS_TYPE_ARRAY, "i", &arr_iter);
    _ = dbus_message_iter_close_container(&reply_iter, &arr_iter);
    sendReply(msg, reply);
}

fn handleAboutToShow(msg: *DBusMessage) void {
    const reply = dbus_message_new_method_return(msg) orelse return;
    defer dbus_message_unref(reply);
    var iter: DBusMessageIter = undefined;
    dbus_message_iter_init_append(reply, &iter);
    const b: u32 = 0;
    _ = dbus_message_iter_append_basic(&iter, DBUS_TYPE_BOOLEAN, @as(*const anyopaque, @ptrCast(&b)));
    sendReply(msg, reply);
}

fn handleAboutToShowGroup(msg: *DBusMessage) void {
    const reply = dbus_message_new_method_return(msg) orelse return;
    defer dbus_message_unref(reply);
    var reply_iter: DBusMessageIter = undefined;
    dbus_message_iter_init_append(reply, &reply_iter);
    // updatesNeeded: ai (empty)
    var arr1: DBusMessageIter = undefined;
    _ = dbus_message_iter_open_container(&reply_iter, DBUS_TYPE_ARRAY, "i", &arr1);
    _ = dbus_message_iter_close_container(&reply_iter, &arr1);
    // idErrors: ai (empty)
    var arr2: DBusMessageIter = undefined;
    _ = dbus_message_iter_open_container(&reply_iter, DBUS_TYPE_ARRAY, "i", &arr2);
    _ = dbus_message_iter_close_container(&reply_iter, &arr2);
    sendReply(msg, reply);
}

// ── DBus message filter ───────────────────────────────────────────────

fn messageFilter(_: *DBusConnection, msg: *DBusMessage, _: ?*anyopaque) callconv(.C) DBusHandlerResult {
    if (dbus_message_is_method_call(msg, INTROSPECTABLE_IFACE, "Introspect") != 0) {
        handleIntrospect(msg);
        return DBUS_HANDLER_RESULT_HANDLED;
    }
    if (dbus_message_is_method_call(msg, PROPERTIES_IFACE, "Get") != 0) {
        handlePropertiesGet(msg);
        return DBUS_HANDLER_RESULT_HANDLED;
    }
    if (dbus_message_is_method_call(msg, PROPERTIES_IFACE, "GetAll") != 0) {
        handlePropertiesGetAll(msg);
        return DBUS_HANDLER_RESULT_HANDLED;
    }
    if (dbus_message_is_method_call(msg, PROPERTIES_IFACE, "Set") != 0) {
        return DBUS_HANDLER_RESULT_HANDLED;
    }

    const path = dbus_message_get_path(msg) orelse return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
    const path_span = std.mem.span(path);

    if (std.mem.eql(u8, path_span, NOTIFIER_PATH)) {
        if (dbus_message_is_method_call(msg, NOTIFIER_IFACE, "Activate") != 0) {
            handleActivate(msg);
            return DBUS_HANDLER_RESULT_HANDLED;
        }
        if (dbus_message_is_method_call(msg, NOTIFIER_IFACE, "ContextMenu") != 0) {
            handleContextMenu(msg);
            return DBUS_HANDLER_RESULT_HANDLED;
        }
        if (dbus_message_is_method_call(msg, NOTIFIER_IFACE, "SecondaryActivate") != 0) {
            handleSecondaryActivate(msg);
            return DBUS_HANDLER_RESULT_HANDLED;
        }
        if (dbus_message_is_method_call(msg, NOTIFIER_IFACE, "Scroll") != 0) {
            handleScroll(msg);
            return DBUS_HANDLER_RESULT_HANDLED;
        }
    }

    if (std.mem.eql(u8, path_span, MENU_PATH)) {
        if (dbus_message_is_method_call(msg, MENU_IFACE, "GetLayout") != 0) {
            handleGetLayout(msg);
            return DBUS_HANDLER_RESULT_HANDLED;
        }
        if (dbus_message_is_method_call(msg, MENU_IFACE, "GetGroupProperties") != 0) {
            handleGetGroupProperties(msg);
            return DBUS_HANDLER_RESULT_HANDLED;
        }
        if (dbus_message_is_method_call(msg, MENU_IFACE, "GetProperty") != 0) {
            handleGetProperty(msg);
            return DBUS_HANDLER_RESULT_HANDLED;
        }
        if (dbus_message_is_method_call(msg, MENU_IFACE, "Event") != 0) {
            handleEvent(msg);
            return DBUS_HANDLER_RESULT_HANDLED;
        }
        if (dbus_message_is_method_call(msg, MENU_IFACE, "EventGroup") != 0) {
            handleEventGroup(msg);
            return DBUS_HANDLER_RESULT_HANDLED;
        }
        if (dbus_message_is_method_call(msg, MENU_IFACE, "AboutToShow") != 0) {
            handleAboutToShow(msg);
            return DBUS_HANDLER_RESULT_HANDLED;
        }
        if (dbus_message_is_method_call(msg, MENU_IFACE, "AboutToShowGroup") != 0) {
            handleAboutToShowGroup(msg);
            return DBUS_HANDLER_RESULT_HANDLED;
        }
    }

    return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
}

// ── Registration with StatusNotifierWatcher ───────────────────────────

fn registerWithWatcher(conn: *DBusConnection) void {
    const msg = dbus_message_new_method_call(
        WATCHER_SERVICE,
        WATCHER_PATH,
        WATCHER_IFACE,
        "RegisterStatusNotifierItem",
    ) orelse return;
    defer dbus_message_unref(msg);

    var iter: DBusMessageIter = undefined;
    dbus_message_iter_init_append(msg, &iter);

    const our_path: [*:0]const u8 = NOTIFIER_PATH;
    _ = dbus_message_iter_append_basic(&iter, DBUS_TYPE_OBJECT_PATH, @as(*const anyopaque, @ptrCast(&our_path)));

    _ = dbus_connection_send(conn, msg, null);
    _ = dbus_connection_flush(conn);
}

// ── Context ───────────────────────────────────────────────────────────

pub const Context = struct {
    allocator: std.mem.Allocator,
};

// ── Init / Deinit ─────────────────────────────────────────────────────

pub fn init(ctx: *Context, tray: *anyopaque, allocator: std.mem.Allocator) !void {
    global_current_tray = tray;
    global_allocator = allocator;
    global_quit_flag = false;
    global_next_id = 1;
    global_menu_version = 0;
    global_menu_items = .{ .items = &.{}, .capacity = 0 };
    global_menu_nodes = .{ .items = &.{}, .capacity = 0 };

    ctx.* = .{ .allocator = allocator };

    // Create root menu node
    global_menu_root = try createMenuNode(0);

    // Connect to session bus
    var err: DBusError = undefined;
    dbus_error_init(&err);

    const conn = dbus_bus_get(DBUS_BUS_SESSION, &err) orelse {
        if (dbus_error_is_set(&err) != 0) {
            const msg = std.mem.span(err.message orelse "unknown error");
            std.debug.print("systray error: failed to connect to DBus: {s}\n", .{msg});
            dbus_error_free(&err);
        }
        return error.TrayInitFailed;
    };
    global_conn = conn;

    // Request a well-known name on the bus
    _ = dbus_bus_request_name(conn, "org.kde.StatusNotifierItem", DBUS_NAME_FLAG_DO_NOT_QUEUE, &err);
    if (dbus_error_is_set(&err) != 0) {
        dbus_error_free(&err);
    }

    // Add the message filter
    dbus_connection_add_filter(conn, messageFilter, null, null);

    // Register with StatusNotifierWatcher
    registerWithWatcher(conn);
}

pub fn deinit(_: *Context) void {
    global_quit_flag = true;

    if (global_conn) |conn| {
        dbus_connection_unref(conn);
        global_conn = null;
    }

    // Free menu nodes
    if (global_menu_root) |root| {
        freeMenuNodeTree(root);
        global_allocator.destroy(root);
        global_menu_root = null;
    }

    global_menu_items.deinit(global_allocator);
    global_menu_nodes.deinit(global_allocator);

    if (global_icon_bytes) |*icon| {
        icon.deinit();
        global_icon_bytes = null;
    }
    if (global_tooltip) |t| {
        global_allocator.free(t);
        global_tooltip = null;
    }
}

fn freeMenuNodeTree(node: *MenuNode) void {
    for (node.children.items) |child| {
        freeMenuNodeTree(child);
        global_allocator.destroy(child);
    }
    node.children.deinit();
    if (node.icon_data) |*icon| {
        icon.deinit();
    }
}

// ── Run / Quit ────────────────────────────────────────────────────────

pub fn run(_: *Context) void {
    const conn = global_conn orelse return;

    while (!global_quit_flag) {
        _ = dbus_connection_read_write(conn, 100);
        while (true) {
            const status = dbus_connection_dispatch(conn);
            if (status == DBUS_DISPATCH_COMPLETE) break;
            if (status == DBUS_DISPATCH_NEED_MEMORY) {
                std.time.sleep(10 * std.time.ns_per_ms);
                break;
            }
        }
    }
}

pub fn quit(_: *Context) void {
    global_quit_flag = true;
}

// ── Icon ──────────────────────────────────────────────────────────────

pub fn setIcon(_: *Context, icon_bytes: []const u8) !void {
    if (global_icon_bytes) |*icon| {
        icon.deinit();
        global_icon_bytes = null;
    }
    if (icon_bytes.len > 0) {
        var arr = std.ArrayList(u8).init(global_allocator);
        try arr.appendSlice(icon_bytes);
        global_icon_bytes = arr;
    }

    // Emit NewIcon signal
    if (global_conn) |conn| {
        const sig = dbus_message_new_signal(NOTIFIER_PATH, NOTIFIER_IFACE, "NewIcon") orelse return;
        defer dbus_message_unref(sig);
        _ = dbus_connection_send(conn, sig, null);
        _ = dbus_connection_flush(conn);
    }
}

pub fn setIconFromFilePath(_: *Context, path: []const u8) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const data = try file.readToEndAlloc(global_allocator, 10 * 1024 * 1024);
    defer global_allocator.free(data);
    try setIcon(null, data);
}

pub fn setTooltip(_: *Context, tooltip: []const u8) !void {
    if (global_tooltip) |t| {
        global_allocator.free(t);
        global_tooltip = null;
    }
    global_tooltip = try global_allocator.dupe(u8, tooltip);

    // Emit NewToolTip signal
    if (global_conn) |conn| {
        const sig = dbus_message_new_signal(NOTIFIER_PATH, NOTIFIER_IFACE, "NewToolTip") orelse return;
        defer dbus_message_unref(sig);
        _ = dbus_connection_send(conn, sig, null);
        _ = dbus_connection_flush(conn);
    }
}

// ── Menu ──────────────────────────────────────────────────────────────

pub fn addMenuItem(_: *Context, tray: anytype, title: []const u8, tooltip: []const u8, is_checkable: bool, checked: bool) !*MenuItem {
    _ = tooltip;
    const item = try global_allocator.create(MenuItem);
    const id = nextId();
    item.* = .{
        .id = id,
        .title = try global_allocator.dupe(u8, title),
        .tooltip = "",
        .disabled = false,
        .checked = checked,
        .is_checkable = is_checkable,
        .parent = null,
        .callback = null,
        .ctx = null,
        .tray = @ptrCast(tray),
    };
    try global_menu_items.append(global_allocator, item);

    // Create menu node
    const node = try createMenuNode(@as(i32, @intCast(id)));
    node.label = try global_allocator.dupe(u8, title);
    node.enabled = !item.disabled;
    node.visible = true;
    if (is_checkable) {
        node.toggle_type = try global_allocator.dupe(u8, "checkmark");
        node.toggle_state = if (checked) 1 else 0;
    } else {
        node.toggle_type = "";
        node.toggle_state = 0;
    }

    // Add to root menu
    if (global_menu_root) |root| {
        try root.children.append(node);
    }

    sendLayoutUpdated();
    return item;
}

pub fn addSeparator(_: *Context) !void {
    const id = nextId();
    const node = try createMenuNode(@as(i32, @intCast(id)));
    node.is_separator = true;

    if (global_menu_root) |root| {
        try root.children.append(node);
    }

    sendLayoutUpdated();
}

pub fn resetMenu(_: *Context) void {
    if (global_menu_root) |root| {
        for (root.children.items) |child| {
            freeMenuNodeTree(child);
            global_allocator.destroy(child);
        }
        root.children.clearRetainingCapacity();
    }
    global_menu_items.clearRetainingCapacity();
    sendLayoutUpdated();
}

// ── Sub-menu ──────────────────────────────────────────────────────────

pub fn menuItemAddSubMenuItem(_: *Context, _: anytype, parent_item: *MenuItem, title: []const u8, tooltip: []const u8, is_checkable: bool, checked: bool) !*MenuItem {
    _ = tooltip;
    const item = try global_allocator.create(MenuItem);
    const id = nextId();
    item.* = .{
        .id = id,
        .title = try global_allocator.dupe(u8, title),
        .tooltip = "",
        .disabled = false,
        .checked = checked,
        .is_checkable = is_checkable,
        .parent = parent_item,
        .callback = null,
        .ctx = null,
        .tray = parent_item.tray,
    };
    try global_menu_items.append(global_allocator, item);

    // Create menu node
    const node = try createMenuNode(@as(i32, @intCast(id)));
    node.label = try global_allocator.dupe(u8, title);
    node.enabled = true;
    node.visible = true;
    if (is_checkable) {
        node.toggle_type = try global_allocator.dupe(u8, "checkmark");
        node.toggle_state = if (checked) 1 else 0;
    }

    // Find parent node and add as child
    if (global_menu_root) |root| {
        const parent_id: i32 = @intCast(parent_item.id);
        if (findMenuNode(parent_id, root)) |parent_node| {
            parent_node.children_display = try global_allocator.dupe(u8, "submenu");
            try parent_node.children.append(node);
        }
    }

    sendLayoutUpdated();
    return item;
}

pub fn menuItemAddSeparator(_: *Context, parent_item: *MenuItem) !void {
    const id = nextId();
    const node = try createMenuNode(@as(i32, @intCast(id)));
    node.is_separator = true;

    if (global_menu_root) |root| {
        const parent_id: i32 = @intCast(parent_item.id);
        if (findMenuNode(parent_id, root)) |parent_node| {
            try parent_node.children.append(node);
        }
    }

    sendLayoutUpdated();
}

// ── Menu item property updates ────────────────────────────────────────

pub fn menuItemSetTitle(_: *Context, item: *MenuItem, title: []const u8) void {
    global_allocator.free(item.title);
    item.title = global_allocator.dupe(u8, title) catch return;

    if (global_menu_root) |root| {
        const id: i32 = @intCast(item.id);
        if (findMenuNode(id, root)) |node| {
            if (node.label) |old| global_allocator.free(old);
            node.label = global_allocator.dupe(u8, title) catch return;
            sendItemsPropertiesUpdated(id, node);
        }
    }
}

pub fn menuItemSetTooltip(_: *Context, _: *MenuItem, _: []const u8) void {}

pub fn menuItemEnable(_: *Context, item: *MenuItem) void {
    item.disabled = false;
    if (global_menu_root) |root| {
        const id: i32 = @intCast(item.id);
        if (findMenuNode(id, root)) |node| {
            node.enabled = true;
            sendItemsPropertiesUpdated(id, node);
        }
    }
}

pub fn menuItemDisable(_: *Context, item: *MenuItem) void {
    item.disabled = true;
    if (global_menu_root) |root| {
        const id: i32 = @intCast(item.id);
        if (findMenuNode(id, root)) |node| {
            node.enabled = false;
            sendItemsPropertiesUpdated(id, node);
        }
    }
}

pub fn menuItemCheck(_: *Context, item: *MenuItem) void {
    item.checked = true;
    if (global_menu_root) |root| {
        const id: i32 = @intCast(item.id);
        if (findMenuNode(id, root)) |node| {
            node.toggle_state = 1;
            sendItemsPropertiesUpdated(id, node);
        }
    }
}

pub fn menuItemUncheck(_: *Context, item: *MenuItem) void {
    item.checked = false;
    if (global_menu_root) |root| {
        const id: i32 = @intCast(item.id);
        if (findMenuNode(id, root)) |node| {
            node.toggle_state = 0;
            sendItemsPropertiesUpdated(id, node);
        }
    }
}

pub fn menuItemHide(_: *Context, item: *MenuItem) void {
    if (global_menu_root) |root| {
        const id: i32 = @intCast(item.id);
        if (findMenuNode(id, root)) |node| {
            node.visible = false;
            sendItemsPropertiesUpdated(id, node);
        }
    }
}

pub fn menuItemShow(_: *Context, item: *MenuItem) void {
    if (global_menu_root) |root| {
        const id: i32 = @intCast(item.id);
        if (findMenuNode(id, root)) |node| {
            node.visible = true;
            sendItemsPropertiesUpdated(id, node);
        }
    }
}

pub fn menuItemRemove(_: *Context, item: *MenuItem) void {
    if (global_menu_root) |root| {
        const id: i32 = @intCast(item.id);
        _ = removeMenuNode(id, root);
        for (global_menu_items.items, 0..) |mi, i| {
            if (mi == item) {
                _ = global_menu_items.swapRemove(i);
                break;
            }
        }
        sendLayoutUpdated();
    }
}

pub fn menuItemSetIconFromFilePath(_: *Context, _: *MenuItem, path: []const u8) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const data = try file.readToEndAlloc(global_allocator, 10 * 1024 * 1024);
    global_allocator.free(data);
}
