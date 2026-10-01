#!/usr/bin/env python3
"""Dump EC register map via /dev/port (I/O ports 0x62/0x66).

Usage:
    sudo python3 ec-dump.py           # dump all readable registers
    sudo python3 ec-dump.py -w ADDR VAL  # write a value to a register (DANGEROUS)

The EC on this board is an ITE IT5570E at standard EC I/O ports:
    0x62 = data port
    0x66 = command port

To read register N: outb(N, 0x66); val = inb(0x62)
To write register N with value V: outb(N, 0x66); outb(V, 0x62)
"""

import argparse
import os
import struct
import sys

EC_DATA = 0x62
EC_CMD = 0x66


def io_open():
    """Open /dev/port for raw I/O access (requires root)."""
    try:
        return os.open("/dev/port", os.O_RDWR)
    except PermissionError:
        print("ERROR: need root to access /dev/port. Run with sudo.", file=sys.stderr)
        sys.exit(1)


def inb(fd, port):
    """Read one byte from I/O port."""
    os.lseek(fd, port, os.SEEK_SET)
    return os.read(fd, 1)[0]


def outb(fd, port, val):
    """Write one byte to I/O port."""
    os.lseek(fd, port, os.SEEK_SET)
    os.write(fd, struct.pack("B", val))


def ec_read(fd, reg):
    """Read EC register `reg`."""
    outb(fd, EC_CMD, reg)
    return inb(fd, EC_DATA)


def ec_write(fd, reg, val):
    """Write `val` to EC register `reg`. DANGEROUS — can brick the board."""
    outb(fd, EC_CMD, reg)
    outb(fd, EC_DATA, val)


def main():
    parser = argparse.ArgumentParser(description="Dump/write EC registers")
    parser.add_argument(
        "-w",
        "--write",
        nargs=2,
        metavar=("ADDR", "VAL"),
        help="Write VAL to register ADDR (DANGEROUS)",
    )
    parser.add_argument("-a", "--address", type=int, help="Read only this address")
    args = parser.parse_args()

    fd = io_open()

    if args.write:
        addr = int(args.write[0], 0)
        val = int(args.write[1], 0)
        if not 0 <= val <= 255:
            print("ERROR: value must be 0-255", file=sys.stderr)
            sys.exit(1)
        ec_write(fd, addr, val)
        print(
            "Wrote 0x%02X to register 0x%02X (read back: 0x%02X)"
            % (val, addr, ec_read(fd, addr))
        )
        print(
            "WARNING: if the board misbehaves, hard-reset (unplug power) may be needed."
        )
        os.close(fd)
        return

    if args.address is not None:
        reg = args.address
        if not 0 <= reg <= 255:
            print("ERROR: address must be 0-255", file=sys.stderr)
            sys.exit(1)
        print("0x%02X = 0x%02X (%d)" % (reg, ec_read(fd, reg), ec_read(fd, reg)))
        os.close(fd)
        return

    # Dump all 256 registers
    print("EC register dump (address = value)")
    known = {
        0x21: "fan1 speed high",
        0x22: "fan1 speed low",
        0x23: "fan1 mode",
        0x24: "fan2 speed high",
        0x25: "fan2 mode",
        0x26: "fan3 mode",
        0x31: "power mode",
        0x70: "temp",
    }
    for reg in range(256):
        try:
            val = ec_read(fd, reg)
            label = known.get(reg, "")
            print(
                "0x%02X = 0x%02X (%3d)%s"
                % (reg, val, val, ("  <- " + label) if label else "")
            )
        except Exception as e:
            print("0x%02X = READ ERROR: %s" % (reg, e))

    os.close(fd)


if __name__ == "__main__":
    main()
