<div align="center">
  <img src="Resources/icon/icon.svg" width="128" height="128" alt="Heartbeat icon">

# Heartbeat

  A macOS menu bar app that nudges you to check your work at a configurable
  interval — for people who don't already have that habit.
</div>

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
git clone <this-repo-url>
cd heartbeat
./scripts/build-app.sh
open dist/Heartbeat.app
```

## Installing the built app

Drag `dist/Heartbeat.app` to `/Applications`.

This build is **not notarized** by Apple. On first launch, macOS Gatekeeper
will warn that it's from an unidentified developer. To open it anyway:

1. Right-click (or Control-click) `Heartbeat.app` → **Open**.
2. Click **Open** in the dialog that appears.

(Alternative: System Settings → Privacy & Security → scroll down and click
**Open Anyway**.)

## Running tests

```bash
swift test
```

## License

MIT (or your preferred opensource license — replace this line).
