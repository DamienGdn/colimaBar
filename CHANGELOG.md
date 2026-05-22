# Changelog

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
