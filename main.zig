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

const udp6_config_data = Udp6ConfigData {
    .accept_promiscuous = false,
    .accept_any_port = false,
    .allow_duplicate_port = false,
    .traffic_class = 0,
    .hop_limit = 255,
    .receive_timeout = 0,
    .transmit_timeout = 0,
    .station_address = [_]u8{ 0 } ** 16,
    .station_port = 1337,
    .remote_address = [_]u8{ 0 } ** 16,
    .remote_port = 1337,
};

const preferred_res_x: u32 = 1920;
const preferred_res_y: u32 = 1080;

var boot_services: *uefi.tables.BootServices = undefined;
var udp6proto: *Udp6Protocol = undefined;
var graphics: *GraphicsOutputProtocol = undefined;
var res_x: u32 = undefined;
var res_y: u32 = undefined;

fn puts(msg: []const u8) void {
    for (msg) |c| {
        _ = uefi.system_table.con_out.?.outputString(&[_]u16{ c, 0 });
    }
}

fn printf(buf: []u8, comptime format: []const u8, args: ...) void {
    puts(fmt.bufPrint(buf, format, args) catch unreachable);
}

extern fn draw(event: uefi.Event, context: ?*c_void) void {
    var udp6token = @ptrCast(*Udp6CompletionToken, @alignCast(8, context));
    const rxdata = udp6token.packet.RxData;
    if (rxdata.fragment_count == 1) {
        const fragment = rxdata.getFragments()[0];
        const buf = fragment.fragment_buffer[0..fragment.fragment_length];
        if (buf.len >= 13 and buf[0] == 'P' and buf[1] == 'X' and buf[2] == ' ') {
            var x: ?u32 = null;
            var y: ?u32 = null;
            var color = GraphicsOutputBltPixel{
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
                            if (x.? >= res_x) {
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
                _ = graphics.blt(@ptrCast([*]GraphicsOutputBltPixel, &color), GraphicsOutputBltOperation.BltVideoFill, 0, 0, x.?, y.?, 1, 1, 0);
            }
        }
    }

    _ = boot_services.signalEvent(rxdata.recycle_signal);
    _ = udp6proto.receive(udp6token);
}

pub fn main() void {
    boot_services = uefi.system_table.boot_services.?;
    var buf: [128]u8 = undefined;

    printf(buf[0..], "locating graphics returned {}\r\n", boot_services.locateProtocol(&GraphicsOutputProtocol.guid, null, @ptrCast(*?*c_void, &graphics)));
    var i: u32 = 0;
    while (i < graphics.mode.max_mode) : (i += 1) {
        var info: *GraphicsOutputModeInformation = undefined;
        var size: usize = undefined;
        _ = graphics.queryMode(i, &size, &info);
        printf(buf[0..], "found resolution {}: {}x{}\r\n", i, info.horizontal_resolution, info.vertical_resolution);
        if (info.horizontal_resolution == preferred_res_x and info.vertical_resolution == preferred_res_y) {
            _ = graphics.setMode(i);
            puts("set preferred resolution\r\n");
            break;
        }
    }
    res_x = graphics.mode.info.horizontal_resolution;
    res_y = graphics.mode.info.vertical_resolution;
    printf(buf[0..], "resolution is {}x{}\r\n", res_x, res_y);

    var udp6sbp: *Udp6ServiceBindingProtocol = undefined;
    printf(buf[0..], "locating udp6sbp returned {}\r\n", boot_services.locateProtocol(&Udp6ServiceBindingProtocol.guid, null, @ptrCast(*?*c_void, &udp6sbp)));
    var udp6handle: uefi.Handle = null;
    printf(buf[0..], "createChild returned {}\r\n", udp6sbp.createChild(&udp6handle));
    printf(buf[0..], "locating udp6 returned {}\r\n", boot_services.handleProtocol(udp6handle, &Udp6Protocol.guid, @ptrCast(*?*c_void, &udp6proto)));

    printf(buf[0..], "configure(null) = {}\r\n", udp6proto.configure(null));
    printf(buf[0..], "configure(&udp6_config_data) = {}\r\n", udp6proto.configure(&udp6_config_data));

    var udp6token: Udp6CompletionToken = undefined;
    _ = boot_services.createEvent(uefi.tables.BootServices.event_notify_signal, uefi.tables.BootServices.tpl_callback, draw, &udp6token, &udp6token.event);
    _ = udp6proto.receive(&udp6token);

    _ = boot_services.stall(30 * 1000 * 1000);
    uefi.system_table.runtime_services.resetSystem(uefi.tables.ResetType.ResetCold, 0, 0, null);
}
