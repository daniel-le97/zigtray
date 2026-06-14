//! ZigTray — A cross-platform system tray library for Zig.
//! Port of fyne-io/systray.
//!
//! ## Re-exports
//! All public types from the `systray` module are re-exported here
//! for convenience. Import via `@import("zigtray")`.

const std = @import("std");

pub const Tray = @import("systray.zig").Tray;
pub const MenuItem = @import("systray.zig").MenuItem;
pub const TrayOptions = @import("systray.zig").TrayOptions;
