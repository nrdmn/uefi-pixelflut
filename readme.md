# UEFI Pixelflut Server

## Disclaimer
This is a proof of concept. It's very slow and it currently requires my fork of zig.

## Usage
1. Edit main.zig and set the preferred screen resolution.
1. Compile with `zig build` and copy efi/boot/bootx64.efi to a FAT formatted device.
1. Run on a network that responds to router solicitations
1. Send UDPv6 packets on port 1337 to the device's autogenerated IPv6 address.
