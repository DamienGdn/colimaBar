# ColimaBar

![ColimaBar icon](docs/icon.png)

macOS menu bar app to manage [Colima](https://github.com/abiosoft/colima) + [Portainer](https://www.portainer.io/) — a lightweight Docker Desktop alternative.

![Screenshot](docs/screenshot.png)

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1%2FM2%2FM3-green) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

---

## Features

- **Start / Stop Colima** — stops automatically when you quit the app
- **Adaptive polling** — 5 s refresh when running, 30 s when stopped
- **Colored icon** — green bubble (running), orange (starting/stopping), white (stopped)
- **Boot summary notification** — "Colima started in 12s — 5 container(s) running"
- **Stop notification** — confirmation when Colima shuts down
- **Last error in menu** — `⚠ error message` visible directly in menu, clears on next success
- **Containers panel** — rich popover with table view (state, name, image, status columns), opens anchored to the menu bar icon
- **Container actions** — Start / Stop / Restart / Logs buttons per selected container
- **Container filter** — toggle All / Running only (segmented control, persisted)
- **Copy container ID** — one click copies the full container ID to clipboard
- **Quick logs** — click a container → Logs → Terminal opens with `docker logs -f`
- **Real-time CPU & RAM usage** — live aggregate stats from all running containers
- **Portainer integration** — auto-opens after Colima starts, installs if missing
- **Profiles** — Minimal (1 CPU / 2 GB), Dev (2 CPU / 4 GB), Heavy (4 CPU / 8 GB)
- **CPU / Memory fine-tuning** — individual presets beyond profiles
- **Auto-start Colima** — optional: start Colima automatically when the app launches
- **Colima update detection** — `🔄 Colima X.Y.Z update available` when brew has a newer version
- **French / English** — follows system language, manual toggle in Configuration
- **Launch at login** — app only, Colima auto-start is a separate opt-in setting

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
| View containers | Click icon → N/M containers → (opens panel) |
| Filter containers | Panel → All / Running toggle |
| Start/stop a container | Panel → select container → Start or Stop |
| Restart a container | Panel → select container → Restart |
| Copy container ID | Panel → select container → Copy ID |
| View container logs | Panel → select container → Logs |
| Open Portainer | Click icon → Open Portainer |
| Install Portainer | Click icon → Install Portainer… (shown when missing) |
| Apply a profile | Click icon → ⚙ Configuration → Profiles → Minimal / Dev / Heavy |
| Change CPU/Memory | Click icon → ⚙ Configuration → CPUs or Memory |
| Auto-start Colima | Click icon → ⚙ Configuration → Auto-start Colima on launch |
| Change language | Click icon → ⚙ Configuration → Language |
| Upgrade Colima | Click icon → 🔄 update item (shown when available) |
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
├── ColimaBarCore/               # Pure Foundation library (testable)
│   ├── ShellRunner.swift        # Process execution + Homebrew PATH injection
│   ├── ColimaState.swift        # State model + ResourceUsage + DockerContainer
│   ├── DockerContainer.swift    # Docker container model + JSON parser
│   ├── ColimaManager.swift      # Polling, start/stop/install, container commands, update check
│   ├── ColimaConfig.swift       # CPU/memory preferences + ColimaProfile presets
│   └── Localization.swift       # FR/EN strings + language preference
└── ColimaBar/                   # AppKit executable
    ├── main.swift               # NSApplication entry point
    ├── AppDelegate.swift        # App lifecycle, SMAppService, notifications, update check trigger
    ├── StatusBarController.swift # NSStatusItem, menu, icon tinting, containers, profiles
    └── ContainersPanelViewController.swift # NSPopover panel with NSTableView for containers
Tests/
└── ColimaBarTests/              # Custom test runner (no Xcode required) — 49 tests
Resources/
├── Info.plist                   # LSUIElement=true, bundle metadata
├── AppIcon.icns                 # App icon (all sizes)
├── colimabar.png                # Menu bar icon @1x
└── colimabar@2x.png             # Menu bar icon @2x
```
