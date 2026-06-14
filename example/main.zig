//! ZigTray example — port of fyne-io/systray/example/main.go.
//!
//! Build: `zig build example`
//! Run:   `zig build run-example`

const std = @import("std");
const zigtray = @import("zigtray");
const icon = @import("icon");

const Tray = zigtray.Tray;

// ── Context ────────────────────────────────────────────────────────────

const Ctx = struct {
    tray: *Tray,
    m_quit: *zigtray.MenuItem,
    m_change: *zigtray.MenuItem,
    m_checked: *zigtray.MenuItem,
    m_enabled: *zigtray.MenuItem,
    m_toggle: *zigtray.MenuItem,
    submenu_bottom: *zigtray.MenuItem,
    submenu_bottom2: *zigtray.MenuItem,
    shown: bool,
};

// ── Main ───────────────────────────────────────────────────────────────

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var tray: Tray = undefined;
    try tray.init(allocator, .{ .on_ready = onReady, .on_exit = onExit });
    defer tray.deinit();
    tray.run();
    std.debug.print("Finished quitting\n", .{});
}

fn onExit(_: *anyopaque) void {
    std.debug.print("Exit at (time unavailable)\n", .{});
}

// ── onReady ────────────────────────────────────────────────────────────

fn onReady(raw: *anyopaque) void {
    const tray: *Tray = @ptrCast(@alignCast(raw));

    tray.setIcon(icon.data) catch {};
    tray.setTooltip("Pretty awesome棒棒嗒") catch {};

    const m_quit = tray.addMenuItem("Quit", "Quit the whole app") catch return;
    tray.addSeparator() catch {};

    const m_change = tray.addMenuItem("Change Me", "Change Me") catch return;
    const m_checked = tray.addMenuItemCheckbox("Checked", "Check Me", true) catch return;
    const m_enabled = tray.addMenuItem("Enabled", "Enabled") catch return;
    _ = tray.addMenuItem("Ignored", "Ignored") catch return;

    const submenu_top = tray.addMenuItem("SubMenuTop", "SubMenu Test (top)") catch return;
    const submenu_middle = submenu_top.addSubMenuItem("SubMenuMiddle", "SubMenu Test (middle)") catch return;
    const submenu_bottom = submenu_middle.addSubMenuItem("SubMenuBottom - Toggle Panic!", "SubMenu Test (bottom) - Hide/Show Panic!") catch return;
    submenu_middle.addSeparator() catch {};
    const submenu_bottom2 = submenu_middle.addSubMenuItem("SubMenuBottom - Panic!", "SubMenu Test (bottom)") catch return;

    tray.addSeparator() catch {};
    const m_toggle = tray.addMenuItem("Toggle", "Toggle some menu items") catch return;
    const m_reset = tray.addMenuItem("Reset", "Reset all items") catch return;

    // Allocate Ctx on the heap so it outlives onReady.
    const ctx = tray.allocator.create(Ctx) catch return;
    ctx.* = .{
        .tray = tray,
        .m_quit = m_quit,
        .m_change = m_change,
        .m_checked = m_checked,
        .m_enabled = m_enabled,
        .m_toggle = m_toggle,
        .submenu_bottom = submenu_bottom,
        .submenu_bottom2 = submenu_bottom2,
        .shown = true,
    };

    // ── Wire callbacks — no anyopaque, no @ptrCast ────────────────────

    m_quit.onClick(Ctx, onQuit, ctx);
    m_change.onClick(Ctx, onChange, ctx);
    m_checked.onClick(Ctx, onChecked, ctx);
    m_enabled.onClick(Ctx, onEnabled, ctx);
    submenu_bottom2.onClick(Ctx, onPanic, ctx);
    submenu_bottom.onClick(Ctx, onTogglePanic, ctx);
    m_toggle.onClick(Ctx, onTogglePanic, ctx);
    m_reset.onClick(Ctx, onReset, ctx);
}

// ── Callbacks — typed! ─────────────────────────────────────────────────

fn onQuit(cx: *Ctx) void {
    std.debug.print("Requesting quit\n", .{});
    cx.tray.quit();
}

fn onChange(cx: *Ctx) void {
    cx.m_change.setTitle("I've Changed");
}

fn onChecked(cx: *Ctx) void {
    if (cx.m_checked.checked) {
        cx.m_checked.uncheck();
        cx.m_checked.setTitle("Unchecked");
    } else {
        cx.m_checked.check();
        cx.m_checked.setTitle("Checked");
    }
}

fn onEnabled(cx: *Ctx) void {
    cx.m_enabled.setTitle("Disabled");
    cx.m_enabled.disable();
}

fn onPanic(_: *Ctx) void {
    std.debug.print("panic button pressed (Zig doesn't panic)\n", .{});
}

fn onTogglePanic(cx: *Ctx) void {
    if (cx.shown) {
        cx.submenu_bottom.check();
        cx.submenu_bottom2.hide();
        cx.m_enabled.hide();
        cx.shown = false;
    } else {
        cx.submenu_bottom.uncheck();
        cx.submenu_bottom2.show();
        cx.m_enabled.show();
        cx.shown = true;
    }
}

fn onReset(cx: *Ctx) void {
    cx.tray.resetMenu();
    const m = cx.tray.addMenuItem("Quit", "Quit the whole app") catch return;
    m.onClick(Ctx, onQuit, cx);
}
