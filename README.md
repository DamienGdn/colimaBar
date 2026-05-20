# ColimaBar

macOS menu bar app to manage [Colima](https://github.com/abiosoft/colima) + [Portainer](https://www.portainer.io/) — a lightweight Docker Desktop alternative.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1%2FM2%2FM3-green)

## Features

- **Start / Stop Colima** from the menu bar
- **Colored icon** — green (running), yellow (starting/stopping), grey (stopped)
- **CPU & Memory display** — shows allocated resources
- **Portainer integration** — auto-opens after Colima starts, installs Portainer if missing
- **CPU / Memory configuration** — presets submenu, restarts Colima with new values
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
| Start Colima | Click icon → ▶ Démarrer Colima |
| Stop Colima | Click icon → ■ Arrêter Colima |
| Open Portainer | Click icon → Ouvrir Portainer |
| Install Portainer | Click icon → Installer Portainer… (shown when missing) |
| Change CPU/Memory | Click icon → ⚙ Configuration → pick preset |
| Launch at login | Click icon → Lancer au démarrage |

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

If you lose your Portainer admin password:

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
├── ColimaBarCore/     # Pure Foundation library (testable)
│   ├── ShellRunner.swift    # Process execution abstraction
│   ├── ColimaState.swift    # State model
│   ├── ColimaManager.swift  # Polling, start/stop/install actions
│   └── ColimaConfig.swift   # CPU/memory preferences (UserDefaults)
└── ColimaBar/         # AppKit executable
    ├── main.swift           # NSApplication entry point
    ├── AppDelegate.swift    # App lifecycle, SMAppService, notifications
    └── StatusBarController.swift  # NSStatusItem, menu, icon
Tests/
└── ColimaBarTests/    # Custom test runner (no Xcode required)
```
