# TheaterNAS Control Center

A production-quality, ANSI-based terminal dashboard for homelab and NAS management. Built entirely in Bash for Debian 13 — no Python, no Node.js, no web UI.

Designed for servers where Docker takes minutes to respond. A background cache daemon collects all slow metrics; the dashboard **never blocks** waiting on Docker.

```
+-------------------------------------------------------------+
|                 THEATERNAS CONTROL CENTER                   |
+-------------------------------------------------------------+
| CPU 12% RAM 32% GPU 4% Docker ✓ Pi-hole ✓ Plex ✓            |
+-------------------------------------------------------------+
| > System             Hostname: TheaterNAS                   |
|   Docker             Uptime: 12 days                        |
|   Network            Containers: 26                         |
|   Media              GPU Temp: 43°C                         |
|   Storage            LAN: 192.168.x.x                       |
|   Logs               Tailscale: 100.x.x.x                   |
|   Settings           Root Usage: 58%                        |
+-------------------------------------------------------------+
| Enter Open    Q Quit    R Refresh    S Screensaver          |
+-------------------------------------------------------------+
```

## Features

- **Modular architecture** — separate modules for System, Docker, Network, GPU, Media, Storage, Logs, Quick Actions, Settings
- **Cache daemon** — systemd service collects metrics in the background every 30s (configurable)
- **Never hangs on Docker** — all Docker/Pi-hole data read from cache files
- **Themes** — Default, Cyberpunk, Matrix, Ocean, Retro (easy to add more)
- **Pi-hole v6 API** — query stats, logs, container status
- **Plex** — sessions, transcodes, logs
- **NVIDIA GPU** — full monitoring and maintenance submenu
- **Tailscale & WireGuard** — VPN status from Docker or host
- **SMART storage** — health, temperatures, SSD wear
- **Screensaver** — animated ANSI starfield
- **100% configurable** — all settings in `config/config.conf`

## Quick Install

### One-liner (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/AKASGaming/homelab-dashboard/main/remote-install.sh | sudo bash
```

### Manual install

```bash
git clone https://github.com/AKASGaming/homelab-dashboard.git
cd homelab-dashboard
sudo ./install.sh
```

### Launch

```bash
main-menu
```

## Requirements

- Debian 13 (or Debian 12/Ubuntu with minor adjustments)
- Bash 4+
- `jq` (installed automatically)
- SSH terminal with ANSI color support
- Optional: `docker`, `nvidia-smi`, `smartctl`, `speedtest` or `speedtest-cli`

## Configuration

All settings are in `/opt/homelab-dashboard/config/config.conf`:

```bash
# Container names
PIHOLE_CONTAINER="pihole"
PLEX_CONTAINER="plex"
TAILSCALE_CONTAINER="tailscale"

# Pi-hole v6 API
PIHOLE_API_URL="http://127.0.0.1"
PIHOLE_API_PASSWORD="your-password"

# Theme
THEME="cyberpunk"

# Cache interval (seconds)
CACHE_INTERVAL=30

# Quick action containers
QUICK_ACTION_CONTAINERS="pihole,plex,tailscale"
```

No code changes required — edit config and restart the cache daemon:

```bash
sudo systemctl restart homelab-dashboard-cache
```

## Commands

| Command | Description |
|---------|-------------|
| `main-menu` | Launch the dashboard |
| `update-dashboard` | Update code, preserve config |
| `uninstall-dashboard` | Remove installation |
| `systemctl status homelab-dashboard-cache` | Cache daemon status |

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| ↑/↓ | Navigate menu |
| Enter | Open selected module |
| Q | Quit |
| R | Refresh display |
| S | Screensaver |
| B | Back (in sub-menus) |

## Themes

Available themes in `/opt/homelab-dashboard/themes/`:

- `default` — Professional blue
- `cyberpunk` — Neon magenta/cyan
- `matrix` — Green terminal
- `ocean` — Deep blue/teal
- `retro` — Amber nostalgia

Change in config or via Settings → Theme Selector.

To add a theme, create `themes/mytheme.theme`:

```bash
THEME_NAME="My Theme"
COLOR_HEADER="39"
COLOR_BORDER="24"
# ... see existing themes for all COLOR_* variables
```

## Architecture

```
/opt/homelab-dashboard/
├── main-menu              # Dashboard entry point
├── config/config.conf     # All user settings
├── cache/                 # JSON cache files (daemon writes, UI reads)
├── modules/
│   ├── ui.sh              # ANSI UI framework
│   ├── cache-daemon.sh    # Background collector
│   ├── system.sh          # System info module
│   ├── docker.sh          # Docker module (cache-only)
│   ├── network.sh         # Network diagnostics
│   ├── gpu.sh             # NVIDIA GPU
│   ├── media.sh           # Pi-hole & Plex
│   ├── storage.sh         # SMART & disks
│   ├── logs.sh            # Log viewer
│   ├── quickactions.sh    # Quick actions
│   ├── settings.sh        # Settings
│   └── screensaver.sh     # Starfield screensaver
└── themes/                # Color themes
```

### Cache Daemon

The cache daemon (`homelab-dashboard-cache.service`) runs every `CACHE_INTERVAL` seconds and collects:

- System (CPU, RAM, uptime, filesystem)
- Docker (containers, networks, volumes, images, stats)
- GPU (nvidia-smi)
- Network (IPs, routes, latency)
- Tailscale & WireGuard
- Media (Pi-hole v6 API, Plex)
- Storage (SMART, largest directories)
- Speedtest (every 10th cycle)

The dashboard UI **only reads** `/opt/homelab-dashboard/cache/*.json`.

## Updating

```bash
sudo update-dashboard
```

Or from a local clone:

```bash
sudo update-dashboard /path/to/homelab-dashboard
```

## Uninstalling

```bash
sudo uninstall-dashboard
```

Optionally keeps a config backup at `/etc/homelab-dashboard-config.conf.removed`.

## License

MIT License — see LICENSE file.

## Author

Built for TheaterNAS homelab infrastructure.
