//! Common types shared across all platforms.

const std = @import("std");

/// Options passed to `Tray.init`.
/// Callbacks receive an opaque pointer to the Tray (cast internally).
pub const TrayOptions = struct {
    on_ready: ?*const fn (*anyopaque) void = null,
    on_exit: ?*const fn (*anyopaque) void = null,
};
