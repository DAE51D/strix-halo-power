#!/usr/bin/env python3
"""EVO-X2 APU power-mode D-Bus service.

Owns /sys/class/ec_su_axb35/apu/power_mode as the single validated writer and
emits ModeChanged(newMode, source) on any change, whether it came from this
service, the physical front button (EC), or the pmode CLI.
"""

import logging
import os
import shutil
import subprocess
import sys
import time

import gi

gi.require_version("GLib", "2.0")
gi.require_version("Gio", "2.0")
gi.require_version("GObject", "2.0")
from gi.repository import GLib, Gio, GObject

BUS_NAME = "com.evox2.powermode.backend"
OBJECT_PATH = "/com/evox2/powermode"
INTERFACE = "com.evox2.powermode"
VERSION = "1.0.0"
MODES = ("quiet", "balanced", "performance")
CYCLE_ORDER = {"quiet": "balanced", "balanced": "performance", "performance": "quiet"}
SYSFS_PATH = "/sys/class/ec_su_axb35/apu/power_mode"
POLL_INTERVAL_MS = 500
DEBOUNCE_MS = 300

log = logging.getLogger("powermode")

INTROSPECTION_XML = """
<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
<node>
  <interface name="com.evox2.powermode">
    <property name="Mode" type="s" access="read"/>
    <property name="Modes" type="as" access="read"/>
    <property name="Version" type="s" access="read"/>
    <method name="GetMode">
      <arg name="mode" type="s" direction="out"/>
    </method>
    <method name="SetMode">
      <arg name="mode" type="s" direction="in"/>
    </method>
    <method name="Cycle">
      <arg name="mode" type="s" direction="out"/>
    </method>
    <method name="Log">
      <arg name="message" type="s" direction="in"/>
    </method>
    <signal name="ModeChanged">
      <arg name="newMode" type="s"/>
      <arg name="source" type="s"/>
    </signal>
  </interface>
</node>
"""


def _read_sysfs():
    with open(SYSFS_PATH, "r") as f:
        return f.read().strip()


def _write_sysfs(mode):
    """Write the mode to sysfs, falling back to a sudo helper if the file is
    not group-writable (see README: the udev rule cannot set sysfs attribute
    permissions, so until the kernel PR lands the service uses a narrow
    sudoers entry)."""
    try:
        with open(SYSFS_PATH, "w") as f:
            f.write(mode + "\n")
        return
    except PermissionError:
        pass
    sudo = shutil.which("sudo")
    helper = shutil.which("pmode-write")
    if not sudo or not helper:
        raise
    cmd = [sudo, "-n", helper, mode]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise OSError("sudo write failed: %s" % proc.stderr.strip())


class PowerModeService:
    def __init__(self):
        self._mode = None
        self._pending_change = None
        self._bus = None

        node = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION_XML)
        self._iface_info = node.lookup_interface(INTERFACE)

    def _note_change(self, source):
        try:
            new_mode = _read_sysfs()
        except OSError as e:
            log.error("failed to re-read %s: %s", SYSFS_PATH, e)
            return False
        if new_mode not in MODES:
            log.warning("sysfs reports unknown mode %r; ignoring", new_mode)
            return False
        if new_mode == self._mode:
            return False
        self._mode = new_mode
        log.warning(
            "power mode changed to %s (source=%s) — RyzenAdj power limits "
            "reset to defaults; re-apply if you use ryzenadj",
            new_mode,
            source,
        )
        self._pending_change = (new_mode, source)
        GLib.timeout_add(DEBOUNCE_MS, self._emit_change)
        return True

    def _emit_change(self):
        if self._pending_change is None:
            return False
        new_mode, source = self._pending_change
        self._pending_change = None
        try:
            self._bus.emit_signal(
                None,
                OBJECT_PATH,
                INTERFACE,
                "ModeChanged",
                GLib.Variant("(ss)", (new_mode, source)),
            )
            log.info("emitted ModeChanged(%s, %s)", new_mode, source)
        except Exception:
            log.exception("failed to emit ModeChanged")
        return False

    def _poll(self):
        try:
            cur = _read_sysfs()
        except OSError as e:
            log.warning("sysfs read failed (module unloaded?): %s", e)
            return True
        if cur != self._mode:
            self._note_change("unknown")
        return True

    def _on_method_call(self, conn, sender, path, iface, method, params, invocation):
        if method == "GetMode":
            if self._mode is None:
                self._mode = _read_sysfs()
            invocation.return_value(GLib.Variant("(s)", (self._mode,)))
        elif method == "SetMode":
            mode = params.unpack()[0]
            self._do_set_mode(invocation, mode)
        elif method == "Cycle":
            cur = self._mode if self._mode is not None else _read_sysfs()
            nxt = CYCLE_ORDER.get(cur, "balanced")
            self._do_set_mode(invocation, nxt)
            invocation.return_value(GLib.Variant("(s)", (self._mode,)))
        elif method == "Log":
            msg = params.unpack()[0]
            log.info("applet: %s", msg)
            invocation.return_value(None)
        else:
            invocation.return_error(
                GLib.Error.new(
                    BUS_NAME + ".UnknownMethod", 0, "unknown method %r" % method
                )
            )
        return True

    def _do_set_mode(self, invocation, mode):
        if mode not in MODES:
            invocation.return_error(
                GLib.Error.new(
                    BUS_NAME + ".InvalidMode",
                    0,
                    "invalid mode %r; expected one of %s" % (mode, ", ".join(MODES)),
                )
            )
            return
        try:
            _write_sysfs(mode)
        except OSError as e:
            invocation.return_error(
                GLib.Error.new(
                    BUS_NAME + ".WriteFailed", 0, "failed to write sysfs: %s" % e
                )
            )
            return
        actual = None
        for _ in range(20):
            time.sleep(0.05)
            try:
                actual = _read_sysfs()
                break
            except OSError:
                continue
        if actual is None:
            invocation.return_error(
                GLib.Error.new(
                    BUS_NAME + ".ReadBackFailed", 0, "failed to read back sysfs"
                )
            )
            return
        if actual != mode:
            log.warning("requested %s but EC reports %s (clamped?)", mode, actual)
        self._note_change("applet")

    def _on_get_property(self, conn, sender, path, iface, prop):
        if prop == "Mode":
            if self._mode is None:
                self._mode = _read_sysfs()
            return GLib.Variant("s", self._mode)
        elif prop == "Modes":
            return GLib.Variant("as", list(MODES))
        elif prop == "Version":
            return GLib.Variant("s", VERSION)
        return None


def main():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    if not os.path.exists(SYSFS_PATH):
        log.error("%s not found — is the ec_su_axb35 module loaded?", SYSFS_PATH)
        return 1

    svc = PowerModeService()
    svc._mode = _read_sysfs()
    log.info("starting power-mode service v%s, initial mode=%s", VERSION, svc._mode)

    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    svc._bus = bus

    try:
        bus.register_object(
            OBJECT_PATH,
            svc._iface_info,
            svc._on_method_call,
            svc._on_get_property,
            None,
        )
    except GLib.Error as e:
        if "NameExists" in str(e) or "NameOwnerExists" in str(e):
            log.info("name %s already owned; exiting (single instance)", BUS_NAME)
            return 0
        raise

    try:
        bus.call_sync(
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "RequestName",
            GLib.Variant("(su)", (BUS_NAME, 0)),
            GLib.VariantType("(u)"),
            Gio.DBusCallFlags.NONE,
            -1,
            None,
        )
        log.info("acquired name %s", BUS_NAME)
    except GLib.Error as e:
        if "NameExists" in str(e) or "NameOwnerExists" in str(e):
            log.info("name %s already owned; exiting (single instance)", BUS_NAME)
            return 0
        raise

    GLib.timeout_add(POLL_INTERVAL_MS, svc._poll)
    loop = GLib.MainLoop()
    loop.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
