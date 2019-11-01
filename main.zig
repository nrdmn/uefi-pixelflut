const std = @import("std");
const uefi = std.os.uefi;
const fmt = std.fmt;
const Udp6ServiceBindingProtocol = uefi.protocols.Udp6ServiceBindingProtocol;
const Udp6Protocol = uefi.protocols.Udp6Protocol;
const Udp6CompletionToken = uefi.protocols.Udp6CompletionToken;
const Udp6ConfigData = uefi.protocols.Udp6ConfigData;
const GraphicsOutputProtocol = uefi.protocols.GraphicsOutputProtocol;
const GraphicsOutputBltPixel = uefi.protocols.GraphicsOutputBltPixel;
const GraphicsOutputBltOperation = uefi.protocols.GraphicsOutputBltOperation;
const GraphicsOutputModeInformation = uefi.protocols.GraphicsOutputModeInformation;

const udp6_config_data = Udp6ConfigData{
    .accept_promiscuous = false,
    .accept_any_port = false,
    .allow_duplicate_port = false,
    .traffic_class = 0,
    .hop_limit = 255,
    .receive_timeout = 0,
    .transmit_timeout = 0,
    .station_address = [_]u8{0} ** 16,
    .station_port = 1337,
    .remote_address = [_]u8{0} ** 16,
    .remote_port = 0,
};

const preferred_res_x: u32 = 1024;
const preferred_res_y: u32 = 768;

const Pixel = extern struct {
    blue: u8,
    green: u8,
    red: u8,
    pad: u8 = undefined,
};

var boot_services: *uefi.tables.BootServices = undefined;
var udp6proto: *Udp6Protocol = undefined;
var graphics: *GraphicsOutputProtocol = undefined;
var res_x: u32 = undefined;
var res_y: u32 = undefined;
var pps: u32 = 0;

extern fn draw(event: uefi.Event, context: ?*c_void) void {
    var udp6token = @ptrCast(*Udp6CompletionToken, @alignCast(8, context));
    const rxdata = udp6token.packet.RxData;
    if (rxdata.fragment_count == 1) {
        const fragment = rxdata.getFragments()[0];
        const buf = fragment.fragment_buffer[0..fragment.fragment_length];
        if (buf.len >= 13 and buf[0] == 'P' and buf[1] == 'X' and buf[2] == ' ') {
            var x: ?u32 = null;
            var y: ?u32 = null;
            var color = Pixel{
                .red = undefined,
                .green = undefined,
                .blue = undefined,
            };
            var state: enum {
                Width,
                Height,
                Red1,
                Red2,
                Green1,
                Green2,
                Blue1,
                Blue2,
                Error,
                Done,
            } = .Width;
            for (buf[3..]) |c| {
                switch (state) {
                    .Width => switch (c) {
                        ' ' => if (x != null) {
                            state = .Height;
                        } else {
                            state = .Error;
                        },
                        '0'...'9' => {
                            x = (x orelse 0) * 10 + c - '0';
                            if (x.? >= res_x - 20) {
                                state = .Error;
                            }
                        },
                        else => state = .Error,
                    },
                    .Height => switch (c) {
                        ' ' => if (y != null) {
                            state = .Red1;
                        } else {
                            state = .Error;
                        },
                        '0'...'9' => {
                            y = (y orelse 0) * 10 + c - '0';
                            if (y.? >= res_y) {
                                state = .Error;
                            }
                        },
                        else => state = .Error,
                    },
                    .Red1 => switch (c) {
                        '0'...'9' => {
                            color.red = (c - '0') * 16;
                            state = .Red2;
                        },
                        'a'...'f' => {
                            color.red = (c - 'a' + 10) * 16;
                            state = .Red2;
                        },
                        'A'...'F' => {
                            color.red = (c - 'A' + 10) * 16;
                            state = .Red2;
                        },
                        else => state = .Error,
                    },
                    .Red2 => switch (c) {
                        '0'...'9' => {
                            color.red += c - '0';
                            state = .Green1;
                        },
                        'a'...'f' => {
                            color.red += c - 'a' + 10;
                            state = .Green1;
                        },
                        'A'...'F' => {
                            color.red += c - 'A' + 10;
                            state = .Green1;
                        },
                        else => state = .Error,
                    },
                    .Green1 => switch (c) {
                        '0'...'9' => {
                            color.green = (c - '0') * 16;
                            state = .Green2;
                        },
                        'a'...'f' => {
                            color.green = (c - 'a' + 10) * 16;
                            state = .Green2;
                        },
                        'A'...'F' => {
                            color.green = (c - 'A' + 10) * 16;
                            state = .Green2;
                        },
                        else => state = .Error,
                    },
                    .Green2 => switch (c) {
                        '0'...'9' => {
                            color.green += c - '0';
                            state = .Blue1;
                        },
                        'a'...'f' => {
                            color.green += c - 'a' + 10;
                            state = .Blue1;
                        },
                        'A'...'F' => {
                            color.green += c - 'A' + 10;
                            state = .Blue1;
                        },
                        else => state = .Error,
                    },
                    .Blue1 => switch (c) {
                        '0'...'9' => {
                            color.blue = (c - '0') * 16;
                            state = .Blue2;
                        },
                        'a'...'f' => {
                            color.blue = (c - 'a' + 10) * 16;
                            state = .Blue2;
                        },
                        'A'...'F' => {
                            color.blue = (c - 'A' + 10) * 16;
                            state = .Blue2;
                        },
                        else => state = .Error,
                    },
                    .Blue2 => switch (c) {
                        '0'...'9' => {
                            color.blue += c - '0';
                            state = .Done;
                        },
                        'a'...'f' => {
                            color.blue += c - 'a' + 10;
                            state = .Done;
                        },
                        'A'...'F' => {
                            color.blue += c - 'A' + 10;
                            state = .Done;
                        },
                        else => state = .Error,
                    },
                    .Done => switch (c) {
                        '\n' => break,
                        else => state = .Error,
                    },
                    .Error => break,
                }
            }

            if (state == .Done) {
                @intToPtr([*]Pixel, graphics.mode.frame_buffer_base)[x.? + y.? * res_x] = color;
                pps += 1;
            }
        }
    }

    _ = boot_services.signalEvent(rxdata.recycle_signal);
    _ = udp6proto.receive(udp6token);
}

const freetype = @cImport({
    @cInclude("glue.c");
});

const face_ttf = @embedFile("comicneue/Web/ComicNeue-Bold.ttf");
var ft_handle: freetype.FT_Library = undefined;
var face: freetype.FT_Face = undefined;

export fn ft_smalloc(size: usize) [*]u8 {
    var buf: [*]u8 align(8) = undefined;
    _ = boot_services.allocatePool(uefi.tables.MemoryType.BootServicesData, size, &buf);
    return buf;
}

export fn ft_sfree(buf: [*]align(8) u8) void {
    _ = boot_services.freePool(buf);
}

fn write(msg: []u8, pos_x: usize, pos_y: usize) void {
    var offset_x = @intCast(c_int, pos_x);
    var offset_y = @intCast(c_int, pos_y);
    for (msg) |c| {
        const index = freetype.FT_Get_Char_Index(face, c);
        _ = freetype.FT_Load_Glyph(face, index, freetype.FT_LOAD_DEFAULT);
        _ = freetype.FT_Render_Glyph(face.*.glyph, freetype.FT_RENDER_MODE_NORMAL);
        const glyph = face.*.glyph.*;
        const bitmap = glyph.bitmap;
        var x: c_int = 0;
        var y: c_int = 0;
        while (y < @intCast(c_int, bitmap.rows)) : (y += 1) {
            while (x < @intCast(c_int, bitmap.width)) : (x += 1) {
                const p = bitmap.buffer[@intCast(usize, x + y * bitmap.pitch)];
                @intToPtr([*]Pixel, graphics.mode.frame_buffer_base)[@intCast(usize, offset_x + x) + @intCast(usize, offset_y + y - glyph.bitmap_top) * res_x] = Pixel{
                    .red = p,
                    .green = p,
                    .blue = p,
                };
            }
            x = 0;
        }
        offset_x += glyph.advance.x >> 6;
        offset_y += glyph.advance.y >> 6;
    }
}

extern fn update_pps(event: uefi.Event, _: ?*c_void) void {
    var black = [_]GraphicsOutputBltPixel{GraphicsOutputBltPixel{ .red = 0, .green = 0, .blue = 0 }};
    _ = graphics.blt(&black, GraphicsOutputBltOperation.BltVideoFill, 0, 0, res_x - 1 - 200, res_y - 1 - 20, 200, 20, 0);
    var buf: [30]u8 = undefined;
    write(fmt.bufPrint(buf[0..], "{} px/s", pps) catch unreachable, res_x - 1 - 200, res_y - 1 - 5);
    pps = 0;
}

pub fn main() void {
    boot_services = uefi.system_table.boot_services.?;

    _ = boot_services.locateProtocol(&GraphicsOutputProtocol.guid, null, @ptrCast(*?*c_void, &graphics));
    var i: u32 = 0;
    while (i < graphics.mode.max_mode) : (i += 1) {
        var info: *GraphicsOutputModeInformation = undefined;
        var size: usize = undefined;
        _ = graphics.queryMode(i, &size, &info);
        if (info.horizontal_resolution == preferred_res_x and info.vertical_resolution == preferred_res_y) {
            _ = graphics.setMode(i);
            break;
        }
    }
    res_x = graphics.mode.info.horizontal_resolution;
    res_y = graphics.mode.info.vertical_resolution;

    _ = freetype.FT_Init_FreeType(&ft_handle);
    _ = freetype.FT_New_Memory_Face(ft_handle, @ptrCast([*c]const u8, &face_ttf), face_ttf.len, 0, &face);
    _ = freetype.FT_Set_Char_Size(face, 0, 12 * 64, 100, 100);
    var buf: [128]u8 = undefined;
    write(fmt.bufPrint(buf[0..], "udp://pixelflut.nirf.de:1337 | {}x{}", res_x, res_y - 20) catch unreachable, 20, res_y - 1 - 5);

    var pps_event: uefi.Event = undefined;
    _ = boot_services.createEvent(uefi.tables.BootServices.event_timer | uefi.tables.BootServices.event_notify_signal, uefi.tables.BootServices.tpl_notify, update_pps, null, &pps_event);
    _ = boot_services.setTimer(pps_event, uefi.tables.TimerDelay.TimerPeriodic, 1000 * 1000 * 10);

    var udp6sbp: *Udp6ServiceBindingProtocol = undefined;
    _ = boot_services.locateProtocol(&Udp6ServiceBindingProtocol.guid, null, @ptrCast(*?*c_void, &udp6sbp));
    var udp6handle: uefi.Handle = null;
    _ = udp6sbp.createChild(&udp6handle);
    _ = boot_services.handleProtocol(udp6handle, &Udp6Protocol.guid, @ptrCast(*?*c_void, &udp6proto));

    _ = udp6proto.configure(null);
    _ = udp6proto.configure(&udp6_config_data);

    var udp6token: Udp6CompletionToken = undefined;
    _ = boot_services.createEvent(uefi.tables.BootServices.event_notify_signal, uefi.tables.BootServices.tpl_callback, draw, &udp6token, &udp6token.event);
    _ = udp6proto.receive(&udp6token);

    _ = boot_services.stall(30 * 1000 * 1000);

    _ = udp6sbp.destroyChild(udp6handle);
    uefi.system_table.runtime_services.resetSystem(uefi.tables.ResetType.ResetCold, 0, 0, null);
}
