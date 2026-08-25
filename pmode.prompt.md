# GMKtec EVO-X2 — Power-Mode Button, D-Bus Service, and Plasma Applet

> **Purpose of this file.** A complete, self-contained implementation brief so that
> this (or another LLM) can build the following *without re-researching the hardware*:
>
> 1. **A D-Bus service** that owns the APU power-mode sysfs file and exposes
>    `GetMode` / `SetMode` / a `ModeChanged` signal. (DE-agnostic core.)
> 2. **A KDE Plasma applet** (Kubuntu front-end) that shows the current mode and
>    lets you click to change it.
> 3. **A kernel input-driver PR** to `cmetz/ec-su_axb35-linux` so the **physical
>    front button** is exposed as a standard Linux input key, and the D-Bus service
>    reacts to it (this is the "proper, not-hack" way to get Windows-parity button
>    behavior on Linux).
>
> Everything below was verified on this specific box on **2026-08-18**. Re-verify the
> "Current state on this box" section before relying on it, but the hardware facts
> (ACPI tables, EC objects, sysfs layout) are stable and do not need re-derivation.

---

## 0. TL;DR — what to build, in what order

| # | Deliverable | Where it lives | Effort | Blocked on |
|---|-------------|----------------|--------|------------|
| 1 | D-Bus service (DE-agnostic core) | `~/pmode/` (new) | ~half day | nothing |
| 2 | KDE Plasma applet (Kubuntu) | `~/pmode/plasma/` | ~half day | #1 |
| 3 | Kernel input-driver PR | fork of `cmetz/ec-su_axb35-linux` | 1–2 days | author confirms button EC register |
| 4 | Wire #3 → #1 (button updates widget) | D-Bus service | ~1 h | #1 + #3 |

Do #1 and #2 first — they give a working "show mode + click to change" UX **today**,
independent of the kernel PR. #3 is the piece that makes the *physical button* work
in Linux; it is the only part that genuinely needs the module author.

---

## 1. Background: why the button "just works" on Windows but not Linux

The front power-mode button is wired to the **embedded controller (EC)**, not the
keyboard controller. The EC firmware does the actual work:

- **The EC toggles the power mode internally** on button press. This is
  OS-independent — it happens whether Windows or Linux is running.
- **Windows additionally gets a notification channel.** The EC emits an ACPI notify
  event; the Windows ACPI driver surfaces it as a **WMI event**; the vendor utility
  (or the FanControl AXB35 plugin) subscribes and updates its UI.

On Linux there are two gaps, both on the Linux side:

1. **The button is not exposed as a standard input event.** The only ACPI buttons
   registered on this box are `Power Button` (PNP0C0C) and `Sleep Button` (PNP0C0E).
   The front power-mode button is a raw EC notify (`_Q74`, see §5) that the Linux
   `acpi` button driver does **not** map to any `/dev/input/eventX`. So there is no
   input device to bind a shortcut to.
2. **Linux has no WMI stack**, so the EC notify event has no consumer.

The `ec_su_axb35` module talks to the EC over a custom register interface to
*read/write* state. It does **not** expose button presses as events. That is the gap
#3 (the kernel input driver) fills.

**Key consequence for the design:** because the EC switches the mode itself, the
D-Bus service does *not* need to drive the button. It only needs to (a) read the
current mode from sysfs, (b) write a new mode when the user clicks the applet, and
(c) notice when the mode changes by *any* means (button, CLI, applet) and emit
`ModeChanged`. The "notice" part is a sysfs watch (poll or inotify) — that is the
only coupling to the button, and it works regardless of whether #3 is merged.

---

## 2. Current state on this box (verified 2026-08-18)

Re-verify with the exact commands shown; these are the ground truth.

### 2.1 Hardware / OS

- **Host**: `EVO-X2` — GMKtec NucBox EVO-X2 (Sixunited AXB35-02 board).
- **APU**: AMD Ryzen AI Max+ 395 "Strix Halo" (gfx1151), APU with unified memory.
- **OS**: Kubuntu 26.04 LTS (Resolute Raccoon).
- **Kernel**: `7.0.0-29-generic` (at time of writing — `uname -r`).
- **User**: `dae51d`, passwordless `sudo` (`sudo -n true` succeeds).
- **DE**: KDE Plasma (Kubuntu).

### 2.2 Module is already installed and loaded

```
$ sudo modinfo ec_su_axb35
filename:       /lib/modules/7.0.0-29-generic/updates/ec_su_axb35.ko
description:    Sixunited AXB35-02 Embedded Controller driver
author:         loom@mopper.de
license:        GPL
name:           ec_su_axb35
vermagic:       7.0.0-29-generic SMP preempt mod_unload modversions

$ sudo lsmod | grep ec_su
ec_su_axb35            16384  0

$ cat /etc/modules          # module auto-loads at boot
ec_su_axb35
```

> **Note:** the module is *not* installed via DKMS on this box (no
> `~/.dkms`/`/var/lib/dkms/ec_su_axb35`). It is a bare `.ko` dropped into
> `/lib/modules/$(uname -r)/updates/`. That means **a kernel update orphans it** —
> the `.ko` stays but won't load on the new kernel until rebuilt. If we add a new
> module (the input driver, #3), we should switch the whole thing to **DKMS** so both
> modules rebuild automatically on kernel upgrades. See §8.

### 2.3 Sysfs surface (the API we build on)

```
/sys/class/ec_su_axb35/
├── apu/
│   ├── power_mode   (RW)  [quiet | balanced | performance]   ← THE file we own
│   └── power/       (runtime PM plumbing, ignore)
├── fan1/            CPU fan 1
├── fan2/            CPU fan 2
├── fan3/            system fan
│   ├── rpm          (RO)  current speed
│   ├── mode         (RW)  [auto | fixed | curve]
│   ├── level        (RW)  [0-5]
│   ├── rampup_curve   (RW) 5 °C thresholds
│   └── rampdown_curve (RW) 5 °C thresholds
└── temp1/
    ├── temp         (RO)  current °C
    ├── min          (RO)
    └── max          (RO)
```

Power-mode semantics (from the Strix Halo wiki, §7):

| mode        | STAPM (sustained) | PPT fast (boost) | PPT slow (avg) |
|-------------|-------------------|------------------|----------------|
| quiet       | 54 W              | 100 W            | 54 W           |
| balanced    | 85 W              | 120 W            | 120 W          |
| performance | 120 W             | 140 W            | 120 W          |

**Important gotcha:** changing the power mode via the EC **resets RyzenAdj power
limits to these defaults.** If the owner has fine-tuned limits with `ryzenadj`, they
must be re-applied after a mode switch. The D-Bus service should log a warning when
a mode change is detected (see §6, "RyzenAdj interaction").

### 2.4 Existing `pmode` CLI (already created this session)

`/home/dae51d/bin/pmode` (on PATH) — a bash one-liner equivalent to the button:

```bash
pmode            # cycle quiet → balanced → performance
pmode performance
pmode balanced
pmode quiet
```

It just writes to `/sys/class/ec_su_axb35/apu/power_mode`. **Keep it** as a CLI
fallback, but the D-Bus service (§4) supersedes it as the canonical writer. The
service and `pmode` can coexist; both just write the same sysfs file.

### 2.5 Input devices present (to confirm the button is NOT one of them)

```
event0  Power Button   (PNP0C0C)   ← ACPI power button, NOT the front button
event1  Sleep Button   (PNP0C0E)
event2  (i8042 keyboard)
event3  Video Bus
event4  USB 0000:3825  (some device)
event5-7 USB 1A2C:0B2A (mouse/trackpad)
event8-15 audio jack buttons (snd cards)
```

None of these is the front power-mode button. Confirmed: the button is an EC notify
only, with no input device. **This is the gap #3 closes.**

---

## 3. Architecture overview

```
┌─────────────────────────────────────────────────────────────────────┐
│  Physical front button                                              │
│        │  (EC firmware toggles mode internally — OS-independent)    │
│        ▼                                                            │
│   EC ──(ACPI notify _Q74)──► [ #3 kernel input driver ]            │
│                              emits KEY_... into /dev/input         │
│                              (optional; needed only for "press"    │
│                               to be *visible* to the OS)           │
└─────────────────────────────────────────────────────────────────────┘
        │  (mode change lands in sysfs either way)
        ▼
/sys/class/ec_su_axb35/apu/power_mode   ◄──── single source of truth
        │  (watched: poll/inotify)        ▲  (written by applet/CLI)
        ▼                                 │
┌────────────────────────────────────────────────────────────────────┐
│  [ #1 D-Bus service ]  com.evox2.powermode                         │
│   • GetMode() -> string                                            │
│   • SetMode(mode)                                                  │
│   • signal ModeChanged(string newMode, string source)              │
│   • owns the sysfs file; validates; emits signal on any change     │
└────────────────────────────────────────────────────────────────────┘
        ▲  (D-Bus calls)
        │
┌────────────────────────────────────────────────────────────────────┐
│  [ #2 KDE Plasma applet ]  shows icon+label, click to cycle/pick   │
└────────────────────────────────────────────────────────────────────┘
```

Design principles:

- **sysfs is the single source of truth.** The D-Bus service never keeps its own
  copy of the mode as authoritative — it always re-reads sysfs. This means the
  button (which writes via the EC), `pmode`, and the applet all converge on the
  same value with no locking drama.
- **The service is the only writer that validates.** It checks the value is one of
  the three legal modes before writing, so a bad applet/CLI can't brick the EC.
- **DE-agnostic core.** #1 is plain D-Bus; #2 is the Kubuntu front-end. A GNOME
  extension or i3bar script could consume #1 unchanged.
- **No polling hack in the UI.** The applet subscribes to `ModeChanged`; it does
  not spin a timer reading sysfs. (The *service* may poll sysfs at ~1 Hz to detect
  out-of-band changes — that is the one legitimate poll, and it is cheap.)

---

## 4. #1 — D-Bus service (implement first)

### 4.1 D-Bus interface

- **Bus**: session bus (the applet and the service both run in the user session).
  The service needs write access to the sysfs file, which is root-owned — see
  §4.4 for the privilege strategy.
- **Name**: `com.evox2.powermode`
- **Object**: `/com/evox2/powermode`
- **Interface**: `com.evox2.powermode`

```
interface com.evox2.powermode {
    // Properties
    @readonly property string Mode;            // current: quiet|balanced|performance
    @readonly property string[] Modes;         // ["quiet","balanced","performance"]
    @readonly property string Version;         // service version string

    // Methods
    string  GetMode();
    void    SetMode(in string mode);           // raises error on invalid mode
    string  Cycle();                           // advance to next, returns new mode

    // Signals
    signal  ModeChanged(string newMode, string source);
    //   source ∈ {"button","applet","cli","unknown"} — best-effort attribution
};
```

`ModeChanged` is the contract the applet (and any future consumer) relies on. The
`source` argument is best-effort: the service can't reliably tell *who* wrote sysfs,
but it can tag writes it initiated (`applet`/`cli`) vs. changes it merely observed
(`button`/`unknown`).

### 4.2 Behavior spec

1. **Startup**: read sysfs once, cache, export `Mode`. Begin watching.
2. **`SetMode(mode)`**:
   - validate `mode ∈ {quiet,balanced,performance}`; else raise
     `com.evox2.powermode.InvalidMode`.
   - write to sysfs; confirm by re-reading (the EC may clamp); if the read-back
     differs from what was requested, emit `ModeChanged` with the *actual* value and
     log a warning.
   - emit `ModeChanged(newMode, "applet")`.
3. **`Cycle()`**: read current, advance
   `quiet→balanced→performance→quiet`, call `SetMode`.
4. **Watch loop** (the only poll): every ~500 ms–1 s, re-read sysfs. If it differs
   from the last value the service knows, emit
   `ModeChanged(newMode, "button" or "unknown")`. Debounce so a single physical
   press doesn't fire multiple signals.
   - *Preferred:* use `inotify` on the sysfs file if the kernel reports writes as
     modify events (test this — sysfs attribute writes do generate `IN_MODIFY` on
     most kernels). Fall back to the poll if inotify doesn't fire.
5. **RyzenAdj interaction**: on *any* `ModeChanged`, log at `warning` level:
   `"power mode changed to X — RyzenAdj power limits reset to defaults; re-apply if
   you use ryzenadj"`. (See §7 wiki note.)
6. **Single instance**: use a D-Bus name ownership check; if the name is already
   owned, exit cleanly (don't run two watchers).

### 4.3 Language / stack recommendation

- **Python 3 + `gdbus`** (via `gi.repository.GLib`/`Gio`) is the lowest-friction
  choice on Kubuntu: `gdbus` is in the base, no extra deps, and it gives you
  method/signal/property export with ~60 lines.
  - Alternative: **C + `gdbus`** if you want a tiny static binary and no Python
    runtime dependency. More code, same API.
  - Avoid: a hand-rolled D-Bus socket server (error-prone), or `dbus-next` (async,
    more moving parts than needed here).
- **sysfs watch**: `GLib.timeout_add` for the poll path, or `inotify` via
  `pyinotify`/`GLib` for the event path.
- **Privilege**: the service runs as the user but needs to write a root-owned sysfs
  file. Options, in order of preference:
  1. **`polkit` / a small setuid helper** — overkill for a single file.
  2. **`udev` rule granting group write** on
     `/sys/class/ec_su_axb35/apu/power_mode` to a group the user is in, e.g.
     `SUBSYSTEM=="ec_su_axb35", KERNEL=="apu", ...` — see §4.4. This is the clean
     "proper" way and avoids setuid.
  3. **Run the service under a `systemd` user unit with `AmbientCapabilities`** —
     doesn't help for a plain sysfs write; skip.

### 4.4 Privilege strategy (recommended: udev rule)

Create `/etc/udev/rules.d/99-ec-su_axb35.rules`:

```
# Allow the 'ec_su_axb35' group to write the power-mode file.
SUBSYSTEM=="ec_su_axb35", KERNEL=="apu", MODE="0664", GROUP="ec_su_axb35"
```

- `sudo groupadd ec_su_axb35`
- `sudo usermod -aG ec_su_axb35 dae51d` (user must re-login to pick up the group)
- The D-Bus service then writes the file as the user with group permission. No
  setuid, no polkit, auditable.

> **Caveat:** this grants *any* process in the group write to the power-mode file.
> That is acceptable for a single-user homelab box. If you want stricter control,
> use a polkit action instead — but for this use case the udev rule is the
> proportionate "proper" solution.

### 4.5 systemd user unit

`~/.config/systemd/user/com.evox2.powermode.service`:

```ini
[Unit]
Description=EVO-X2 APU power-mode D-Bus service
After=default.target

[Service]
ExecStart=/usr/bin/python3 %h/pmode/powermode_service.py
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
```

Enable: `systemctl --user enable --now com.evox2.powermode`.

### 4.6 Files to produce for #1

```
~/pmode/
├── powermode_service.py     # the D-Bus service
├── com.evox2.powermode.service
├── 99-ec-su_axb35.rules     # udev rule (installed to /etc/udev/rules.d/)
└── README.md                # how to install/enable, the D-Bus API, the gotchas
```

### 4.7 Acceptance criteria for #1

- [ ] `gdbus call --session --dest com.evox2.powermode --object-path /com/evox2/powermode --method com.evox2.powermode.GetMode` returns the current mode.
- [ ] `gdbus call ... SetMode "performance"` changes the mode; `cat /sys/class/ec_su_axb35/apu/power_mode` reflects it.
- [ ] Pressing the **physical button** (or running `pmode`) causes a `ModeChanged`
      signal (verify with `gdbus monitor --session | grep ModeChanged`).
- [ ] Invalid mode raises `InvalidMode` and does not touch sysfs.
- [ ] Service survives a restart and re-exports the correct `Mode`.
- [ ] Only one instance runs (second start exits cleanly).

---

## 5. #3 — Kernel input-driver PR (the "proper" button fix)

This is the only piece that needs the module author, and the only piece that is
genuinely "not a hack." It makes the physical button a real Linux input key.

### 5.1 What the ACPI tables tell us (verified on this box)

The EC lives at `_SB.PCI0.SBRG.EC0` (HID `PNP0C09`). Its `_CRS` defines two I/O
regions (command `BUF0` = 0x66, data `BUF1` = 0x62 — matches the dmesg line
`ACPI: EC: EC_CMD/EC_SC=0x66, EC_DATA=0x62`). The EC exposes a large field of
named accessors. The ones relevant to power mode:

| EC object | Meaning (from DSDT strings) |
|-----------|------------------------------|
| `SPMF`    | **S**ystem **P**ower **M**ode **F**lag — the power-mode state |
| `DP55`    | power preset "55" (≈ quiet, 54 W) |
| `DP85`    | power preset "85" (≈ balanced, 85 W) |
| `D120`    | power preset "120" (≈ performance, 120 W) |
| `DPX1/2/3/5/6` | additional power presets |
| `MODS`    | mode status |
| `KBBL`    | keyboard/brightness-related (used by `_Q65`) |

The **ACPI notify methods** (the `_Qxx` handlers under `EC0`) that the EC fires:

| Notify | DSDT comment | Relevance |
|--------|--------------|-----------|
| `_Q05` | Brightness Decrease | not us |
| `_Q06` | Brightness Increase | not us |
| `_Q80` | Volume Up | not us |
| `_Q81` | Volume Down | not us |
| `_Q46` | FN F1 Status Change Event | not us |
| `_Q54` | **Power Button Event** (`\_SB_PWRB`) | this is the *power button* (sleep/shutdown), NOT the front perf button |
| `_Q65` | (no comment; touches `KBBL`) | likely keyboard/LED related |
| `_Q74` | **"dynamic DPTC, change thermal table EVENT"** — body stores `DP55`/`DP85`/`D120` | **THIS is the front power-mode button** |
| `_Q79` | (no comment) | unknown |

**Conclusion:** the front power-mode button fires ACPI notify **`_Q74`** on
`_SB.PCI0.SBRG.EC0`, and the handler writes one of the `DP55`/`DP85`/`D120` presets
to the EC. The EC then updates `SPMF`. The module's `power_mode` sysfs file reads
`SPMF` (that is why `cat power_mode` reflects the button — the EC did the work).

> **What we still need from the author:** the exact EC **data register offset** for
> `SPMF` (read) and the preset write register, plus confirmation of which `_Q74`
> GPE/notify number maps to the front button on the AXB35-02. The DSDT gives us the
> *names* and the *event*, but the raw EC byte offsets are what the C driver needs,
> and those are reverse-engineered knowledge the author (`loom@mopper.de`) already
> has (the module already reads `SPMF` to populate `power_mode`).

### 5.2 The PR, concretely

Fork `https://github.com/cmetz/ec-su_axb35-linux` (note: README author is
`loom@mopper.de`; repo owner is `cmetz`). Repo layout (verified):

```
ec-su_axb35-linux/
├── src/            # the C driver source
├── hwmon/          # hwmon glue
├── python-gui/     # existing python GUI (root) — prior art for #2
├── scripts/        # info.sh, test_fan_mode_fixed.sh, su_axb35_monitor
├── contrib/
├── Kbuild / Makefile
├── README.md
└── LICENSE (GPL-2.0)
```

**Proposed PR: "expose the front power-mode button as an input key"**

1. **New file `src/input_dev.c`** (or extend the existing driver) that:
   - Registers an `input_dev` with a single key. Use a **vendor key** to avoid
     colliding with reserved codes, e.g. `KEY_PROG1` (0x87) or a `KEY_...` in the
     vendor range `0xE000+`. Document the chosen code in the README.
   - Subscribes to the EC's button event. Two implementation options:
     - **(a) ACPI notify hook** — register for the `_Q74` notify on the EC device
       (the "proper" ACPI way; requires the GPE number, which the author has).
     - **(b) EC register poll / interrupt** — if the EC exposes a button-status
       register, read it on the EC interrupt. Simpler if (a)'s GPE is fiddly.
   - On event: `input_report_key(dev, KEY_PROG1, 1)` then `(..., 0)` (press+release),
     `input_sync(dev)`.
   - Set `dev->name = "EVO-X2 power-mode button"`, a stable `phys`/`uniq`, and
     `input_set_capability(dev, EV_KEY, KEY_PROG1)`.
   - `BUSTYPE_BUSUNKNOWN`, `DEVTYPE...` as appropriate; register via
     `input_register_device`.
2. **Kbuild/Makefile** — add the new source to the build (or keep it in the same
   `.ko` if it's a small addition; a single module is simpler for DKMS).
3. **README** — document the new input device, the key code, and how to bind it
   (e.g. KDE System Settings → Shortcuts, or `input-remapper`, or a udev rule).
4. **Optional but nice:** also emit a udev tag so a udev rule can auto-trigger
   `pmode cycle` or the D-Bus `Cycle()` method — but the *primary* contract is the
   input key; the D-Bus service (§4) already reacts to the sysfs change, so the
   input key is mostly for *other* tools / global shortcuts.

**Why this is the "proper" way (vs. hacks):**
- It uses the kernel's input subsystem — the standard, supported mechanism for
  hardware buttons. No userspace daemon guessing, no WMI, no polling the EC from
  userspace.
- It's a small, reviewable, GPL out-of-tree module that fits the existing repo.
- It benefits every AXB35-02 vendor (GMKtec, Bosgame, FEVM, Peladn, NIMO — see
  README) and is the kind of thing that could even be upstreamed.

**Effort:** 1–2 days *if* the author confirms the EC register/GPE. The C is
straightforward (input drivers are a well-trodden path); the unknown is the
hardware detail, which is the author's domain. **Action:** open an *issue* first
asking for the `SPMF` read offset + the `_Q74` GPE number, then submit the PR
against that.

### 5.3 DKMS (do this as part of #3, or independently)

Because the module is currently a bare `.ko` (see §2.2), a kernel update orphans it.
Add DKMS so `ec_su_axb35` **and** the new input driver rebuild on every kernel:

```
# dkms.conf
PACKAGE_NAME="ec-su_axb35"
PACKAGE_VERSION="1.0"
MAKE[0]="make -C ${kernel_source_dir} M=${dkms_tree}/${DKMS_PACKAGE}/${DKMS_VERSION}/build KERNELRELEASE=${kernelver} modules"
CLEAN="make -C ${kernel_source_dir} M=${dkms_tree}/${DKMS_PACKAGE}/${DKMS_VERSION}/build KERNELRELEASE=${kernelver} clean"
BUILT_MODULE_NAME[0]="ec_su_axb35"
DEST_MODULE_LOCATION[0]="/updates"
AUTOINSTALL="yes"
```

```
sudo dkms add -m ec-su_axb35 -v 1.0
sudo dkms build -m ec-su_axb35 -v 1.0 -k $(uname -r)
sudo dkms install -m ec-su_axb35 -v 1.0 -k $(uname -r)
```

Then remove the bare `.ko` and the `/etc/modules` line (DKMS +
`/etc/modules-load.d/ec_su_axb35.conf` handles loading). This is a real improvement
for the repo and a good standalone PR.

---

## 6. #2 — KDE Plasma applet (Kubuntu front-end)

A Plasma **system-monitor / custom applet** (QML) that:

- Shows the current mode as an icon + short label (e.g. a gauge icon +
  "Quiet" / "Balanced" / "Perf").
- **Left-click** → menu with the three modes (check-mark the current one) **and** a
  "Cycle" entry. Selecting one calls `SetMode`; "Cycle" calls `Cycle()`.
- **Subscribes** to `ModeChanged` and updates icon+label live (no timers).
- Optional: right-click → "Open terminal" / "Show RPMs & temp" (reads
  `fanX/rpm`, `temp1/temp` — nice-to-have, not required).

### 6.1 Stack

- **Plasma 6 (KDE Frameworks / QML)**, packaged as a Plasma applet
  (`metadata.json` + `contents/ui/main.qml`). Kubuntu 26.04 ships Plasma 6.
- Talk to the D-Bus service via QML's `QtDBus` (`Qt.createQmlObject` or a small
  `plasmoid`-exposed helper). No need to read sysfs from QML — always go through
  the D-Bus service (single writer, validated).
- Icon: use Breeze icons (`breeze:power-management` or a custom SVG per mode).

### 6.2 Files to produce for #2

```
~/pmode/plasma/
├── metadata.json            # applet manifest (Plasma 6)
├── contents/
│   └── ui/
│       ├── main.qml         # the widget
│       └── powermode.js     # D-Bus helper (get/set/cycle, subscribe)
├── icons/                   # optional per-mode SVGs
└── README.md                # install: copy to ~/.local/share/plasma/... or build .plasmoid
```

### 6.3 Install (dev loop)

```
# quick test without packaging:
kpackagetool6 --type Plasma/Applet --install ~/pmode/plasma
# or copy into the applets dir and restart plasmashell:
cp -r ~/pmode/plasma ~/.local/share/plasma/plasmoids/com.evox2.powermode
kquitapp6 plasmashell && kstart plasmashell &
```

### 6.4 Acceptance criteria for #2

- [ ] Applet appears in the system-tray / panel; shows the correct current mode.
- [ ] Click → menu lists the 3 modes + Cycle; picking one changes the mode and the
      icon updates immediately (via `ModeChanged`, not a refresh).
- [ ] Press the **physical button** → applet updates within ~1 s (proves the
      service's watch loop works end-to-end).
- [ ] Applet survives a `plasmashell` restart and re-reads the correct mode.
- [ ] No busy-waiting in QML (verify with `qdbus`/`gdbus monitor` that updates are
      signal-driven).

---

## 7. Reference: Strix Halo wiki (the source of truth for semantics)

- Power-mode + fan-control guide (Sixunited AXB35):
  `https://strixhalo.wiki/Guides/Sixunited_AXB35/Power_Mode_and_Fan_Control`
- Module repo: `https://github.com/cmetz/ec-su_axb35-linux`
- Windows EC impl (reference for the EC register map): `https://github.com/deseven/ec-su_axb35-win`
- FanControl AXB35 plugin (Windows, no secure-boot-disable): `https://github.com/pajtony/FanControl.AXB35`
- RyzenAdj (fine-tune power limits): `https://github.com/FlyGoat/RyzenAdj`
- Board vendor list: `https://strixhalo-homelab.d7.wtf/Hardware/Boards/Sixunited-AXB35`

**RyzenAdj gotcha (repeated because it bites):** changing the power mode via the EC
resets `STAPM LIMIT`, `PPT LIMIT FAST`, `PPT LIMIT SLOW` to the per-mode defaults
(§2.3 table). If the owner uses `ryzenadj --stapm-limit=... --fast-limit=...
--slow-limit=...`, those must be re-applied after every mode switch. The D-Bus
service should warn on every `ModeChanged` (see §4.2.5).

---

## 8. Implementation checklist (copy into a todo list)

### Phase 1 — D-Bus service (#1)  [~half day, no blockers]
- [ ] Create `~/pmode/` skeleton.
- [ ] Write `powermode_service.py` (gdbus): properties `Mode`/`Modes`/`Version`,
      methods `GetMode`/`SetMode`/`Cycle`, signal `ModeChanged`.
- [ ] Implement sysfs watch (inotify preferred, poll fallback), debounced.
- [ ] Validate `SetMode`; raise `InvalidMode` on bad input.
- [ ] Log RyzenAdj warning on every mode change.
- [ ] Single-instance guard (D-Bus name ownership).
- [ ] `com.evox2.powermode.service` user unit; enable.
- [ ] udev rule + `ec_su_axb35` group for sysfs write permission.
- [ ] Verify all §4.7 acceptance criteria with `gdbus`.

### Phase 2 — Plasma applet (#2)  [~half day, needs #1]
- [ ] `metadata.json` + `main.qml` + `powermode.js`.
- [ ] Icon + label reflecting `Mode`; subscribe to `ModeChanged`.
- [ ] Click menu: 3 modes + Cycle; call D-Bus methods.
- [ ] Install via `kpackagetool6`; verify §6.4 acceptance criteria.
- [ ] (Nice-to-have) RPM/temp readout in a right-click panel.

### Phase 3 — Kernel input-driver PR (#3)  [1–2 days, needs author]
- [ ] Open issue on `cmetz/ec-su_axb35-linux` asking for: `SPMF` read offset,
      preset-write register, and the `_Q74` GPE/notify number for the front button.
- [ ] On reply: add `src/input_dev.c` (or extend driver) registering `KEY_PROG1`
      (or chosen vendor key) on the `_Q74` event.
- [ ] Update Kbuild/Makefile + README.
- [ ] Add DKMS (`dkms.conf`) for `ec_su_axb35` (+ input driver); migrate off the
      bare `.ko` and `/etc/modules` line.
- [ ] Submit PR; tag the wiki / repo.

### Phase 4 — Wire button → widget (#4)  [~1 h, needs #1 + #3]
- [ ] Confirm the D-Bus service's watch loop fires `ModeChanged` when the physical
      button is pressed (it should, since the EC updates sysfs).
- [ ] If the input key (#3) is preferred as the trigger, add a udev rule or a tiny
      listener that calls `com.evox2.powermode.Cycle()` on `KEY_PROG1`.
- [ ] End-to-end test: press button → applet updates → `gdbus monitor` shows signal.

---

## 9. Decisions & rationale (so a future implementer doesn't second-guess)

- **Why a D-Bus service instead of just reading sysfs in the applet?** Single
  validated writer, one place to own the watch loop, one place to log the RyzenAdj
  warning, and a stable API that any DE can consume. Reading sysfs from QML would
  duplicate the watch logic in every consumer and bypass validation.
- **Why session bus, not system bus?** The applet is a user-session component; the
  sysfs write is granted via a udev group rule, not root. Session bus keeps it all
  in the user's namespace and avoids a system service + polkit for one file.
- **Why poll/inotify in the service rather than a kernel event?** The kernel input
  driver (#3) is the *proper* event source, but it's blocked on the author. The
  service's sysfs watch is a **correct, low-cost fallback** that works today and
  keeps working after #3 lands (the EC still updates sysfs either way). It is not a
  hack — it's the standard way to observe a sysfs attribute from userspace.
- **Why keep `pmode`?** It's a zero-dependency CLI fallback and is already on PATH.
  The D-Bus service supersedes it as the canonical writer but they coexist fine.
- **Why not just use the existing `python-gui/` in the repo?** It's a root GUI app,
  not a panel applet, and not D-Bus-based. We want a proper tray/panel applet with a
  stable API, not a throwaway window. (The repo's `python-gui/` is still useful as
  prior art for the EC sysfs calls.)

---

## 10. Verification commands (keep handy)

```bash
# current mode
cat /sys/class/ec_su_axb35/apu/power_mode

# set mode (CLI)
echo performance | sudo tee /sys/class/ec_su_axb35/apu/power_mode
#   or, with the udev group rule in place, as the user:
echo performance > /sys/class/ec_su_axb35/apu/power_mode

# D-Bus (service running)
gdbus call --session --dest com.evox2.powermode \
  --object-path /com/evox2/powermode \
  --method com.evox2.powermode.GetMode
gdbus call --session --dest com.evox2.powermode \
  --object-path /com/evox2/powermode \
  --method com.evox2.powermode.SetMode performance
gdbus monitor --session 2>/dev/null | grep -i modechanged

# module status
sudo lsmod | grep ec_su
sudo dmesg | grep -i "Sixunited AXB35-02 EC driver loaded"

# fan/temp (sanity)
cat /sys/class/ec_su_axb35/temp1/temp
cat /sys/class/ec_su_axb35/fan1/rpm

# ACPI evidence (for the #3 PR)
sudo cat /sys/firmware/acpi/tables/DSDT | strings | grep -E "_Q74|SPMF|DP55|DP85|D120"
```

---

*End of brief. Built from live inspection of EVO-X2 on 2026-08-18. If the kernel,
module, or DSDT has changed since, re-run §2 and §5.1 before implementing.*
