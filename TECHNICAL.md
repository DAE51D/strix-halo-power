# Technical notes

For anyone reviewing the design or the
[`ec-su_axb35` PR #33](https://github.com/cmetz/ec-su_axb35-linux/pull/33).

## Architecture

Five layers, each independently restartable, all surviving reboot:

1. **Kernel module `ec_su_axb35`** (submodule `driver/`). Out-of-tree, built
   per-kernel via DKMS. Exposes `/sys/class/ec_su_axb35/apu/power_mode`
   (RW, root-only) and, with the `input_button` param, the front power-mode
   button as a `KEY_POWER` input device. The sysfs file is the single source
   of truth for the mode.

2. **Privilege helper `pmode-write` + sudoers.** The sysfs file is root-only.
   Rather than a setuid binary or a polkit rule, a narrow sudoers entry lets
   the `ec_su_axb35` group run exactly one command, no shell, no wildcards:
   `/usr/local/bin/pmode-write <mode>`.

3. **D-Bus backend `com.evox2.powermode.backend`** (PyGObject). The single
   validated writer. It polls sysfs every 500 ms, debounces external changes
   (front button / CLI) by 300 ms, and emits `ModeChanged(newMode, source)`.
   Writes try a direct sysfs write first, falling back to the sudo helper on
   `PermissionError`, then read back to confirm (and warn if the EC clamped
   the value).

4. **D-Bus bridge `pmode-bridge`** (C++/Qt). Owns `com.evox2.powermode` and
   forwards to the backend. Exists **only** because of the Plasma 6.6 D-Bus
   limitation below. It also polls the backend's `Mode` every 150 ms and
   re-emits `ModeChanged` on change, so the widget tracks the button path
   promptly.

5. **Plasma applet `org.kde.pmode`**. Left-click cycles, right-click picks a
   mode. The icon is bound to the current mode; a 2 s poll + `ModeChanged`
   `SignalWatcher` keep it current.

## Why the C++ bridge exists (the Plasma 6.6 D-Bus limitation)

This is the non-obvious part. On Plasma 6.6.6 (KDE Frameworks 6), the
long-lived `plasmashell` process **cannot reach a PyGObject-registered D-Bus
object**, even though the object is correctly registered on the session bus:

- `PlasmaDBus.SessionBus.asyncCall` to *any* PyGObject service (including a
  trivial standalone test service registered with the same
  `Gio.DBusConnection.register_object`) fails with
  `org.freedesktop.DBus.Error.UnknownMethod: Object does not exist at path …`.
- The **same** Plasma connection reaches C++/Qt services fine
  (`org.freedesktop.Notifications.GetCapabilities` succeeds).
- `gdbus` (GDBus) reaches the PyGObject service fine.
- Both Qt6 and GDBus link the same `libdbus-1.so.3`, so it is not a lib
  difference.

It is a Plasma-long-lived-Qt-connection ↔ PyGObject-peer visibility
incompatibility, not a bug in the service, and a reboot does not fix it.

A **second** Plasma 6.6 bug compounds it: `PlasmaDBus.dbusMessage.arguments`
is **always dropped** in this build. A string argument (plain,
`new PlasmaDBus.string`, or `new PlasmaDBus.variant` with `signature:"s"`)
arrives empty, so a method requiring an `(s)` arg reports
`No such method … (signature '')`. **No-arg method calls do work.**

The bridge resolves both:

- It is a C++/Qt service, so Plasma *can* reach it.
- It exposes **no-arg** `SetQuiet()` / `SetBalanced()` / `SetPerformance()`
  (plus `GetMode()`, `Cycle()`, `Ping()`), so the widget never sends an
  argument that Plasma would drop.
- `Set*` use fire-and-forget `asyncCall` to the backend so the bridge replies
  in ~6 ms. (A blocking call stalled the reply ~10 s, making rapid clicks
  queue and the icon look frozen.)

The bridge's `ModeChanged` re-emit uses a 150 ms poll of the backend's `Mode`
property rather than a D-Bus signal subscription, because
`QDBusConnection::connect()` (the only signal-subscription API in this Qt
build) is unreliable — it mis-parses the slot name (strips the first char) and
fails to connect. Polling is robust and the 150 ms cadence is imperceptible.

**If Plasma/Qt fixes the PyGObject visibility or the argument-dropping bug**,
the bridge can be deleted and the applet can call the backend directly — the
backend's D-Bus API is unchanged.

## The `input_button` module param (driver PR #33)

The front power-mode button changes the EC register but, upstream, generates
no input event — the desktop has no way to know a mode change happened. The
patch registers a `KEY_POWER` input device on the power-mode register (0x31),
polled in the existing 1 s workqueue worker.

It is **default off** (`input_button=0`) deliberately: most desktops bind
`KEY_POWER` to the sleep/shutdown power menu, so leaving it on makes every
button press open that menu. The D-Bus backend already polls the power-mode
sysfs attribute and updates the desktop, so the input event is redundant for
this stack. Enable with `modprobe ec_su_axb35 input_button=1` if you want the
raw event (e.g. to bind it yourself).

## Reboot survival

- **Driver:** DKMS rebuilds it on every kernel upgrade; `/etc/modules-load.d/`
  auto-loads it at boot.
- **Services:** both are systemd **user** services with `enable` (start at
  login) + `Restart=on-failure`. The backend refuses to start if the module
  isn't loaded (it checks for the sysfs file first).
- **Applet:** installed to `~/.local/share/plasma/plasmoids/`, picked up by
  Plasma at login.
- **Privilege helper / udev / sudoers:** static files in `/etc` and
  `/usr/local/bin`.
