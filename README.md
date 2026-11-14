# Antigravity Quota

A lightweight, zero-dependency native macOS menu bar app that displays remaining **Google Antigravity** quotas for **Gemini** and **Third-Party (Claude & GPT)** models.

## Features

- **Menu Bar Indicators:** Displays two compact entries (`G` and `3P`) with selectable styles (`Rings + %`, `Rings`, or `Numbers`), metric selection (`Lowest`, `5-Hour`, or `Weekly`), and color-coded status (`green >= 50%`, `orange 20–49%`, `red < 20%`, or monochrome).
- **Expanded Popover:** Click the menu bar item to inspect full 5-hour and weekly quota bars, local reset countdowns, manual refresh (`⌘R`), configurable auto-refresh (`1m`, `5m`, `15m`, `30m`, `Off`), Launch at Login, custom `agy` CLI path override, and `Quit` (`⌘Q`).
- **Zero Extra Auth:** Uses your existing `agy` CLI login via `agy --print "/quota"` in the background — no external dependencies, OAuth tokens, or undocumented endpoints.

## Requirements

- macOS 14+
- Swift / Xcode Command Line Tools
- Antigravity CLI (`agy`) installed and authenticated

## Usage

```sh
# Build and launch the menu bar app
make run

# Build release app bundle at build/AntigravityQuota.app
make build

# Run unit tests
make test

# Regenerate Resources/AppIcon.icns from scripts/generate_icon.swift
make icon

# Optional: copy into /Applications (required by macOS for Launch at Login)
make install
```
