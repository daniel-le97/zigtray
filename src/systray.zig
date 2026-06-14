//! Cross-platform system tray API.
//! Port of fyne-io/systray to Zig.
//!
//! Each `MenuItem` holds a back-reference to its parent `Tray`, so you
//! can call methods directly on items without passing the tray:
//!
//! ```zig
//! const quit = try tray.addMenuItem("Quit", "Quit the app");
//! quit.onClick = onQuit;
//! quit.setTitle("Goodbye");
//! ```
//!
//! ## Windows notes
//! - `init()` uses `self: *Tray` (pointer receiver). Caller declares
//!   `var tray: Tray = undefined` and passes `&tray`.
//! - We do NOT call NIM_SETVERSION to avoid a union-layout mismatch.
//!   Windows sends WM_LBUTTONUP/WM_RBUTTONUP (0x202/0x205).
//! - WM_CREATE fires *during* CreateWindowExW, before the tray pointer
//!   is stored. The window proc guards against the null case.

const std = @import("std");
const builtin = @import("builtin");

pub const TrayOptions = @import("systray/types.zig").TrayOptions;

const Impl = switch (builtin.target.os.tag) {
    .windows => @import("systray/windows.zig"),
    .macos => @import("systray/macos.zig"),
    .linux => @import("systray/linux.zig"),
    else => @compileError("unsupported platform: " ++ @tagName(builtin.target.os.tag)),
};

// ── MenuItem ──────────────────────────────────────────────────────────

/// A menu item in the system tray context menu.
/// Holds a `tray` back-pointer so methods like `.setTitle()` can update
/// the native menu without you having to pass the tray everywhere.
pub const MenuItem = struct {
    id: u32,
    title: []const u8,
    tooltip: []const u8,
    disabled: bool,
    checked: bool,
    is_checkable: bool,
    parent: ?*MenuItem,

    /// Internal callback storage.
    callback: ?*const fn (ctx: ?*anyopaque) void = null,
    /// User-defined context passed to the callback.
    ctx: ?*anyopaque = null,

    /// Back-reference to the parent Tray (set by `Tray.addMenuItem`).
    tray: ?*Tray = null,

    // ── Methods ──────────────────────────────────────────────────────

    pub fn setTitle(self: *MenuItem, title: []const u8) void {
        const t = self.tray orelse return;
        Impl.menuItemSetTitle(&t.impl, self, title);
    }

    pub fn setTooltip(self: *MenuItem, tooltip: []const u8) void {
        const t = self.tray orelse return;
        Impl.menuItemSetTooltip(&t.impl, self, tooltip);
    }

    pub fn enable(self: *MenuItem) void {
        const t = self.tray orelse return;
        Impl.menuItemEnable(&t.impl, self);
    }

    pub fn disable(self: *MenuItem) void {
        const t = self.tray orelse return;
        Impl.menuItemDisable(&t.impl, self);
    }

    pub fn check(self: *MenuItem) void {
        const t = self.tray orelse return;
        Impl.menuItemCheck(&t.impl, self);
    }

    pub fn uncheck(self: *MenuItem) void {
        const t = self.tray orelse return;
        Impl.menuItemUncheck(&t.impl, self);
    }

    pub fn hide(self: *MenuItem) void {
        const t = self.tray orelse return;
        Impl.menuItemHide(&t.impl, self);
    }

    pub fn show(self: *MenuItem) void {
        const t = self.tray orelse return;
        Impl.menuItemShow(&t.impl, self);
    }

    pub fn remove(self: *MenuItem) void {
        const t = self.tray orelse return;
        Impl.menuItemRemove(&t.impl, self);
    }

    /// Add a sub-menu item under this item.
    pub fn addSubMenuItem(self: *MenuItem, title: []const u8, tooltip: []const u8) !*MenuItem {
        const t = self.tray orelse return error.TrayNotSet;
        return Impl.menuItemAddSubMenuItem(&t.impl, self, title, tooltip, false, false);
    }

    /// Add a separator after this item in the sub-menu.
    pub fn addSeparator(self: *MenuItem) !void {
        const t = self.tray orelse return;
        try Impl.menuItemAddSeparator(&t.impl, self);
    }

    /// Set the icon of this menu item from a file path.
    pub fn setIconFromFilePath(self: *MenuItem, path: []const u8) !void {
        const t = self.tray orelse return;
        try Impl.menuItemSetIconFromFilePath(&t.impl, self, path);
    }

    /// Register a click callback with a typed context pointer.
    /// The library wraps it internally — no `?*anyopaque` in user code.
    pub fn onClick(self: *MenuItem, comptime T: type, comptime cb: *const fn (*T) void, ctx: *T) void {
        const wrapper = struct {
            fn dispatch(c: ?*anyopaque) void {
                cb(@ptrCast(@alignCast(c.?)));
            }
        }.dispatch;
        self.callback = wrapper;
        self.ctx = @ptrCast(ctx);
    }

    /// Returns the parent item's id, or 0 for a top-level item.
    pub fn parentId(self: *const MenuItem) u32 {
        if (self.parent) |p| return p.id;
        return 0;
    }
};

// ── Tray ──────────────────────────────────────────────────────────────

/// The main system tray object.
/// Must be stack-declared by the caller and initialized via `init()`.
pub const Tray = struct {
    /// Platform-specific implementation state.
    impl: Impl.Context,

    /// Callbacks (opaque pointer, cast back to `*Tray` in handlers).
    allocator: std.mem.Allocator,
    on_ready: ?*const fn (*anyopaque) void,
    on_exit: ?*const fn (*anyopaque) void,

    /// Initialize the system tray.
    /// `self` must be stack-allocated; its address is stored for the window proc.
    pub fn init(self: *Tray, allocator: std.mem.Allocator, options: TrayOptions) !void {
        self.* = .{
            .impl = undefined,
            .allocator = allocator,
            .on_ready = options.on_ready,
            .on_exit = options.on_exit,
        };
        const opaque_self: *anyopaque = @ptrCast(self);
        try Impl.init(&self.impl, opaque_self, allocator);

        if (self.on_ready) |cb| cb(@ptrCast(self));
    }

    /// Deinitialize and free all resources.
    pub fn deinit(self: *Tray) void {
        Impl.deinit(&self.impl);
        if (self.on_exit) |cb| cb(@ptrCast(self));
    }

    /// Run the message pump (blocks until `quit()` is called).
    pub fn run(self: *Tray) void {
        Impl.run(&self.impl);
    }

    /// Quit the system tray.
    pub fn quit(self: *Tray) void {
        Impl.quit(&self.impl);
        if (self.on_exit) |cb| cb(@ptrCast(self));
    }

    /// Set the tray icon from raw `.ico` file bytes.
    pub fn setIcon(self: *Tray, icon_bytes: []const u8) !void {
        try Impl.setIcon(&self.impl, icon_bytes);
    }

    /// Set the tray icon from a `.ico` file path.
    pub fn setIconFromFilePath(self: *Tray, path: []const u8) !void {
        try Impl.setIconFromFilePath(&self.impl, path);
    }

    /// Set the tooltip text shown on hover.
    pub fn setTooltip(self: *Tray, tooltip: []const u8) !void {
        try Impl.setTooltip(&self.impl, tooltip);
    }

    /// Add a top-level menu item.
    pub fn addMenuItem(self: *Tray, title: []const u8, tooltip: []const u8) !*MenuItem {
        return Impl.addMenuItem(&self.impl, self, title, tooltip, false, false);
    }

    /// Add a checkable top-level menu item.
    pub fn addMenuItemCheckbox(self: *Tray, title: []const u8, tooltip: []const u8, checked: bool) !*MenuItem {
        return Impl.addMenuItem(&self.impl, self, title, tooltip, true, checked);
    }

    /// Add a separator bar to the top-level menu.
    pub fn addSeparator(self: *Tray) !void {
        try Impl.addSeparator(&self.impl);
    }

    /// Remove all menu items and rebuild from scratch.
    pub fn resetMenu(self: *Tray) void {
        Impl.resetMenu(&self.impl);
    }
};
