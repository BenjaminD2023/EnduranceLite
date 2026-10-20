# EnduranceLite

A macOS menu bar utility that stretches laptop battery life. Inspired by [Endurance](https://enduranceapp.com/) — not affiliated with Magnetism Studios.

EnduranceLite watches your charge and, when you hit a threshold you choose, turns on a low-power session: native macOS Low Power Mode, paused browsers, paused background services, sleeping energy-hungry apps, and hidden background windows. Display dimming is left to Apple's Low Power Mode.

## Features

| Measure | What it does |
|---|---|
| Slow Down Processor | Enables macOS Low Power Mode (Apple Silicon equivalent of disabling Turbo Boost). Asks for an administrator password once. |
| Pause Web Browsers | Pauses background browser helpers with `SIGSTOP`, including Dia's GPU, network and renderer processes. Browser main processes stay runnable so Dock and Command-Tab switching remain responsive. Switching back resumes the entire process family; a periodic check also recovers the frontmost family. Display wake resumes helpers before background pausing starts again. Raycast, Obsidian and shared system WebKit processes are excluded. |
| Pause Services | Pauses Photos analysis, updaters, cloud helpers, and similar background maintenance. |
| Monitor Expensive Apps | Watches CPU and sleeps apps that stay hot in the background. |
| Hide Background Apps | Hides apps that are not in front so macOS can throttle them. |
| Display Savings | Information about macOS Low Power Mode's automatic display savings. Brightness follows your macOS settings; this row has no separate toggle. |

Trigger: **Ask**, **Always**, **Never**, or **On Unplug**, at a battery percentage you pick (default 70%).

Lives in the menu bar. Opens a SwiftUI settings window (the original Endurance pane lives in System Settings; this app is a standalone window instead). Low Power Mode survives sleep, lid close, and unlock — status is restored instead of reset.

## Requirements

- Apple Silicon or Intel Mac, macOS 14 or later
- Apple Development signing identity (the project is set to team `45PVRUCTSQ`)

The app is **not sandboxed**. Pausing other processes and calling `pmset` cannot work inside the App Sandbox.

## Build and sign

```sh
./scripts/build-and-sign.sh
```

That produces a Release build, signs it with your local Apple Development identity, and copies it to `/Applications/EnduranceLite.app`.

Or open `EnduranceLite.xcodeproj` in Xcode and run.

Run all feature regression checks with `./scripts/test.sh`. They cover browser
and service process recovery, CPU monitoring, window restoration, battery
triggers and readings, settings persistence, and native battery policy restoration.
Pause tests use disposable child process trees; power and window tests use fake
providers, without changing your Mac's power settings or hiding your apps.

## Notes

- Native Low Power Mode needs root (`pmset`). The first time Slow Down Processor runs, macOS shows an administrator password dialog once. EnduranceLite installs a sudoers rule for `/usr/bin/pmset` only, so later toggles do not ask again. Uninstall removes that rule.
- Quitting normally resumes paused processes and restores hidden windows, while preserving the native Low Power Mode session for relaunch. A forced kill cannot run cleanup; stopped processes then need `SIGCONT` or a relaunch.
- Developer tools (Xcode, Cursor, Grok, Terminal, etc.) are never auto-slept.
- This is a personal-team signed build, not notarized. First launch from Finder may need Right Click → Open.
