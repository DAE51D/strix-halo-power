#!/usr/bin/env python3
"""EVO-X2 APU power-mode D-Bus service.

Owns /sys/class/ec_su_axb35/apu/power_mode as the single validated writer and
emits ModeChanged(newMode, source) on any change, whether it came from this
service, the physical front button (EC), or the pmode CLI.

Also exposes live telemetry (power, temp, fan RPMs, load) via GetTelemetry(),
polled from amd-smi/sysfs at ~1 Hz.
"""

import glob
import json
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
VERSION = "1.2.0"
MODES = ("quiet", "balanced", "performance")
CYCLE_ORDER = {"quiet": "balanced", "balanced": "performance", "performance": "quiet"}
SYSFS_PATH = "/sys/class/ec_su_axb35/apu/power_mode"
SYSFS_BASE = "/sys/class/ec_su_axb35"
POLL_INTERVAL_MS = 500
TELEMETRY_POLL_MS = 1000
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
    <method name="GetLoadAverage">
      <arg name="load" type="d" direction="out"/>
    </method>
    <method name="GetTelemetry">
      <arg name="telemetry" type="s" direction="out"/>
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
    <method name="GetEnergy">
      <arg name="energy" type="s" direction="out"/>
    </method>
    <method name="ResetEnergy">
    </method>
    <method name="GetRate">
      <arg name="rate" type="d" direction="out"/>
    </method>
    <method name="SetRate">
      <arg name="rate" type="s" direction="in"/>
    </method>
    <signal name="ModeChanged">
      <arg name="newMode" type="s"/>
      <arg name="source" type="s"/>
    </signal>
    <signal name="TelemetryUpdated">
      <arg name="telemetry" type="s"/>
    </signal>
  </interface>
</node>
"""


def _read_sysfs():
    with open(SYSFS_PATH, "r") as f:
        return f.read().strip()


def _read_sysfs_file(path):
    with open(path, "r") as f:
        return f.read().strip()


def _read_int(path):
    try:
        return int(_read_sysfs_file(path))
    except (OSError, ValueError):
        return None


def _read_float(path):
    try:
        return float(_read_sysfs_file(path))
    except (OSError, ValueError):
        return None


def _get_amdgpu_hwmon():
    """Resolve the amdgpu hwmon by name (not index), so it survives reboots."""
    for hw in sorted(glob.glob("/sys/class/hwmon/hwmon*")):
        try:
            if _read_sysfs_file(hw + "/name").strip() == "amdgpu":
                return hw
        except OSError:
            continue
    return None


def _power_w():
    """Current package power in watts. Try amd-smi first, then sysfs hwmon."""
    try:
        out = subprocess.run(
            ["amd-smi", "metric", "--json"],
            capture_output=True,
            text=True,
            timeout=5,
        ).stdout
        d = json.loads(out)["gpu_data"][0]
        p = d.get("power", {})
        val = p.get("socket_power", {}).get("value")
        if val is None:
            val = p.get("apu_average_gfx_power", {}).get("value")
        if isinstance(val, (int, float)):
            return round(float(val), 1)
    except Exception:
        pass
    # Fallback: sysfs hwmon power1_input (µW)
    hw = _get_amdgpu_hwmon()
    if hw:
        uw = _read_int(hw + "/power1_input")
        if uw is not None:
            return round(uw / 1e6, 1)
    return None


def _telemetry(mode=None):
    """Collect a snapshot of power, temp, fan RPMs, load, and mode."""
    t = {}
    t["power_w"] = _power_w()
    # Temp: prefer EC sensor (register 0x70), fallback to amd-smi
    t["temp_c"] = _read_float(SYSFS_BASE + "/temp1/temp")
    if t["temp_c"] is None:
        try:
            out = subprocess.run(
                ["amd-smi", "metric", "--json"],
                capture_output=True,
                text=True,
                timeout=5,
            ).stdout
            d = json.loads(out)["gpu_data"][0]
            temp = d.get("temperature", {})
            val = temp.get("apu_temperature_gfx", {}).get("value")
            if val is None:
                val = temp.get("edge", {}).get("value")
            if isinstance(val, (int, float)):
                t["temp_c"] = round(float(val), 1)
        except Exception:
            pass
    # Fan RPMs
    for i in (1, 2, 3):
        t["fan%d_rpm" % i] = _read_int(SYSFS_BASE + "/fan%d/rpm" % i)
    # Load average (1-min)
    try:
        t["load1"] = round(float(os.getloadavg()[0]), 2)
    except (AttributeError, OSError):
        t["load1"] = None
    # Current mode
    t["mode"] = mode
    return t


ENERGY_DIR = os.path.expanduser("~/.local/share/evox2-power")
ENERGY_FILE = os.path.join(ENERGY_DIR, "energy.json")
RATE_FILE = os.path.join(ENERGY_DIR, "rate.json")
DEFAULT_RATE = 0.13  # $/kWh


def _ensure_energy_dir():
    os.makedirs(ENERGY_DIR, exist_ok=True)


def _load_energy():
    """Load persisted energy data. Returns {total_wh, last_updated, started}."""
    try:
        with open(ENERGY_FILE, "r") as f:
            data = json.load(f)
            return {
                "total_wh": float(data.get("total_wh", 0)),
                "last_updated": float(data.get("last_updated", 0)),
                "started": float(data.get("started", time.time())),
            }
    except (OSError, ValueError, KeyError):
        return {"total_wh": 0.0, "last_updated": 0.0, "started": time.time()}


def _save_energy(total_wh, last_updated, started=None):
    """Persist energy data to disk."""
    _ensure_energy_dir()
    try:
        with open(ENERGY_FILE, "w") as f:
            json.dump(
                {
                    "total_wh": total_wh,
                    "last_updated": last_updated,
                    "started": started if started else time.time(),
                },
                f,
            )
    except OSError as e:
        log.warning("failed to save energy data: %s", e)


def _load_rate():
    """Load the configured $/kWh rate."""
    try:
        with open(RATE_FILE, "r") as f:
            data = json.load(f)
            return float(data.get("rate", DEFAULT_RATE))
    except (OSError, ValueError, KeyError):
        return DEFAULT_RATE


def _save_rate(rate):
    """Persist the configured $/kWh rate."""
    _ensure_energy_dir()
    try:
        with open(RATE_FILE, "w") as f:
            json.dump({"rate": rate}, f)
    except OSError as e:
        log.warning("failed to save rate: %s", e)


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
        self._telemetry = None
        self._telemetry_pending = None

        # Energy tracking state
        self._energy = _load_energy()
        self._energy_dirty = False
        self._rate = _load_rate()

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

    def _accumulate_energy(self, power_w, now):
        """Add power_w × dt to the total Wh accumulator. dt is the time since
        the last update (or the poll interval if this is the first sample)."""
        if power_w is None:
            return
        last = self._energy["last_updated"]
        if last == 0:
            # First sample: just record the timestamp, don't accumulate
            self._energy["last_updated"] = now
            return
        dt = now - last
        if dt <= 0 or dt > 3600:
            # Clock jumped or too large a gap; skip accumulation to avoid
            # recording bogus energy for time we weren't polling
            self._energy["last_updated"] = now
            return
        dwh = power_w * dt / 3600.0
        self._energy["total_wh"] += dwh
        self._energy["last_updated"] = now
        self._energy_dirty = True

    def _poll_telemetry(self):
        """Poll power/temp/fans/load every ~1 s and emit TelemetryUpdated on
        significant changes (>1 W, >1°C, >50 RPM, >0.1 load)."""
        try:
            cur = _telemetry(self._mode)
        except Exception:
            cur = {}
        if not cur:
            return True
        self._telemetry = cur
        # Accumulate energy from the power reading
        self._accumulate_energy(cur.get("power_w"), time.time())
        if self._telemetry_pending is None:
            # First sample: emit immediately so the applet has data
            self._telemetry_pending = cur
            GLib.timeout_add(DEBOUNCE_MS, self._emit_telemetry)
            return True
        # Compare to last emitted sample; emit only if something changed enough
        prev = self._telemetry_pending
        changed = False
        if (
            cur.get("power_w") is not None
            and prev.get("power_w") is not None
            and abs(cur["power_w"] - prev["power_w"]) > 1.0
        ):
            changed = True
        if (
            cur.get("temp_c") is not None
            and prev.get("temp_c") is not None
            and abs(cur["temp_c"] - prev["temp_c"]) > 1.0
        ):
            changed = True
        for i in (1, 2, 3):
            key = "fan%d_rpm" % i
            if (
                cur.get(key) is not None
                and prev.get(key) is not None
                and abs(cur[key] - prev[key]) > 50
            ):
                changed = True
        if (
            cur.get("load1") is not None
            and prev.get("load1") is not None
            and abs(cur["load1"] - prev["load1"]) > 0.1
        ):
            changed = True
        if cur.get("mode") != prev.get("mode"):
            changed = True
        if changed:
            self._telemetry_pending = cur
            GLib.timeout_add(DEBOUNCE_MS, self._emit_telemetry)
        return True

    def _emit_telemetry(self):
        if self._telemetry_pending is None:
            return False
        sample = self._telemetry_pending
        self._telemetry_pending = None
        try:
            payload = json.dumps(sample)
            self._bus.emit_signal(
                None,
                OBJECT_PATH,
                INTERFACE,
                "TelemetryUpdated",
                GLib.Variant("(s)", (payload,)),
            )
            log.debug(
                "emitted TelemetryUpdated(%s W, %s °C, load %s)",
                sample.get("power_w"),
                sample.get("temp_c"),
                sample.get("load1"),
            )
        except Exception:
            log.exception("failed to emit TelemetryUpdated")
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
        elif method == "GetLoadAverage":
            try:
                load = float(os.getloadavg()[0])
            except (AttributeError, OSError):
                load = -1.0
            invocation.return_value(GLib.Variant("(d)", (load,)))
        elif method == "SetMode":
            mode = params.unpack()[0]
            self._do_set_mode(invocation, mode)
        elif method == "Cycle":
            cur = self._mode if self._mode is not None else _read_sysfs()
            nxt = CYCLE_ORDER.get(cur, "balanced")
            self._do_set_mode(invocation, nxt)
            invocation.return_value(GLib.Variant("(s)", (self._mode,)))
        elif method == "GetTelemetry":
            if self._telemetry is not None:
                payload = json.dumps(self._telemetry)
            else:
                payload = json.dumps(_telemetry(self._mode))
            invocation.return_value(GLib.Variant("(s)", (payload,)))
        elif method == "GetEnergy":
            total_wh = self._energy["total_wh"]
            total_cost = round(total_wh / 1000.0 * self._rate, 4)
            payload = json.dumps(
                {
                    "total_wh": round(total_wh, 2),
                    "total_cost": total_cost,
                    "session_wh": 0,
                    "started": self._energy.get("started", 0),
                }
            )
            invocation.return_value(GLib.Variant("(s)", (payload,)))
        elif method == "ResetEnergy":
            self._energy = {
                "total_wh": 0.0,
                "last_updated": time.time(),
                "started": time.time(),
            }
            self._save_energy(0.0, self._energy["last_updated"])
            invocation.return_value(None)
        elif method == "GetRate":
            invocation.return_value(GLib.Variant("(d)", (self._rate,)))
        elif method == "SetRate":
            rate_str = params.unpack()[0]
            try:
                new_rate = float(rate_str)
                if new_rate < 0:
                    raise ValueError("rate must be non-negative")
                self._rate = new_rate
                _save_rate(new_rate)
                invocation.return_value(None)
            except (ValueError, IndexError) as e:
                invocation.return_error(
                    GLib.Error.new(BUS_NAME + ".InvalidRate", 0, "invalid rate: %s" % e)
                )
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
    GLib.timeout_add(TELEMETRY_POLL_MS, svc._poll_telemetry)
    GLib.timeout_add(
        60000,
        lambda: (
            svc._save_energy(
                svc._energy["total_wh"],
                svc._energy["last_updated"],
                svc._energy.get("started"),
            )
            if svc._energy_dirty
            else True
        ),
    )
    loop = GLib.MainLoop()
    loop.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
