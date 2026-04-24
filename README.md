# Connecter

A macOS menu bar utility for managing SMB network share connections. Connecter mounts and monitors your network shares automatically, with smart retry logic and network-aware behavior.

## Features

- **Automatic mounting** — shares connect on launch and reconnect after network interruptions
- **Menu bar status** — at-a-glance connection state with per-share quick actions
- **Secure credentials** — passwords stored exclusively in macOS Keychain, never on disk
- **Smart retry** — exponential backoff (30s → 60s → 120s → 5min) with configurable auto-disable after repeated failures
- **Network-aware** — skips mount attempts when offline using `NWPathMonitor`
- **Custom mount points** — override the default `/Volumes` path per share
- **Launch at login** — via `SMAppService`
- **Activity log** — structured log of all mount/unmount/error events
- **Notifications** — optional macOS notifications for connection events

## Requirements

- macOS 26 (Tahoe) or later
- An Apple Developer account (for local builds)

## Building

1. Clone the repo
2. Open `connecter.xcodeproj` in Xcode
3. Set your development team in the project signing settings
4. Build and run (`⌘R`)

No external dependencies — only system frameworks (SwiftUI, AppKit, NetFS, ServiceManagement, Network, Security, UserNotifications).

> **Note:** App Sandbox is disabled to allow native NetFS mounting and custom mount paths.

## Architecture

```
connecterApp.swift       — @main, scene setup, AppDelegate
ContentView.swift        — main window, toolbar, share list
Managers/
  MountManager.swift     — mounting, monitoring, retry logic
  KeychainManager.swift  — secure credential storage
  LoginItemManager.swift — launch at login (SMAppService)
  NetworkMonitor.swift   — NWPathMonitor connectivity detection
  LogManager.swift       — structured activity logging
  NotificationManager.swift
Models/
  ShareConfig.swift      — share configuration + connection state
  AppSettings.swift      — user preferences (UserDefaults)
Views/
  MenuBar/               — menu bar extra and status items
  Shares/                — share list, cards, add/edit form
  Settings/              — preferences window
  Log/                   — activity log window
  Common/                — window sizing, styling utilities
```

## Privacy

- Passwords are stored in the macOS Keychain and never written to disk in plaintext
- No analytics, telemetry, or network requests (other than your configured SMB shares)
- No data leaves the device
