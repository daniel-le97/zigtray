//! macOS system tray implementation using AppKit (via Objective-C).
//! Compiles `macos.m` alongside Zig and calls its C bridge functions.

const std = @import("std");
const MenuItem = @import("../systray.zig").MenuItem;

// ── C bridge functions (namespaced to avoid name conflicts) ───────────

pub const c = struct {
    pub extern "c" fn registerSystray() void;
    pub extern "c" fn nativeLoop() void;
    pub extern "c" fn nativeEnd() void;
    pub extern "c" fn nativeStart() void;
    pub extern "c" fn setIcon(bytes: [*]const u8, len: i32, isTemplate: bool) void;
    pub extern "c" fn setTitle(title: [*:0]u8) void;
    pub extern "c" fn setTooltip(tooltip: [*:0]u8) void;
    pub extern "c" fn add_or_update_menu_item(menuId: i32, parentMenuId: i32, title: [*:0]u8, tooltip: [*:0]u8, disabled: i16, checked: i16, isCheckable: i16) void;
    pub extern "c" fn add_separator(menuId: i32, parentId: i32) void;
    pub extern "c" fn hide_menu_item(menuId: i32) void;
    pub extern "c" fn show_menu_item(menuId: i32) void;
    pub extern "c" fn remove_menu_item(menuId: i32) void;
    pub extern "c" fn reset_menu() void;
    pub extern "c" fn show_menu() void;
    pub extern "c" fn quit() void;
};

// ── Callbacks exported as C symbols (called by macos.m) ───────────────

var current_context: ?*Context = null;
var menu_items: std.ArrayListUnmanaged(*MenuItem) = .{ .items = &.{}, .capacity = 0 };
var next_id: u32 = 1;
var menu_allocator: std.mem.Allocator = undefined;

export fn systray_ready() void {}
export fn systray_on_exit() void {}

export fn systray_left_click() void {
    c.show_menu();
}

export fn systray_right_click() void {
    c.show_menu();
}

export fn systray_menu_item_selected(menu_id: i32) void {
    const id = @as(u32, @intCast(menu_id));
    for (menu_items.items) |item| {
        if (item.id == id) {
            if (item.callback) |cb| cb(item.ctx);
            break;
        }
    }
}

// ── Context ───────────────────────────────────────────────────────────

pub const Context = struct {
    allocator: std.mem.Allocator,
};

// ── Init / Deinit ─────────────────────────────────────────────────────

pub fn init(ctx: *Context, tray: *anyopaque, allocator: std.mem.Allocator) !void {
    _ = tray;
    current_context = ctx;
    menu_allocator = allocator;
    menu_items = std.ArrayListUnmanaged(*MenuItem){ .items = &.{}, .capacity = 0 };
    ctx.* = .{ .allocator = allocator };

    // On macOS this enters the Cocoa event loop after setting up the delegate.
    c.registerSystray();
}

pub fn deinit(ctx: *Context) void {
    _ = ctx;
    for (menu_items.items) |item| {
        menu_allocator.free(item.title);
        menu_allocator.free(item.tooltip);
        menu_allocator.destroy(item);
    }
    menu_items.deinit(menu_allocator);
}

// ── Run / Quit ────────────────────────────────────────────────────────

pub fn run(_: *Context) void {
    c.nativeLoop();
}

pub fn quit(_: *Context) void {
    c.quit();
}

// ── Icon ──────────────────────────────────────────────────────────────

pub fn setIcon(_: *Context, icon_bytes: []const u8) !void {
    if (icon_bytes.len == 0) return error.InvalidIconData;
    c.setIcon(icon_bytes.ptr, @intCast(icon_bytes.len), false);
}

pub fn setIconFromFilePath(_: *Context, path: []const u8) !void {
    const file = std.fs.cwd().openFile(path, .{}) catch return error.FileOpenFailed;
    defer file.close();
    const data = file.readToEndAlloc(menu_allocator, 10 * 1024 * 1024) catch return error.FileReadFailed;
    defer menu_allocator.free(data);
    c.setIcon(data.ptr, @intCast(data.len), false);
}

pub fn setTooltip(_: *Context, tooltip: []const u8) !void {
    const z = try std.heap.c_allocator.dupeZ(u8, tooltip);
    c.setTooltip(@ptrCast(z));
}

// ── Menu ──────────────────────────────────────────────────────────────

pub fn addMenuItem(ctx: *Context, tray: anytype, title: []const u8, tooltip: []const u8, is_checkable: bool, checked: bool) !*MenuItem {
    const item = try ctx.allocator.create(MenuItem);
    const id = nextId();
    item.* = .{
        .id = id,
        .title = try ctx.allocator.dupe(u8, title),
        .tooltip = try ctx.allocator.dupe(u8, tooltip),
        .disabled = false,
        .checked = checked,
        .is_checkable = is_checkable,
        .parent = null,
        .callback = null,
        .ctx = null,
        .tray = @ptrCast(tray),
    };
    try menu_items.append(menu_allocator, item);

    const title_z = try std.heap.c_allocator.dupeZ(u8, title);
    const tooltip_z = try std.heap.c_allocator.dupeZ(u8, tooltip);
    c.add_or_update_menu_item(
        @intCast(id),
        0,
        @ptrCast(title_z),
        @ptrCast(tooltip_z),
        0,
        if (checked) @as(i16, 1) else 0,
        if (is_checkable) @as(i16, 1) else 0,
    );
    return item;
}

pub fn addSeparator(_: *Context) !void {
    c.add_separator(0, 0);
}

pub fn resetMenu(_: *Context) void {
    c.reset_menu();
    menu_items.clearRetainingCapacity();
}

/// Update the native NSMenuItem to reflect the current Zig-side state.
fn updateNativeMenuItem(item: *MenuItem) void {
    const title_z = std.heap.c_allocator.dupeZ(u8, item.title) catch return;
    const tooltip_z = std.heap.c_allocator.dupeZ(u8, item.tooltip) catch return;
    c.add_or_update_menu_item(
        @intCast(item.id),
        @intCast(item.parentId()),
        @ptrCast(title_z),
        @ptrCast(tooltip_z),
        if (item.disabled) @as(i16, 1) else 0,
        if (item.checked) @as(i16, 1) else 0,
        if (item.is_checkable) @as(i16, 1) else 0,
    );
}

pub fn menuItemSetTitle(_: *Context, item: *MenuItem, title: []const u8) void {
    const old = item.title;
    item.title = menu_allocator.dupe(u8, title) catch return;
    menu_allocator.free(old);
    updateNativeMenuItem(item);
}

pub fn menuItemSetTooltip(_: *Context, item: *MenuItem, tooltip: []const u8) void {
    const old = item.tooltip;
    item.tooltip = menu_allocator.dupe(u8, tooltip) catch return;
    menu_allocator.free(old);
    updateNativeMenuItem(item);
}

pub fn menuItemEnable(_: *Context, item: *MenuItem) void {
    item.disabled = false;
    updateNativeMenuItem(item);
}
pub fn menuItemDisable(_: *Context, item: *MenuItem) void {
    item.disabled = true;
    updateNativeMenuItem(item);
}
pub fn menuItemCheck(_: *Context, item: *MenuItem) void {
    item.checked = true;
    updateNativeMenuItem(item);
}
pub fn menuItemUncheck(_: *Context, item: *MenuItem) void {
    item.checked = false;
    updateNativeMenuItem(item);
}

pub fn menuItemHide(_: *Context, item: *MenuItem) void {
    c.hide_menu_item(@intCast(item.id));
}
pub fn menuItemShow(_: *Context, item: *MenuItem) void {
    c.show_menu_item(@intCast(item.id));
}

pub fn menuItemRemove(ctx: *Context, item: *MenuItem) void {
    c.remove_menu_item(@intCast(item.id));
    for (menu_items.items, 0..) |mi, i| {
        if (mi == item) {
            _ = menu_items.swapRemove(i);
            break;
        }
    }
    ctx.allocator.free(item.title);
    ctx.allocator.free(item.tooltip);
    ctx.allocator.destroy(item);
}

pub fn menuItemAddSubMenuItem(ctx: *Context, parent: *MenuItem, title: []const u8, tooltip: []const u8, is_checkable: bool, checked: bool) !*MenuItem {
    const child = try ctx.allocator.create(MenuItem);
    const id = nextId();
    child.* = .{
        .id = id,
        .title = try ctx.allocator.dupe(u8, title),
        .tooltip = try ctx.allocator.dupe(u8, tooltip),
        .disabled = false,
        .checked = checked,
        .is_checkable = is_checkable,
        .parent = parent,
        .callback = null,
        .ctx = null,
        .tray = parent.tray,
    };
    try menu_items.append(menu_allocator, child);

    const title_z = try std.heap.c_allocator.dupeZ(u8, title);
    const tooltip_z = try std.heap.c_allocator.dupeZ(u8, tooltip);
    c.add_or_update_menu_item(
        @intCast(id),
        @intCast(parent.id),
        @ptrCast(title_z),
        @ptrCast(tooltip_z),
        0,
        if (checked) @as(i16, 1) else 0,
        if (is_checkable) @as(i16, 1) else 0,
    );
    return child;
}

pub fn menuItemAddSeparator(_: *Context, item: *MenuItem) !void {
    c.add_separator(0, @intCast(item.id));
}

pub fn menuItemSetIconFromFilePath(_: *Context, _: *MenuItem, _: []const u8) !void {}

// ── Helpers ───────────────────────────────────────────────────────────

fn nextId() u32 {
    const id = next_id;
    next_id += 1;
    return id;
}
