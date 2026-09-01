# Publishing the Strix Halo Power Mode widget — checklist

Split into two groups: things that can be done in this repo/session, and
things that need your own KDE Identity login (store submission is a web
form under your account — not something an agent session can do for you,
account creation and credential entry are off-limits regardless of
permission mode).

Unlike a self-contained widget, `org.kde.pmode` is a thin D-Bus client —
it does nothing without the kernel driver + privilege helper + backend
service also being installed (see README.md's stack table). That must be
called out prominently wherever this gets listed, since installing just
the `.plasmoid` leaves the widget showing a disconnected/no-op state.

## Local prep (this session can do these)

- [x] Fix `applet/org.kde.pmode/metadata.json`'s `License` field — it said
      `LGPL-2.1-or-later` but the repo's actual `LICENSE` is MIT (with the
      `driver/` submodule separately GPL-2.0, unaffected by this)
- [x] Packaging script (`scripts/build-plasmoid.sh`) that builds
      `pmode-<version>.plasmoid` (a zip of `applet/org.kde.pmode/`'s
      contents, `metadata.json` at the zip root) via `git archive`, same
      approach as the `knvtop` sibling project
- [x] GitHub Actions release workflow (`.github/workflows/package.yml`) —
      pushing a `v*` tag builds the `.plasmoid` and attaches it to a GitHub
      Release automatically, so the repo's own GitHub becomes a real
      distribution point without a manual build step each time
- [x] Draft store listing copy (title, tagline, longer description, tags/
      category) — see `STORE_LISTING.md`
- [ ] Test-build the plasmoid locally (`./scripts/build-plasmoid.sh`) and
      test-install it via `kpackagetool6 -t Plasma/Applet -u
      pmode-1.0.0.plasmoid` to confirm the zip is structured correctly —
      do this before ever pushing a tag or submitting to the store
- [ ] Push a `v1.0.0` tag to trigger the release workflow and confirm the
      GitHub Release + attached `.plasmoid` come out right — **this is a
      real, publicly visible action (creates a tag + a GitHub Release), so
      it's left for you to trigger deliberately** rather than done
      automatically: `git tag v1.0.0 && git push origin v1.0.0`

## Needs your KDE Identity login (can't be done from here)

- [ ] Create/log into a KDE Identity account at id.kde.org (shared login
      across store.kde.org, invent.kde.org, bugs.kde.org)
- [ ] Go to store.kde.org → Plasma 6 add-ons / widgets category → "Add new
      item" (or whatever the current upload flow is labeled)
- [ ] Fill in the submission form using the drafted copy in
      `STORE_LISTING.md`, attach screenshots from `docs/`, upload the
      `.plasmoid` built above (or link the GitHub Release instead, if the
      form supports an external download URL)
- [ ] Make sure the listing's description leads with the "you also need to
      install the driver + services" caveat — a store visitor installing
      only the widget through Plasma's "Get New Widgets" flow won't see
      the README
- [ ] Publish / submit for review

If anything in the "local prep" half unexpectedly trips a guardrail too,
skip it here and do it yourself — no need to fight it, just note which
item and move to the next one.
