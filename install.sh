#!/usr/bin/env bash
# One-shot installer for strix-halo-power.
# Installs: kernel driver (DKMS), privilege helper, udev rule,
# D-Bus backend service, C++ D-Bus bridge, and the Plasma 6 applet.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log() { printf '\033[1;32m[pmode]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[pmode]\033[0m %s\n' "$*" >&2; }
die() {
	printf '\033[1;31m[pmode]\033[0m %s\n' "$*" >&2
	exit 1
}

# --- 0. submodule -----------------------------------------------------------
if [ ! -f driver/src/ec_su_axb35.c ]; then
	die "driver/ submodule is empty. Run: git submodule update --init"
fi

# --- 1. kernel driver (DKMS) -----------------------------------------------
if [ "$EUID" -ne 0 ]; then
	warn "running as non-root; sudo will be used where needed"
	SUDO="sudo"
else
	SUDO=""
fi

log "building + installing kernel driver via DKMS"
$SUDO dkms remove -m ec-su_axb35 -v 1.0 --all 2>/dev/null || true
$SUDO dkms add -m ec-su_axb35 -v 1.0 --source-dir "$SCRIPT_DIR/driver"
$SUDO dkms build -m ec-su_axb35 -v 1.0 -k "$(uname -r)"
$SUDO dkms install -m ec-su_axb35 -v 1.0 -k "$(uname -r)"
echo "ec_su_axb35" | $SUDO tee /etc/modules-load.d/su_axb35.conf >/dev/null
$SUDO modprobe ec_su_axb35 || warn "modprobe failed (will load at next boot)"
[ -e /sys/class/ec_su_axb35/apu/power_mode ] ||
	die "driver did not expose /sys/class/ec_su_axb35/apu/power_mode"
log "driver up: $(cat /sys/class/ec_su_axb35/apu/power_mode 2>/dev/null || sudo cat /sys/class/ec_su_axb35/apu/power_mode)"

# --- 2. privilege helper ----------------------------------------------------
log "installing privilege helper + sudoers"
$SUDO groupadd -f ec_su_axb35
id -nG "$USER" | tr ' ' '\n' | grep -qx ec_su_axb35 ||
	$SUDO usermod -aG ec_su_axb35 "$USER"
$SUDO install -m 755 service/pmode-write /usr/local/bin/pmode-write
$SUDO install -m 440 service/pmode-sudoers /etc/sudoers.d/pmode
$SUDO visudo -cf /etc/sudoers.d/pmode >/dev/null
warn "group membership takes effect at your next login"

# --- 3. udev rule -----------------------------------------------------------
log "installing udev rule"
$SUDO install -m 444 service/99-ec-su_axb35.rules /etc/udev/rules.d/
$SUDO udevadm control --reload-rules && $SUDO udevadm trigger

# --- 4. D-Bus backend service ----------------------------------------------
log "installing D-Bus backend service"
mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
install -m 755 service/powermode_service.py "$HOME/.local/bin/powermode_service.py"
sed "s|__SCRIPT__|$HOME/.local/bin/powermode_service.py|g" \
	service/com.evox2.powermode.service >"$HOME/.config/systemd/user/com.evox2.powermode.service"
systemctl --user daemon-reload
systemctl --user enable --now com.evox2.powermode

# --- 5. C++ D-Bus bridge ----------------------------------------------------
log "compiling + installing D-Bus bridge"
command -v pkg-config >/dev/null || die "pkg-config not found (install qt6-base-dev)"
MOC="$(pkg-config --variable=host_bins Qt6Core)/moc"
[ -x "$MOC" ] || MOC="/usr/lib/qt6/libexec/moc"
# compile in a temp dir so the generated .moc lands next to the source
TMPB="$(mktemp -d)"
cp service/pmode-bridge.cpp "$TMPB/"
"$MOC" "$TMPB/pmode-bridge.cpp" -o "$TMPB/pmode-bridge.moc"
g++ -fPIC -std=c++17 "$TMPB/pmode-bridge.cpp" -o "$HOME/.local/bin/pmode-bridge" \
	$(pkg-config --cflags --libs Qt6DBus Qt6Core)
rm -rf "$TMPB"
install -m 644 service/pmode-bridge.service "$HOME/.config/systemd/user/pmode-bridge.service"
systemctl --user daemon-reload
systemctl --user enable --now pmode-bridge

# --- 6. Plasma applet -------------------------------------------------------
log "installing Plasma applet"
kpackagetool6 --type Plasma/Applet --install applet/org.kde.pmode

log "done. Add the 'Strix Halo Power Mode' widget to your panel."
log "verify: gdbus call --session --dest com.evox2.powermode --object-path /com/evox2/powermode --method com.evox2.powermode.GetMode"
