# Connecter

A macOS menu bar utility for managing SMB network share connections. Connecter mounts and monitors your network shares automatically, with smart retry logic and network-aware behavior.

## Features

- **Automatic mounting** — shares connect on launch and reconnect after sleep, network changes and interruptions
- **Menu bar status** — at-a-glance connection state with per-share quick actions
- **Secure credentials** — passwords stored exclusively in the macOS Keychain, never on disk; the share list can be rebuilt from the Keychain (“Recover from Keychain”)
- **Smart retry** — exponential backoff (×2, ×4, then 5 min) with configurable auto-disable after repeated failures, and a notification when a share is switched off
- **Network-aware** — pauses checks while offline (`NWPathMonitor`) and re-checks every share as soon as connectivity returns
- **Server-aware** — probes the SMB port before every mount attempt, so an unreachable NAS costs nothing (no NetFS calls, no failure count) and shares come back within one check interval of the server returning
- **Stable mount points** — reuses a stale `/Volumes/<share>` left by an interrupted mount instead of ending up at `/Volumes/<share>-1`, so saved paths keep working
- **Launch at login** — via `SMAppService`, off by default
- **Activity log** — filterable log of all mount/unmount/error events, also written to a rotating file
- **Notifications** — optional macOS notifications for connection events
- **Localized** — English, Spanish, German, French, Italian, Brazilian Portuguese, Japanese and Simplified Chinese (String Catalog)

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
Localizable.xcstrings    — String Catalog (en, es, de, fr, it, ja, pt-BR, zh-Hans)
PrivacyInfo.xcprivacy    — privacy manifest
```

## Where data lives

| Data | Location |
|---|---|
| Share list and settings | `UserDefaults` (`es.guzman.connecter`), inside the app container when sandboxed |
| Passwords | Keychain internet-password items (protocol SMB, security domain `es.guzman.connecter`) whose attributes carry host, share path, user name and display name |
| Activity log | `Library/Logs/Connecter/connecter.log` |

Every share gets a Keychain item at launch and whenever it is saved (the secret is empty for shares that rely on a password saved by Finder), so **Settings → Keychain** lists what is stored and **Recover** rebuilds the list — for example after moving to the sandboxed build, whose container starts empty. Items are created as synchronizable so that, once the app is signed with the Keychain Sharing capability, they also follow the user to other Macs through iCloud Keychain; without that entitlement macOS refuses synchronizable items (`errSecMissingEntitlement`) and Connecter stores them locally.

## Privacy

- Passwords are stored in the macOS Keychain and never written to disk in plaintext
- No analytics, telemetry, or network requests (other than your configured SMB shares)
- No data leaves the device

## Feedback

Bug reports, questions and ideas are welcome, in English or Spanish:

| I want to… | Where |
|---|---|
| Report something that doesn't work | [New issue → Bug report](https://github.com/arcester/connecter/issues/new/choose) |
| Suggest a feature or vote on ideas | [Discussions → Ideas](https://github.com/arcester/connecter/discussions/categories/ideas) |
| Ask how something works | [Discussions → Q&A](https://github.com/arcester/connecter/discussions/categories/q-a) |
| Report a security problem | Privately, see [SECURITY.md](SECURITY.md) |

> **Before posting:** this repository is public. Remove passwords, user names, server names, IP addresses and Tailscale or VPN host names from anything you paste, including activity log entries.

## License

Connecter is open source under the [Apache License 2.0](LICENSE). You may use, modify and redistribute the code under its terms, which include keeping the copyright notice and the [NOTICE](NOTICE) file.

### Name and icon

The license covers the source code only, not the name “Connecter” or the app icon. If you publish your own build or a fork, please give it a different name and icon so it isn't mistaken for the official app.
