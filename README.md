# ZigTray

A cross-platform system tray library for [Zig](https://ziglang.org/).

Place an icon and menu in the OS notification area (system tray).

## Platform support

| Platform | Status        | Backend                                              |
| -------- | ------------- | ---------------------------------------------------- |
| Windows  | ✅ Working    | `Shell_NotifyIconW` + Win32 `HMENU`                  |
| macOS    | ✅ Working    | Cocoa `NSStatusBar` + `NSMenu` (via Objective-C)     |
| Linux    | ⚠️ Not tested | `libdbus-1` (StatusNotifierItem + DBusMenu protocol) |

## API

### Quick start

```zig
const std = @import("std");
const zigtray = @import("zigtray");

pub fn main() !void {
    var tray: zigtray.Tray = undefined;
    try tray.init(std.heap.page_allocator, .{
        .on_ready = onReady,
        .on_exit = onExit,
    });
    defer tray.deinit();
    tray.run(); // blocking message pump
}

fn onReady(tray: *zigtray.Tray) void {
    tray.setIcon(icon_bytes) catch {};
    tray.setTooltip("My App") catch {};

    const quit = tray.addMenuItem("Quit", "Quit the app") catch return;
    tray.addSeparator() catch {};
    const settings = tray.addMenuItem("Settings", "Open settings") catch return;

    quit.onClick(void, onQuit, null);
    settings.onClick(void, onSettings, null);
}

fn onQuit(_: *void) void { std.process.exit(0); }
fn onSettings(_: *void) void { /* open settings */ }

fn onExit(_: *zigtray.Tray) void { std.debug.print("Goodbye\n", .{}); }
```

### MenuItem methods

Each `MenuItem` holds a back-reference to its parent `Tray`, so you can
call methods directly on the item:

```zig
const item = tray.addMenuItem("Enable Feature", "Toggle it") catch return;

item.setTitle("Disable Feature");
item.check();
item.uncheck();
item.disable();
item.enable();
item.hide();
item.show();
item.remove();

const sub = item.addSubMenuItem("Sub Option", "A sub-menu item");
item.addSeparator() catch {};
```

### Callbacks

```zig
// Context struct for your app state
const AppCtx = struct {
    window: *MyWindow,
    counter: u32,
};

var app_ctx = AppCtx{ .window = &window, .counter = 0 };

// Typed callback — no anyopaque in user code
item.onClick(AppCtx, onItemClick, &app_ctx);

fn onItemClick(ctx: *AppCtx) void {
    ctx.counter += 1;
    ctx.window.setTitle("Clicked {d} times", .{ctx.counter});
}
```

## Build

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .zigtray = .{
        .url = "https://github.com/daniel-le97/zigtray/archive/refs/heads/main.tar.gz",
        .hash = "...",
    },
},
```

Then in `build.zig`:

```zig
const zigtray = b.dependency("zigtray", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zigtray", zigtray.module("zigtray"));
```

### macOS

The build system automatically compiles `src/systray/macos.m` with
`-fobjc-arc` and links `Cocoa.framework` when targeting macOS.

## Example

```bash
zig build run-example
```

## Acknowledgements

This library is a Zig port of [fyne-io/systray](https://github.com/fyne-io/systray),
a Go system tray library. The API design closely follows the Go original,
and the macOS Objective-C implementation (`src/systray/macos.m`) is adapted
from `systray/systray_darwin.m` under the terms of its license.

> [fyne-io/systray](https://github.com/fyne-io/systray) — Copyright (c) 2019 Fyne.io & Contributors
> Licensed under the Apache License, Version 2.0.
