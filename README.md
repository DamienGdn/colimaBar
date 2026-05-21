# ColimaBar

<p align="center">
  <img src="docs/icon.png" width="128" alt="ColimaBar icon" />
</p>

<p align="center">
  macOS menu bar app to manage <a href="https://github.com/abiosoft/colima">Colima</a> + <a href="https://www.portainer.io/">Portainer</a> — a lightweight Docker Desktop alternative.
</p>

<p align="center">
  <img src="docs/screenshot.png" width="320" alt="ColimaBar menu screenshot" />
</p>

<p align="center">
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-blue" />
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-M1%2FM2%2FM3-green" />
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.9-orange" />
</p>

---

## Features

- **Start / Stop Colima** from the menu bar — stops automatically when you quit the app
- **Colored icon** — green (running), yellow (starting/stopping), grey (stopped)
- **Real-time CPU & RAM usage** — live stats from all running containers
- **Portainer integration** — auto-opens after Colima starts, installs Portainer if missing
- **CPU / Memory configuration** — presets submenu, restarts Colima with new values
- **French / English** — follows system language, manual toggle in Configuration
- **Launch at login** — toggle from the menu (app only, Colima starts manually)
- **Error notifications** — system alerts on failures

## Requirements

- macOS 13 (Ventura) or later
- Apple Silicon Mac (M1/M2/M3)
- Xcode Command Line Tools
- Homebrew with `colima` and `docker`

## Install

```bash
# 1. Install dependencies
brew install colima docker

# 2. Clone and build
git clone git@github.com:DamienGdn/colimaBar.git
cd colimaBar
make install

# 3. Launch
open /Applications/ColimaBar.app
```

> **Gatekeeper warning:** The app is ad-hoc signed. Right-click → Open → Open anyway on first launch.

## Usage

| Action | How |
|--------|-----|
| Start Colima | Click icon → ▶ Start Colima |
| Stop Colima | Click icon → ■ Stop Colima |
| Open Portainer | Click icon → Open Portainer |
| Install Portainer | Click icon → Install Portainer… (shown when missing) |
| Change CPU/Memory | Click icon → ⚙ Configuration → pick preset |
| Change language | Click icon → ⚙ Configuration → Language |
| Launch at login | Click icon → Launch at login |

Portainer runs at **https://localhost:9443** (accept self-signed certificate on first visit).

## Build commands

```bash
make build    # compile release binary
make bundle   # create ColimaBar.app
make install  # bundle + install to /Applications
make clean    # remove build artifacts
```

## Run tests

```bash
swift run ColimaBarTests
```

## Rebuild after changes

```bash
make install && open /Applications/ColimaBar.app
```

## Reset Portainer credentials

```bash
docker rm portainer
docker volume rm portainer_data
docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data portainer/portainer-ce:latest
```

Open https://localhost:9443 to create a new admin account.

## Architecture

```
Sources/
├── ColimaBarCore/          # Pure Foundation library (testable)
│   ├── ShellRunner.swift        # Process execution + Homebrew PATH injection
│   ├── ColimaState.swift        # State model + ResourceUsage
│   ├── ColimaManager.swift      # Polling, start/stop/install actions
│   ├── ColimaConfig.swift       # CPU/memory preferences (UserDefaults)
│   └── Localization.swift       # FR/EN strings + language preference
└── ColimaBar/              # AppKit executable
    ├── main.swift               # NSApplication entry point
    ├── AppDelegate.swift        # App lifecycle, SMAppService, notifications
    └── StatusBarController.swift # NSStatusItem, menu, icon tinting
Tests/
└── ColimaBarTests/         # Custom test runner (no Xcode required)
Resources/
├── Info.plist              # LSUIElement=true, bundle metadata
├── AppIcon.icns            # App icon (all sizes)
├── colimabar.png           # Menu bar icon @1x
└── colimabar@2x.png        # Menu bar icon @2x
```
