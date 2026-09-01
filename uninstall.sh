#!/usr/bin/env bash
# Reverse of install.sh. Removes the applet, both user services, the privilege
# helper, the udev rule, and the DKMS driver. Does NOT remove the ec_su_axb35
# group (harmless) or touch your ryzenadj/other config.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log() { printf '\033[1;32m[pmode]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[pmode]\033[0m %s\n' "$*" >&2; }

if [ "$EUID" -ne 0 ]; then SUDO="sudo"; else SUDO=""; fi

log "stopping + disabling user services"
systemctl --user disable --now com.evox2.powermode 2>/dev/null || true
systemctl --user disable --now pmode-bridge 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/com.evox2.powermode.service" \
	"$HOME/.config/systemd/user/pmode-bridge.service"
systemctl --user daemon-reload

log "removing Plasma applet"
kpackagetool6 --type Plasma/Applet --remove com.daevid.pmode 2>/dev/null || true

log "removing installed binaries"
rm -f "$HOME/.local/bin/powermode_service.py" "$HOME/.local/bin/pmode-bridge"

log "removing privilege helper + sudoers + udev rule"
$SUDO rm -f /usr/local/bin/pmode-write /etc/sudoers.d/pmode \
	/etc/udev/rules.d/99-ec-su_axb35.rules /etc/modules-load.d/su_axb35.conf

log "removing DKMS driver + unloading module"
$SUDO dkms remove -m ec-su_axb35 -v 1.0 --all 2>/dev/null || true
$SUDO rmmod ec_su_axb35 2>/dev/null || warn "could not unload ec_su_axb35 (in use?)"

log "done. (The ec_su_axb35 group was left in place; remove it with: sudo groupdel ec_su_axb35)"
