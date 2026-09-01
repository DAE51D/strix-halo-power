#!/usr/bin/env bash
# Build org.kde.pmode.plasmoid -- a zip of applet/org.kde.pmode/'s contents
# with metadata.json at the zip root, the format store.kde.org and Plasma's
# "Install from local file" both expect.
#
# Uses `git archive` (not a raw zip/tar) so only files actually tracked in
# git end up in the package -- local dev cruft is excluded automatically
# without needing to duplicate .gitignore's rules here.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(python3 -c "import json; print(json.load(open('$repo_root/applet/org.kde.pmode/metadata.json'))['KPlugin']['Version'])")"
out="$repo_root/pmode-${version}.plasmoid"

cd "$repo_root"
git archive --format=zip -o "$out" HEAD:applet/org.kde.pmode

echo "Built: $out"
unzip -l "$out"
