# GMKtec EVO-X2 RGB LED Control — Information Request

**Date:** 2026-10-01
**Requester:** Daevid Vincent (EVO-X2 owner)
**Purpose:** Enable RGB LED control on Linux via the open-source `ec-su_axb35-linux` driver (cmetz/ec-su_axb35-linux)

## Background

I own a **GMKtec NucBox EVO-X2** (Sixunited AXB35-02 board, AMD Ryzen AI Max+ 395 "Strix Halo") running Kubuntu 26.04. I use the open-source Linux EC driver [cmetz/ec-su_axb35-linux](https://github.com/cmetz/ec-su_axb35-linux) which provides fan control, temperature readout, and power mode switching on Linux.

The EVO-X2 has a **front touch button** that cycles through RGB LED effects (13 modes on Windows, including "off"). I want to control these LED modes from software (Linux) — the same way Windows does — so I can build a desktop applet that lets me change the RGB mode, schedule off-hours for nighttime, etc.

## The Problem

After extensive investigation (including a detailed analysis posted as [issue #27](https://github.com/cmetz/ec-su_axb35-linux/issues/27) on the driver's GitHub), it appears the RGB LED is **NOT controlled by the ITE IT5570E EC** chip. Key findings:

1. **RGB works when the PC is completely powered off** (on the 5V standby rail) — the EC is not active in this state.
2. **No EC register changes** correlate with RGB button presses (full dump of ACPI EC space 0x00-0xFF and EC RAM 0x0000-0x1FFF via I2EC showed no changes).
3. **No USB HID device** appears for LED control (`lsusb` shows only keyboard + WiFi).
4. **No LED/RGB references** in the ACPI DSDT tables.
5. The RGB LED strip appears to be driven by a **separate standalone microcontroller** with no known software interface from the host.

## What We Need

To implement RGB LED control on Linux, we need one of the following from GMKtec/Sixunited:

### Option A: The LED Microcontroller Details (Preferred)

Please provide:

1. **LED microcontroller model/chip** — what IC drives the RGB LED strip? (e.g., WS2812, SK6812, an MCU like an STM32/CH552, etc.)
2. **Communication interface** — how does the host system (EC or CPU) communicate with the LED microcontroller?
   - Is it connected to the EC via I2C, SPI, UART, or a dedicated GPIO line?
   - Is it connected directly to the CPU (e.g., via a dedicated GPIO pin, or an I2C/SPI bus that the CPU can access)?
   - Does it have its own independent I2C/SPI address on a system bus?
3. **Command protocol** — what commands/bytes are sent to change the LED mode? (e.g., mode 0 = off, mode 1 = static red, mode 2 = rainbow cycle, etc.)
4. **Pinout/schematic** — which pins on which connector does the LED controller connect to on the AXB35-02 board?
5. **Does the front touch button** send a signal to the EC, to the CPU, or directly to the LED microcontroller?

### Option B: Windows Driver/Utility Analysis

If the above details are not readily available:

1. **Which Windows utility** controls the RGB LED? (Is it a GMKtec proprietary app, a Sixunited tool, or a generic RGB control app?)
2. **Which Windows driver** does that utility use? (Can you provide the `.sys` driver file or its source?)
3. **Does the utility communicate** via a kernel driver, a user-mode service, USB HID, or something else?
4. Can you provide a **packet capture** or **API trace** of the utility changing the LED mode (e.g., using Wireshark for USB traffic, or Process Monitor for driver calls)?

### Option C: Firmware/EC Source Access

1. **Is the EC firmware source** available from Sixunited or ITE?
2. Does the EC firmware contain any code related to the RGB LED (even if it's just passing through commands from the front button)?
3. Can Sixunited provide an **EC register map** that includes any LED-related registers, even if they're unused by the current driver?

## Technical Context (What We Already Know)

For reference, here's what the existing Linux driver controls via the EC:

| Function | EC Register | Access |
|----------|-------------|--------|
| Power mode (quiet/balanced/performance) | 0x31 | Read/Write |
| Fan 1 mode | 0x21 | Read/Write |
| Fan 2 mode | 0x23 | Read/Write |
| Fan 3 mode | 0x25 | Read/Write |
| Fan 1 speed | 0x35 (high) / 0x36 (low) | Read |
| Fan 2 speed | 0x37 (high) / 0x38 (low) | Read |
| Fan 3 speed | 0x28 (high) / 0x29 (low) | Read |
| CPU temperature | 0x70 | Read |

The EC is accessed via standard ACPI I/O ports (0x62 data / 0x66 command) or directly via I2EC PNP ports (0x4E/0x4F).

The front touch button for RGB is physically separate from the power mode button. On Windows, pressing it cycles through 13 LED modes. We need to understand what that button does electrically and how the mode change is propagated.

## Why This Matters

The open-source `ec-su_axb35-linux` driver is used by owners of multiple AXB35-02-based machines (GMKtec EVO-X2, Bosgame M5, FEVM FA-EX9, Peladn YO1, NIMO AI MiniPC, Corsair AI Workstation 300). RGB LED support would benefit all of these users on Linux.

Without this information, the RGB LED remains inaccessible on Linux, and users are forced to use Windows or live with the default LED behavior.

## Contact

Please respond to: daevid@daevid.com
GitHub: [@DAE51D](https://github.com/DAE51D)
Driver repo: [cmetz/ec-su_axb35-linux](https://github.com/cmetz/ec-su_axb35-linux) (driver author: loom@mopper.de)

Any information you can provide — even partial — would be greatly appreciated. If you can connect us with the Sixunited engineering team that designed the AXB35-02 board, that would be ideal.
