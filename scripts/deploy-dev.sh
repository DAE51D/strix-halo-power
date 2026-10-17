#!/usr/bin/env bash
# Deploy the working tree's applet to the live Plasma install and stamp it
# with a build timestamp, so the widget's About page (Settings -> About)
# shows exactly which build is running:
#
#     Strix Halo Power Mode 1.2.1+20261016.2130.a8414a5-dirty
#
# Only the *installed copy's* metadata.json is stamped. The source tree's
# Version stays a clean "1.2.1" (what build-plasmoid.sh packages and what
# pmode.prompt.md says to bump), so release builds never carry a timestamp.
#
# Stamp format: <Version>+<YYYYMMDD>.<HHMM>.<git short sha>[-dirty]
#   -dirty = uncommitted changes in the tree, i.e. the sha alone does not
#            identify what you deployed.
#
# Same pattern as the knvtop sibling project's scripts/deploy-dev.sh.
#
# plasmashell reads metadata when it loads the applet, so a running widget
# keeps its old stamp/QML until plasmashell restarts. Pass --restart to do
# that for you (it re-instantiates every widget and flashes the panel).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$repo_root/applet/com.daevid.pmode"
dest="${PMODE_DEST:-$HOME/.local/share/plasma/plasmoids/com.daevid.pmode}"

sha="$(git -C "$repo_root" rev-parse --short HEAD 2>/dev/null || echo nogit)"
if [[ -n "$(git -C "$repo_root" status --porcelain -- applet/com.daevid.pmode 2>/dev/null)" ]]; then
    sha="${sha}-dirty"
fi
stamp="$(date +%Y%m%d.%H%M).${sha}"

mkdir -p "$dest"
rsync -a --delete --exclude '__pycache__' "$src/" "$dest/"

python3 - "$dest/metadata.json" "$stamp" <<'PY'
import json
import sys

path, stamp = sys.argv[1], sys.argv[2]
with open(path) as f:
    meta = json.load(f)
meta["KPlugin"]["Version"] = f"{meta['KPlugin']['Version']}+{stamp}"
with open(path, "w") as f:
    json.dump(meta, f, indent=4)
    f.write("\n")
print("Deployed to", path, "->", meta["KPlugin"]["Version"])
PY

if [[ "${1:-}" == "--restart" ]]; then
    systemctl --user restart plasma-plasmashell.service
    echo "plasmashell restarted"
else
    echo "Not restarting plasmashell; run with --restart (or restart it yourself) to load this build."
fi
