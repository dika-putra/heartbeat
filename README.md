<div align="center">
  <img src="Resources/icon/icon.svg" width="128" height="128" alt="Heartbeat icon">

# Heartbeat

  A macOS menu bar app that nudges you to check your work at a configurable
  interval — for people who don't already have that habit.

  ![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
  ![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)
  ![License](https://img.shields.io/badge/license-MIT-green)
  [![Release](https://img.shields.io/github/v/release/dika-putra/heartbeat)](https://github.com/dika-putra/heartbeat/releases/latest)
</div>

## Preview
<img width="256" height="478" alt="Screenshot 2026-09-30 at 09 13 20" src="https://github.com/user-attachments/assets/2237adac-5ba3-47bc-a775-1234bd6625ce" />

## Download

Grab the latest `.dmg` from the [Releases page](https://github.com/dika-putra/heartbeat/releases/latest),
open it, and drag Heartbeat into Applications. See
[Installing the built app](#installing-the-built-app) below for the
Gatekeeper "unidentified developer" step.

## Features

- Configurable reminder interval, with separate Normal and Urgent modes
- Notifications only fire during a configurable active-hours window
  (default 08:00–17:00)
- Custom or system notification sound
- Custom reminder message
- Launch at login
- Notifications replace each other instead of stacking

## Build from source

Requires macOS 13+ and Swift 5.9+ (ships with Xcode 15+).

```bash
git clone git@github.com:dika-putra/heartbeat.git
cd heartbeat
./scripts/build-app.sh
open dist/Heartbeat.app
```

## Installing the built app

Drag `dist/Heartbeat.app` to `/Applications`.

This build is **not notarized** by Apple. On first launch, macOS Gatekeeper
will warn that it's from an unidentified developer (downloading the `.dmg`
via a browser adds a quarantine flag, which can make this warning stricter —
sometimes "Heartbeat can't be opened because Apple cannot check it for
malicious software", with no visible bypass option). To open it anyway:

1. Right-click (or Control-click) `Heartbeat.app` in `/Applications` → **Open**
   → **Open** again in the dialog.
2. If that doesn't offer an **Open** option: System Settings → Privacy &
   Security → scroll down → **Open Anyway**.
3. If it's still blocked, clear the quarantine flag directly in Terminal:
   ```bash
   xattr -cr /Applications/Heartbeat.app
   ```
   then open it normally.

## Running tests

```bash
swift test
```

## License

[MIT](LICENSE)
