# Connecter

A macOS menu bar utility for managing SMB network share connections. Connecter mounts and monitors your network shares automatically, with smart retry logic and network-aware behavior.

## Features

- **Automatic mounting** — shares connect on launch and reconnect after sleep, network changes and interruptions
- **Menu bar status** — at-a-glance connection state with per-share quick actions
- **Secure credentials** — passwords stored exclusively in the macOS Keychain, never on disk
- **Smart retry** — exponential backoff (×2, ×4, then 5 min) with configurable auto-disable after repeated failures, and a notification when a share is switched off
- **Network-aware** — pauses checks while offline (`NWPathMonitor`) and re-checks every share as soon as connectivity returns
- **Launch at login** — via `SMAppService`, off by default
- **Activity log** — filterable log of all mount/unmount/error events, also written to a rotating file
- **Notifications** — optional macOS notifications for connection events
- **Localized** — English and Spanish (String Catalog)

## Requirements

- macOS 26 (Tahoe) or later
- Xcode 26 or later and an Apple Developer account for signed builds

## Building

1. Clone the repo
2. Open `connecter.xcodeproj` in Xcode
3. Set your development team in the project signing settings
4. Build and run (`⌘R`)

No external dependencies — only system frameworks (SwiftUI, AppKit, NetFS, ServiceManagement, Network, Security, UserNotifications).

## App Sandbox and distribution

The app runs inside the App Sandbox with the `network.client` entitlement, as required by the Mac App Store. Everything the app needs works there:

| Capability | How it is done |
|---|---|
| Mounting | `NetFSMountURLAsync` (the mount is performed by macOS's NetAuth agent) |
| Unmounting | `FileManager.unmountVolume(at:)` via Disk Arbitration |
| Port check | Non-blocking BSD socket (`PortProbe`), no external processes |
| Mount detection | `mountedVolumeURLs` + `volumeURLForRemountingKey` |
| Open in Finder | The share's `smb://` URL is handed to Finder |
| Log file | `Library/Logs/Connecter/` inside the app container |

One thing a sandboxed process cannot do is signal other processes. On macOS 27 the system's NetAuth agent can stop answering mount requests; a non-sandboxed build restarts it automatically, whereas the sandboxed build shows the user how to do it (`killall NetAuthSysAgent NetAuthAgent`) and retries afterwards. `AppEnvironment.isSandboxed` selects the behavior at runtime, so the same code base can also be shipped outside the store with Developer ID signing and the sandbox turned off.

See [docs/app-store-checklist.md](docs/app-store-checklist.md) for the submission checklist.

## Architecture

```
connecterApp.swift       — @main, scene setup, AppDelegate
ContentView.swift        — main window, toolbar, share list, NetAuth recovery
Managers/
  MountManager.swift     — mounting, monitoring, retry logic, NetAuth diagnosis
  PortProbe.swift        — sandbox-safe TCP port check
  KeychainManager.swift  — secure credential storage
  LoginItemManager.swift — launch at login (SMAppService)
  NetworkMonitor.swift   — NWPathMonitor connectivity detection
  LogManager.swift       — structured activity logging (memory + rotating file)
  NotificationManager.swift
Models/
  ShareConfig.swift      — share configuration + connection state
  AppSettings.swift      — user preferences (UserDefaults)
  AppEnvironment.swift   — sandbox detection, version info
Views/
  MenuBar/               — menu bar extra and status items
  Shares/                — share list, cards, add/edit form
  Settings/              — preferences window
  Log/                   — activity log window
  Common/                — window sizing, styling utilities
Localizable.xcstrings    — String Catalog (en, es)
PrivacyInfo.xcprivacy    — privacy manifest
```

## Privacy

- Passwords are stored in the macOS Keychain and never written to disk in plaintext
- No analytics, telemetry, or network requests (other than your configured SMB shares)
- No data leaves the device
