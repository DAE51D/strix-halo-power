# store.kde.org submission — draft copy

Paste directly into the submission form; adjust to taste.

## Title

Strix Halo Power Mode

## Tagline / short description (one line)

Panel widget + button to switch AMD Strix Halo APU power modes (quiet/balanced/performance)

## Category

Plasma 6 / Widgets (or "Plasma Addons" — whichever the current taxonomy
calls the widget category)

## Tags

amd, strix-halo, ryzen-ai, apu, power-mode, thermal, battery, thermal-profile,
system-monitor, plasmoid, gmktec, dbus

## Full description

**Strix Halo Power Mode** is a KDE Plasma 6 panel widget that switches the
APU power mode (`quiet` / `balanced` / `performance`) on **AMD Strix Halo**
hardware (Ryzen AI Max+ 395, Sixunited AXB35-02 EC — e.g. the GMKtec NucBox
EVO-X2). Left-click cycles through the three modes; right-click picks one
directly. The icon reflects the mode currently in effect, and it stays in
sync automatically if the mode changes from the physical `P-MODE` button
on the device instead.

**⚠️ This widget requires the full stack, not just the plasmoid.** It's a
thin D-Bus client — installing only this package through Plasma's "Get New
Widgets" browser will show a widget that does nothing. You must first
install:
- a small kernel driver (`ec_su_axb35`, DKMS) exposing the sysfs power-mode
  file and the front button as an input device
- a narrowly-scoped privilege helper (sudoers-gated) that performs the
  actual root-only sysfs write
- a systemd user D-Bus service + C++/Qt bridge that the widget talks to

All of that is one script: `sudo ./install.sh` from the project source.
Full install instructions, an architecture diagram, and the complete D-Bus
API are in the README at the link below.

**What it measures/controls is real, not cosmetic** — the modes set an
actual power/thermal envelope. Benchmarks in the repo show ~29% faster LLM
prompt processing in `performance` vs `quiet` mode on a 12B model
(Vulkan backend); token generation is close to mode-insensitive since it's
memory-bandwidth-bound rather than compute-bound.

Source, issue tracker, full documentation, and benchmark methodology:
https://github.com/DAE51D/strix-halo-power

## Note for whoever submits this

`origin` for this repo is already GitHub
(https://github.com/DAE51D/strix-halo-power) — no mirror step needed,
unlike the `knvtop` sibling project (which runs the other direction, Gitea
as canonical with a GitHub push mirror). Point the store listing's source
link straight at GitHub, and consider linking the "Releases" page
specifically once `.github/workflows/package.yml` has produced at least
one tagged `.plasmoid` build, so store visitors and direct downloaders get
the same artifact.

## Screenshots to attach

See `docs/` in the repo root (also embedded in README.md):
- `widget-menu.png` — the panel widget's right-click mode menu
- `pmode_button.png` — the physical P-MODE button referenced by the README

Consider adding one more before submitting: a screenshot of the compact
panel icon itself in each of the three modes (quiet/balanced/performance),
since the store listing's primary image is usually the compact
representation, and right now only the expanded menu is captured.
