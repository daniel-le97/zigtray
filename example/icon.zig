//! Embedded 16×16 32bpp .ico file for the example app.
//! Blue background with yellow/orange vertical bar (matching the
//! fyne-io/systray example screenshot).  Generated at comptime.

const W = 16;
const H = 16;

const total_size = 6 + 16 + 40 + (W * H * 4);

/// Complete .ico file bytes.
pub const data: []const u8 = &ico_bytes;

const ico_bytes: [total_size]u8 = result: {
    var pixels: [W * H * 4]u8 = undefined;

    var row: usize = 0;
    while (row < H) : (row += 1) {
        var col: usize = 0;
        while (col < W) : (col += 1) {
            const idx = (row * W + col) * 4;
            if (col >= 5 and col <= 10) {
                // Yellow-orange vertical bar
                pixels[idx + 0] = 50;
                pixels[idx + 1] = 200;
                pixels[idx + 2] = 255;
                pixels[idx + 3] = 255;
            } else {
                // Blue background
                pixels[idx + 0] = 200;
                pixels[idx + 1] = 0;
                pixels[idx + 2] = 0;
                pixels[idx + 3] = 255;
            }
        }
    }

    // ICO header (6 bytes)
    const header = [_]u8{ 0, 0, 1, 0, 1, 0 };

    // Directory entry (16 bytes)
    const payload_size: u32 = 40 + pixels.len;
    const offset: u32 = 6 + 16;
    const dir = [_]u8{
        W,                       H,                            0,                             0,                             1,                 0,                      32,                      0,
        @truncate(payload_size), @truncate(payload_size >> 8), @truncate(payload_size >> 16), @truncate(payload_size >> 24), @truncate(offset), @truncate(offset >> 8), @truncate(offset >> 16), @truncate(offset >> 24),
    };

    // BITMAPINFOHEADER (40 bytes)
    const bih = [_]u8{
        40,    0, 0,  0,
        W,     0, 0,  0,
        H * 2, 0, 0,  0,
        1,     0, 32, 0,
        0,     0, 0,  0,
        0,     0, 0,  0,
        0,     0, 0,  0,
        0,     0, 0,  0,
        0,     0, 0,  0,
        0,     0, 0,  0,
    };

    // Assemble
    var buf: [total_size]u8 = undefined;
    @memcpy(buf[0..6], &header);
    @memcpy(buf[6..22], &dir);
    @memcpy(buf[22..62], &bih);
    @memcpy(buf[62..], &pixels);
    break :result buf;
};
