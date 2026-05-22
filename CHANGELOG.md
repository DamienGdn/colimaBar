# Changelog

## v1.9.0 — 2026-05-22

### New features

- **In-app logs viewer** — floating NSWindow (no Terminal needed): streams `docker logs -f`, follow/stop toggle, clear button, 5 000-line cap, dark background monospace display
- **Networks tab** — new 5th tab in the containers panel: lists Docker networks with driver and scope; "Prune networks" button removes unused ones
- **Compose tab** — groups containers by their Docker Compose project (derived from `com.docker.compose.project` label); shows project name, container count, and status (All running / Stopped / N/M running)
- **Polling interval presets** — Settings: choose Rapide (2 s / 10 s), Normal (5 s / 30 s default), or Lent (15 s / 60 s); takes effect on next poll cycle
- **Compact mode** — Settings: show running container count next to the icon in the menu bar (`▶ N`)
- **Disk resize** — Settings: "Resize disk…" button (enabled when Colima is running) triggers a restart with the configured disk size
- **Resource alerts** — system notification when CPU > 80 % or RAM > 90 % for 2 consecutive polling cycles
- **Multi-instance switcher** — "Instance" submenu in the menu bar: switch between Colima instances with a checkmark on the active one

---

## v1.8.0 — 2026-05-22

### New features

- **Context menu** — right-click any container row: start/stop/restart, logs, shell, copy ID, open port(s), filter by image, change restart policy, inspect
- **Restart policy column** — shows each container's restart policy (↺ always / ⚠ on-fail / ◎ unless / —); change via context menu → `docker update --restart`
- **Custom exec command** — Shell button prompts for the command before opening Terminal (default `sh`)
- **Environment variables** — new "Env" button opens a popover with all KEY=VALUE env vars; copy-all button
- **Quick filter by image** — context menu → "Filter by this image" instantly filters the list

### Improvements

- Search field now matches both container name and image name
- Volumes tab: "Containers" column shows which containers use each volume

---

## v1.7.0 — 2026-05-22

### New features

- **Clickable port URLs** — each port number in the containers panel is a link; click opens `http://localhost:PORT` in the default browser
- **CPU/RAM sparklines** — mini area chart (up to 20 data points) shown below the table when a running container is selected
- **Image management tab** — new "Images" tab in the panel: lists all Docker images with repository, tag, size and creation date; pull new images by name; delete existing images with confirmation
- **Volume management tab** — new "Volumes" tab: lists all Docker volumes with size and associated containers; prune unused volumes with confirmation

### Improvements

- **Container selection preserved** — polling refreshes no longer deselect the current row
- Containers panel height increased to 560 px to accommodate the sparkline zone

### Bug fixes

- Pull button / spinner no longer get stuck if the image callback is not wired
- Stale CPU/RAM labels cleared when switching to a container with no stats yet

---

## v1.6.0

- Sortable columns (name / ports / CPU / RAM) + global RAM% in header
- Containers popover widened to 900 px

## v1.5.0

- RAM% added to menu status line
- Portainer auto-start removed on Colima start

## v1.4.0

- Settings popover replaces Configuration submenu
- Profiles: Minimal / Dev / Heavy
- CPU / Memory / Disk fine-tuning
- Named Colima instances
- Auto-start Colima on launch

## v1.3.0

- Per-container CPU & RAM live stats
- Real-time aggregate CPU & RAM in panel header
- Container search
- All / Running filter (persisted)

## v1.2.0

- Containers panel (NSPopover) with table view
- Container actions: Start / Stop / Restart / Logs / Shell
- Copy container ID
- Exposed ports column

## v1.1.0

- Portainer integration (auto-install, auto-start)
- docker system prune with confirmation
- Colima update detection via brew

## v1.0.0

- Initial release
- Start / Stop Colima from menu bar
- Colored status icon (green / orange / white)
- Lifecycle notifications
- Crash detection
- French / English localization
- Launch at login
