# Coffeine

Coffeine is a macOS menu bar app that controls whether your Mac can sleep. In "Prevent Sleep" mode, the Mac stays awake even when you close the lid.

## Features

- **Prevent Sleep / Allow Sleep** (⌘S): blocks all system sleep, also when the lid is closed.
- **Keep Display On**: the display does not turn off when the Mac is idle.
- **Allow Sleep When Battery ≤ 15%**: a safety guard. When the Mac runs on battery and the charge drops to 15%, Coffeine restores normal sleep. This option is on by default.
- **Open at Login**: Coffeine starts automatically when you log in.
- **Remove pmset Permission…**: removes the sudoers rule that Coffeine installed.
- **Quit Coffeine**: Coffeine restores normal sleep when it quits.

The menu bar icon shows the state. A filled cup means that the Mac stays awake. An empty cup means normal sleep.

## Download

**[⬇ Download Coffeine.zip](https://github.com/jpetvaldsky/insomnimac/releases/latest/download/Coffeine.zip)** (universal: Apple Silicon and Intel, macOS 13+). All versions are on the [Releases](https://github.com/jpetvaldsky/insomnimac/releases) page.

1. Unzip the file and move `Coffeine.app` to `/Applications`.
2. Open `Coffeine.app`. The app is not notarized by Apple, so macOS blocks the first start.
3. Open **System Settings › Privacy & Security**, scroll down, and click **Open Anyway** next to the Coffeine message.

As an alternative to steps 2 and 3, remove the quarantine flag in Terminal:

```sh
xattr -dr com.apple.quarantine /Applications/Coffeine.app
```

If you do not trust a prebuilt binary, build the app yourself (see below).

## Requirements

- macOS 13 or later (Apple Silicon and Intel).
- Xcode 26 or later. The build uses `swiftc` and `actool`.
- An administrator account. Coffeine asks for the password once, the first time you prevent sleep.

## Build and install

```sh
./build.sh            # builds build/Coffeine.app and build/Coffeine.zip
./build.sh --install  # builds the app, copies it to /Applications, and starts it
```

If `actool` reports "A required plugin failed to load", run `xcodebuild -runFirstLaunch`.

## How it works

Common tools (`caffeinate`, IOPM assertions) block only idle sleep. They do not block sleep when the lid is closed. Coffeine therefore uses `pmset -a disablesleep 1`.

`pmset` needs root privileges. The first time you prevent sleep, Coffeine asks for an administrator password. Then it installs `/etc/sudoers.d/coffeine`. This file lets the current user run only these two commands without a password:

```
/usr/bin/pmset -a disablesleep 0
/usr/bin/pmset -a disablesleep 1
```

Coffeine also creates an IOPM assertion against idle sleep. When "Keep Display On" is on, it also creates an assertion for the display.

Coffeine saves the last state and restores it after a restart.

## Do the same in Terminal (without the app)

Coffeine does not use any hidden magic. It is a menu bar switch for built-in macOS commands. You can run the same commands yourself in Terminal.

**Prevent all sleep, also with the lid closed:**

```sh
sudo pmset -a disablesleep 1
```

**Allow sleep again:**

```sh
sudo pmset -a disablesleep 0
```

Important: `disablesleep` does not turn off when you close Terminal. The Mac stays awake until you run `sudo pmset -a disablesleep 0`.

**Keep the display on** (equivalent of "Keep Display On"). Stop it with Ctrl+C:

```sh
caffeinate -d
```

**Block only idle sleep** (closing the lid still puts the Mac to sleep). Stop it with Ctrl+C:

```sh
caffeinate -i
```

**Check the battery level** (Coffeine does this every 60 seconds for the battery guard):

```sh
pmset -g batt
```

### What the app adds to these commands

| Coffeine menu item | Terminal equivalent | What the app adds |
|---|---|---|
| Prevent Sleep / Allow Sleep | `sudo pmset -a disablesleep 1` / `0` | No password after the first setup, and a visible state in the menu bar |
| Keep Display On | `caffeinate -d` | Runs in the background, no open Terminal window |
| Allow Sleep When Battery ≤ 15% | `pmset -g batt` (manual check) | Checks automatically and allows sleep again at 15% |
| Quit Coffeine | `sudo pmset -a disablesleep 0` | Restores normal sleep automatically when the app quits |
| Open at Login | none | Starts the app and restores the last state after a restart |

## Check the state

```sh
pmset -g | grep SleepDisabled   # "SleepDisabled 1" means that sleep is prevented
```

## Warnings

- If Coffeine crashes or is force-quit, the Mac stays in the "prevent sleep" state. Start Coffeine again, or run `sudo pmset -a disablesleep 0`.
- A closed Mac that does not sleep can overheat in a bag.

## Uninstall

1. In the Coffeine menu, select "Remove pmset Permission…".
2. Quit Coffeine.
3. Delete `/Applications/Coffeine.app`.

## Project structure

| File | Purpose |
|---|---|
| `Sources/main.swift` | The complete app (AppKit, IOKit, ServiceManagement) |
| `Info.plist` | App metadata, `LSUIElement` (no Dock icon) |
| `CoffeeeCup.icon` | App icon made with Icon Composer |
| `build.sh` | Build and install script |
