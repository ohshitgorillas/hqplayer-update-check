# hqplayer-update-check

Systemd timer that polls [Signalyst](https://signalyst.com) for new releases of **HQPlayer Embedded** and **NAA (Network Audio Adapter)**. Exposes Prometheus metrics via node-exporter's textfile collector; Alertmanager fires on new versions.

## What it does

**HQPlayer Embedded** — scrapes `signalyst.eu/bins/hqplayerd/noble/` for the latest Intel-optimized `.deb`, compares against the installed `hqplayerd` package, and downloads to `~/hqplayer-downloads/` if newer. Does not auto-install or restart — install manually when not playing (see alert description).

**NAA** — polls the Signalyst NAA RSS feed. Baselines to current latest on first run. Fires once per new release, then auto-advances the baseline.

## Requirements

- Ubuntu 24.04 (Noble) — targets the `noble` package directory
- `hqplayerd` installed via `.deb`
- `curl`, `python3` (stdlib only)
- [Prometheus node-exporter](https://github.com/prometheus/node_exporter) with textfile collector enabled
- Prometheus
- Alertmanager (optional, for notifications)

## Install

```bash
sudo bash setup.sh
```

Installs the script to `/usr/local/bin/`, enables the systemd timer, runs an initial check, and restarts node-exporter with `--collector.textfile.directory` pointed at `/var/lib/node_exporter/textfile_collector/`.

## node-exporter config

Add to your node-exporter `command:` block (assumes `/` mounted as `/rootfs:ro`, which is standard for Docker deployments):

```yaml
- '--collector.textfile.directory=/rootfs/var/lib/node_exporter/textfile_collector'
```

## Prometheus alert rules

```yaml
- name: hqplayer
  rules:
  - alert: HQPlayerUpdateAvailable
    expr: hqplayer_update_available == 1
    labels:
      severity: info
    annotations:
      summary: "HQPlayer Embedded update ready on {{ $labels.instance }}"
      description: "v{{ $labels.latest }} downloaded to ~/hqplayer-downloads/ (installed: {{ $labels.installed }}). Install when not playing: sudo dpkg -i ~/hqplayer-downloads/hqplayerd_{{ $labels.latest }}_amd64.deb && sudo systemctl restart hqplayerd"

  - alert: HQPlayerDownloadFailed
    expr: hqplayer_update_check_success == 0 and hqplayer_update_available == 1
    for: 1h
    labels:
      severity: warning
    annotations:
      summary: "HQPlayer update download failed on {{ $labels.instance }}"
      description: "New version {{ $labels.latest }} found but download failed. Check: journalctl -u hqplayer-update-check"

  - alert: HQPlayerUpdateCheckFailed
    expr: hqplayer_update_check_success == 0
    for: 24h
    labels:
      severity: warning
    annotations:
      summary: "HQPlayer update check failing on {{ $labels.instance }}"
      description: "Check: systemctl status hqplayer-update-check.timer && journalctl -u hqplayer-update-check"

  - alert: NAAReleaseAvailable
    expr: naa_update_available == 1
    labels:
      severity: info
    annotations:
      summary: "NAA update available: v{{ $labels.latest }}"
      description: "New NAA v{{ $labels.latest }} on signalyst.com. Update NAA endpoints."

  - alert: NAAUpdateCheckFailed
    expr: naa_update_check_success == 0
    for: 24h
    labels:
      severity: warning
    annotations:
      summary: "NAA update check failing on {{ $labels.instance }}"
      description: "Check: systemctl status hqplayer-update-check.timer && journalctl -u hqplayer-update-check"
```

## Metrics

| Metric | Description |
|--------|-------------|
| `hqplayer_update_available` | 1 = new `.deb` in `~/hqplayer-downloads/`, awaiting install |
| `hqplayer_update_check_success` | 0 = scrape or download failed |
| `naa_update_available` | 1 = new NAA release detected (clears next run) |
| `naa_update_check_success` | 0 = RSS fetch failed |

## State files

| Path | Purpose |
|------|---------|
| `/etc/hqplayer-update-check/naa_known_version` | Last seen NAA version (auto-updated on each new release) |
| `/var/lib/node_exporter/textfile_collector/hqplayer_update.prom` | Prometheus metrics output |

## Timer

Runs 5 minutes after boot, then every 6 hours (±10 min random delay).

```bash
systemctl status hqplayer-update-check.timer
journalctl -u hqplayer-update-check
```
