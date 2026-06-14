//! Windows system tray implementation using Shell_NotifyIconW.
//! Uses a hidden message-only window to receive tray notifications.

const std = @import("std");
const MenuItem = @import("../systray.zig").MenuItem;

const HWND = std.os.windows.HWND;
const HINSTANCE = std.os.windows.HINSTANCE;
const HICON = std.os.windows.HICON;
const HMENU = std.os.windows.HMENU;
const DWORD = std.os.windows.DWORD;
const UINT = std.os.windows.UINT;
const BOOL = c_int;
const FALSE: BOOL = 0;
const LONG_PTR = isize;
const WPARAM = usize;
const LPARAM = isize;
const LRESULT = isize;
const LPVOID = *anyopaque;
const HANDLE = std.os.windows.HANDLE;

const GWLP_USERDATA: i32 = -21;
const WM_DESTROY: UINT = 0x0002;
const WM_COMMAND: UINT = 0x0111;
const WM_QUIT: UINT = 0x0012;
const WM_TRAY_CALLBACK = 0x8001;
const NIM_ADD: DWORD = 0;
const NIM_MODIFY: DWORD = 1;
const NIM_DELETE: DWORD = 2;
const NIF_MESSAGE: DWORD = 1;
const NIF_ICON: DWORD = 2;
const NIF_TIP: DWORD = 4;
const NIF_SHOWTIP: DWORD = 0x80;
const IMAGE_ICON: UINT = 1;
const LR_LOADFROMFILE: UINT = 0x0010;
const LR_DEFAULTSIZE: UINT = 0x0040;

const POINT = extern struct { x: i32, y: i32 };
const MSG = extern struct { hwnd: ?HWND, message: UINT, wParam: WPARAM, lParam: LPARAM, time: DWORD, pt: POINT };

const WNDCLASSEXW = extern struct {
    cbSize: UINT,
    style: UINT,
    lpfnWndProc: WNDPROC,
    cbClsExtra: i32,
    cbWndExtra: i32,
    hInstance: HINSTANCE,
    hIcon: ?HICON,
    hCursor: ?*opaque {},
    hbrBackground: ?*opaque {},
    lpszMenuName: ?[*:0]const u16,
    lpszClassName: [*:0]const u16,
    hIconSm: ?HICON,
};

const NOTIFYICONDATAW = extern struct {
    cbSize: DWORD,
    hWnd: HWND,
    uID: UINT,
    uFlags: DWORD,
    uCallbackMessage: UINT,
    hIcon: HICON,
    szTip: [128]u16,
    dwState: DWORD = 0,
    dwStateMask: DWORD = 0,
    szInfo: [256]u16 = [_]u16{0} ** 256,
    uVersionOrInfoTitle: extern union { uVersion: UINT, szInfoTitle: [64]u16 } = .{ .szInfoTitle = [_]u16{0} ** 64 },
    dwInfoFlags: DWORD = 0,
    guidItem: [16]u8 = [_]u8{0} ** 16,
    hBalloonIcon: HICON = undefined,
};

const WNDPROC = *const fn (HWND, UINT, WPARAM, LPARAM) callconv(.winapi) LRESULT;

extern "user32" fn CreateWindowExW(
    dwExStyle: DWORD,
    lpClassName: [*:0]const u16,
    lpWindowName: [*:0]const u16,
    dwStyle: DWORD,
    x: i32,
    y: i32,
    nWidth: i32,
    nHeight: i32,
    hWndParent: ?HWND,
    hMenu: ?HMENU,
    hInstance: HINSTANCE,
    lpParam: ?LPVOID,
) callconv(.winapi) ?HWND;
extern "user32" fn DefWindowProcW(hWnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT;
extern "user32" fn DestroyWindow(hWnd: HWND) callconv(.winapi) BOOL;
extern "user32" fn GetMessageW(lpMsg: *MSG, hWnd: ?HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT) callconv(.winapi) BOOL;
extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(.winapi) BOOL;
extern "user32" fn DispatchMessageW(lpMsg: *const MSG) callconv(.winapi) LRESULT;
extern "user32" fn PostThreadMessageW(idThread: DWORD, msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) BOOL;
extern "user32" fn RegisterClassExW(lpWndClass: *const WNDCLASSEXW) callconv(.winapi) u16;
extern "user32" fn LoadImageW(hInst: ?HINSTANCE, name: [*:0]const u16, type_: UINT, cx: i32, cy: i32, fuLoad: UINT) callconv(.winapi) ?HICON;
extern "user32" fn CreatePopupMenu() callconv(.winapi) ?HMENU;
extern "user32" fn TrackPopupMenu(hMenu: HMENU, uFlags: UINT, x: i32, y: i32, nReserved: i32, hWnd: HWND, prcRect: ?*anyopaque) callconv(.winapi) BOOL;
extern "user32" fn DestroyMenu(hMenu: HMENU) callconv(.winapi) BOOL;
extern "user32" fn AppendMenuW(hMenu: HMENU, uFlags: UINT, uIDNewItem: usize, lpNewItem: ?[*:0]const u16) callconv(.winapi) BOOL;
extern "user32" fn GetCursorPos(lpPoint: *POINT) callconv(.winapi) BOOL;
extern "user32" fn SetWindowLongPtrW(hWnd: HWND, nIndex: i32, dwNewLong: LONG_PTR) callconv(.winapi) LONG_PTR;
extern "user32" fn GetWindowLongPtrW(hWnd: HWND, nIndex: i32) callconv(.winapi) LONG_PTR;
extern "user32" fn SetForegroundWindow(hWnd: HWND) callconv(.winapi) BOOL;
extern "shell32" fn Shell_NotifyIconW(dwMessage: DWORD, lpData: *const NOTIFYICONDATAW) callconv(.winapi) BOOL;
extern "kernel32" fn GetModuleHandleW(lpModuleName: ?[*:0]const u16) callconv(.winapi) ?HINSTANCE;
extern "kernel32" fn GetCurrentThreadId() callconv(.winapi) DWORD;
extern "kernel32" fn GetTempPathW(nBufferLength: DWORD, lpBuffer: [*]u16) callconv(.winapi) DWORD;
extern "kernel32" fn CreateFileW(lpFileName: [*:0]const u16, dwDesiredAccess: DWORD, dwShareMode: DWORD, lpSecurityAttributes: ?*anyopaque, dwCreationDisposition: DWORD, dwFlagsAndAttributes: DWORD, hTemplateFile: ?HANDLE) callconv(.winapi) ?HANDLE;
extern "kernel32" fn WriteFile(hFile: HANDLE, lpBuffer: *const anyopaque, nNumberOfBytesToWrite: DWORD, lpNumberOfBytesWritten: ?*DWORD, lpOverlapped: ?*anyopaque) callconv(.winapi) BOOL;
extern "kernel32" fn CloseHandle(hObject: HANDLE) callconv(.winapi) BOOL;

// ── Context ───────────────────────────────────────────────────────────

pub const Context = struct {
    allocator: std.mem.Allocator,
    hwnd: HWND,
    nid: NOTIFYICONDATAW,
    icon_id: UINT,
    hmenu: ?HMENU,
    thread_id: DWORD,
    menu_items: std.ArrayListUnmanaged(*MenuItem),
    next_id: u32,
};

// ── Init / Deinit ─────────────────────────────────────────────────────

pub fn init(ctx: *Context, _: *anyopaque, allocator: std.mem.Allocator) !void {
    const hinstance = GetModuleHandleW(null) orelse return error.NoModuleHandle;

    const class_name: [:0]const u16 = comptime std.unicode.utf8ToUtf16LeStringLiteral("ZigTraySystray");
    if (RegisterClassExW(&.{
        .cbSize = @sizeOf(WNDCLASSEXW),
        .style = 0,
        .lpfnWndProc = trayWndProc,
        .cbClsExtra = 0,
        .cbWndExtra = @sizeOf(LONG_PTR),
        .hInstance = hinstance,
        .hIcon = null,
        .hCursor = null,
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = class_name,
        .hIconSm = null,
    }) == 0) return error.RegisterClassFailed;

    const hwnd = CreateWindowExW(0, class_name, class_name, 0, 0, 0, 0, 0, null, null, hinstance, null) orelse
        return error.CreateWindowFailed;

    ctx.* = .{
        .allocator = allocator,
        .hwnd = hwnd,
        .nid = undefined,
        .icon_id = 1,
        .hmenu = CreatePopupMenu(),
        .thread_id = GetCurrentThreadId(),
        .menu_items = .{ .items = &.{}, .capacity = 0 },
        .next_id = 1,
    };
    _ = SetWindowLongPtrW(hwnd, GWLP_USERDATA, @as(LONG_PTR, @intCast(@intFromPtr(ctx))));

    ctx.nid = .{
        .cbSize = @sizeOf(NOTIFYICONDATAW),
        .hWnd = hwnd,
        .uID = ctx.icon_id,
        .uFlags = NIF_MESSAGE | NIF_SHOWTIP,
        .uCallbackMessage = WM_TRAY_CALLBACK,
        .hIcon = undefined,
        .szTip = [_]u16{0} ** 128,
    };
    _ = Shell_NotifyIconW(NIM_ADD, &ctx.nid);
}

pub fn deinit(ctx: *Context) void {
    _ = Shell_NotifyIconW(NIM_DELETE, &.{
        .cbSize = @sizeOf(NOTIFYICONDATAW),
        .hWnd = ctx.hwnd,
        .uID = ctx.icon_id,
        .uFlags = 0,
        .uCallbackMessage = 0,
        .hIcon = undefined,
        .szTip = [_]u16{0} ** 128,
    });
    if (ctx.hmenu) |h| _ = DestroyMenu(h);
    ctx.menu_items.deinit(ctx.allocator);
    _ = DestroyWindow(ctx.hwnd);
}

// ── Run / Quit ────────────────────────────────────────────────────────

pub fn run(_: *Context) void {
    var msg: MSG = undefined;
    while (GetMessageW(&msg, null, 0, 0) != FALSE) {
        _ = TranslateMessage(&msg);
        _ = DispatchMessageW(&msg);
    }
}

pub fn quit(ctx: *Context) void {
    _ = PostThreadMessageW(ctx.thread_id, WM_QUIT, 0, 0);
}

// ── Icon ──────────────────────────────────────────────────────────────

pub fn setIcon(ctx: *Context, icon_bytes: []const u8) !void {
    if (icon_bytes.len < 22) return error.InvalidIconData;

    var tmp_wbuf: [260]u16 = undefined;
    const tmp_len = GetTempPathW(260, &tmp_wbuf);
    if (tmp_len == 0 or tmp_len > 240) return error.TempPathFailed;

    const suffix = [_]u16{ 'z', 'i', 'g', 't', 'r', 'a', 'y', '_', 'i', 'c', 'o', 'n', '.', 'i', 'c', 'o' };
    const total_wlen = tmp_len + suffix.len;
    @memcpy(tmp_wbuf[tmp_len..][0..suffix.len], &suffix);
    tmp_wbuf[total_wlen] = 0;
    const wide_path: [:0]u16 = tmp_wbuf[0..total_wlen :0];

    {
        const handle = CreateFileW(wide_path, 0x40000000, 0, null, 2, 0x80, null) orelse
            return error.IconTempFileFailed;
        defer _ = CloseHandle(handle);
        var written: DWORD = 0;
        if (WriteFile(handle, icon_bytes.ptr, @intCast(icon_bytes.len), &written, null) == FALSE)
            return error.IconTempFileFailed;
    }

    const hicon = LoadImageW(null, wide_path, IMAGE_ICON, 0, 0, LR_LOADFROMFILE | LR_DEFAULTSIZE) orelse
        return error.LoadIconFailed;

    ctx.nid.hIcon = hicon;
    ctx.nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_SHOWTIP;
    _ = Shell_NotifyIconW(NIM_MODIFY, &ctx.nid);
}

pub fn setIconFromFilePath(ctx: *Context, path: []const u8) !void {
    const path_w = try toUtf16(path);
    const hicon = LoadImageW(null, @ptrCast(path_w), IMAGE_ICON, 0, 0, LR_LOADFROMFILE | LR_DEFAULTSIZE) orelse
        return error.LoadIconFailed;
    ctx.nid.hIcon = hicon;
    ctx.nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_SHOWTIP;
    _ = Shell_NotifyIconW(NIM_MODIFY, &ctx.nid);
}

pub fn setTooltip(ctx: *Context, tooltip: []const u8) !void {
    const utf16 = try toUtf16(tooltip);
    const len = @min(utf16.len, 127);
    @memset(&ctx.nid.szTip, 0);
    @memcpy(ctx.nid.szTip[0..len], utf16[0..len]);
    ctx.nid.uFlags = NIF_TIP | NIF_MESSAGE | NIF_SHOWTIP;
    _ = Shell_NotifyIconW(NIM_MODIFY, &ctx.nid);
}

// ── Menu ──────────────────────────────────────────────────────────────

pub fn addMenuItem(ctx: *Context, tray: anytype, title: []const u8, _: []const u8, _: bool, checked: bool) !*MenuItem {
    const item = try ctx.allocator.create(MenuItem);
    item.* = .{
        .id = nextId(ctx),
        .title = try ctx.allocator.dupe(u8, title),
        .tooltip = "",
        .disabled = false,
        .checked = checked,
        .is_checkable = false,
        .parent = null,
        .callback = null,
        .ctx = null,
        .tray = @ptrCast(tray),
    };
    try ctx.menu_items.append(ctx.allocator, item);

    const hmenu = ctx.hmenu orelse return error.MenuNotCreated;
    var flags: UINT = 0;
    if (item.checked) flags |= 0x0008; // MF_CHECKED
    const title_w = try toUtf16(title);
    if (AppendMenuW(hmenu, flags, @as(usize, @intCast(item.id)), @ptrCast(title_w)) == FALSE)
        return error.AppendMenuFailed;
    return item;
}

pub fn addSeparator(ctx: *Context) !void {
    const hmenu = ctx.hmenu orelse return error.MenuNotCreated;
    if (AppendMenuW(hmenu, 0x0800, 0, @ptrFromInt(0)) == FALSE)
        return error.AppendMenuFailed;
}

pub fn resetMenu(ctx: *Context) void {
    if (ctx.hmenu) |h| _ = DestroyMenu(h);
    ctx.hmenu = CreatePopupMenu();
    ctx.menu_items.clearRetainingCapacity();
}

pub fn menuItemSetTitle(ctx: *Context, item: *MenuItem, title: []const u8) void {
    const new_title = ctx.allocator.dupe(u8, title) catch return;
    ctx.allocator.free(item.title);
    item.title = new_title;
}

pub fn menuItemSetTooltip(_: *Context, _: *MenuItem, _: []const u8) void {}
pub fn menuItemEnable(_: *Context, item: *MenuItem) void {
    item.disabled = false;
}
pub fn menuItemDisable(_: *Context, item: *MenuItem) void {
    item.disabled = true;
}
pub fn menuItemCheck(_: *Context, item: *MenuItem) void {
    item.checked = true;
}
pub fn menuItemUncheck(_: *Context, item: *MenuItem) void {
    item.checked = false;
}
pub fn menuItemHide(_: *Context, _: *MenuItem) void {}
pub fn menuItemShow(_: *Context, _: *MenuItem) void {}

pub fn menuItemRemove(ctx: *Context, item: *MenuItem) void {
    ctx.allocator.free(item.title);
    ctx.allocator.destroy(item);
}

pub fn menuItemAddSubMenuItem(ctx: *Context, parent: *MenuItem, title: []const u8, tooltip: []const u8, _: bool, checked: bool) !*MenuItem {
    const child = try ctx.allocator.create(MenuItem);
    child.* = .{
        .id = nextId(ctx),
        .title = try ctx.allocator.dupe(u8, title),
        .tooltip = try ctx.allocator.dupe(u8, tooltip),
        .disabled = false,
        .checked = checked,
        .is_checkable = false,
        .parent = parent,
        .callback = null,
        .ctx = null,
        .tray = parent.tray,
    };
    try ctx.menu_items.append(ctx.allocator, child);

    const hmenu = ctx.hmenu orelse return error.MenuNotCreated;
    var flags: UINT = 0;
    if (child.checked) flags |= 0x0008;
    const title_w = try toUtf16(title);
    if (AppendMenuW(hmenu, flags, @as(usize, @intCast(child.id)), @ptrCast(title_w)) == FALSE)
        return error.AppendMenuFailed;
    return child;
}

pub fn menuItemAddSeparator(_: *Context, _: *MenuItem) !void {}
pub fn menuItemSetIconFromFilePath(_: *Context, _: *MenuItem, _: []const u8) !void {}

// ── Helpers ───────────────────────────────────────────────────────────

fn toUtf16(s: []const u8) ![:0]u16 {
    return try std.unicode.utf8ToUtf16LeAllocZ(std.heap.page_allocator, s);
}

fn nextId(ctx: *Context) u32 {
    const id = ctx.next_id;
    ctx.next_id += 1;
    return id;
}

// ── Window procedure ──────────────────────────────────────────────────

fn trayWndProc(hwnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT {
    const ptr = GetWindowLongPtrW(hwnd, GWLP_USERDATA);
    if (ptr == 0) return DefWindowProcW(hwnd, msg, wParam, lParam);
    const ctx: *Context = @ptrFromInt(@as(usize, @intCast(ptr)));

    switch (msg) {
        WM_TRAY_CALLBACK => {
            if (lParam == 0x0205) { // WM_RBUTTONUP
                if (ctx.hmenu) |hmenu| {
                    var pt: POINT = undefined;
                    _ = GetCursorPos(&pt);
                    _ = SetForegroundWindow(hwnd);
                    _ = TrackPopupMenu(hmenu, 0, pt.x, pt.y, 0, hwnd, null);
                }
            }
            return 0;
        },
        WM_COMMAND => {
            const cmd_id = @as(UINT, @truncate(@as(usize, @intCast(wParam))));
            for (ctx.menu_items.items) |item| {
                if (item.id == cmd_id) {
                    if (item.callback) |cb| cb(item.ctx);
                    break;
                }
            }
            return 0;
        },
        WM_DESTROY => return 0,
        else => return DefWindowProcW(hwnd, msg, wParam, lParam),
    }
}
