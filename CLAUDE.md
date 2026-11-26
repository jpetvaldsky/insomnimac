# CLAUDE.md

## Project

Coffeine is a macOS menu bar app (AppKit, no Xcode project). It controls whether the Mac can sleep. The "prevent sleep" mode also blocks sleep when the lid is closed.

## Build

- `./build.sh` builds a universal (arm64 + x86_64) `build/Coffeine.app` with `swiftc` and ad-hoc signs it.
- `./build.sh --install` also kills the running app, copies the app to `/Applications`, refreshes LaunchServices, and starts it.
- `actool` compiles `CoffeeeCup.icon` (Icon Composer) into `Assets.car` and `CoffeeeCup.icns`. If `actool` fails with "A required plugin failed to load", run `xcodebuild -runFirstLaunch`.
- Deployment target: macOS 13.0 (needed for `SMAppService`).
- There are no tests. Verify changes manually: build, install, use the menu, then check `pmset -g | grep SleepDisabled`.

## Architecture (`Sources/main.swift`)

- `Power`: wraps `pmset`, the sudoers helper, and battery queries (IOKit.ps).
  - Hard mode: `sudo -n /usr/bin/pmset -a disablesleep 0|1`. Only this blocks lid-close sleep.
  - The sudoers rule `/etc/sudoers.d/coffeine` allows exactly these two commands for the current user. The app installs it once with `NSAppleScript` "with administrator privileges" and validates it with `visudo -cf`.
- `Assertion`: soft layer with IOPM assertions (`PreventUserIdleSystemSleep`, `PreventUserIdleDisplaySleep`).
- `AppDelegate`: status item, menu (rebuilt in `menuNeedsUpdate`), settings in `UserDefaults`, battery guard timer (60 s, limit 15 %), login item with `SMAppService.mainApp`.

## Rules

- The app must never leave `disablesleep 1` active when it quits. Keep the reset in `applicationWillTerminate`.
- Keep the sudoers rule as narrow as it is now. Do not allow arbitrary `pmset` arguments.
- UI strings are in Czech. Code and comments are in English.
- `LSUIElement` is `true`. The app has no Dock icon and no main window.

## Known issues

- System Settings › Login Items can show a stale generic icon after the app icon changes. Toggle "Spouštět při přihlášení" off and on, then reopen System Settings. Do not run `sfltool resetbtm`, because it resets all login item approvals.
