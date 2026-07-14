# Changelog

## 2026-05-29

### Changed
- `BINS_URL` now derives the Fedora release from `rpm -E %fedora` instead of a hardcoded `fc43`. The bins dir tracks the running release automatically across distro upgrades; no edit needed on each bump.

### Added
- Distribution-bump detection: lists the bins root, takes the highest `fcNN` dir, and emits `hqplayer_distro_bump_available{running,latest}` (1 when signalyst publishes for a newer Fedora than the running release) plus `hqplayer_distro_check_success`.
- `file` label on `hqplayer_update_available` carrying the exact RPM filename, so the install-command alert no longer hardcodes the dist tag.

## 2026-05-09

### Fixed
- Version regex now accepts decimal RPM release tags (e.g. `5.17.2-48.1.fc43`). Previously required integer release, causing `hqplayer_update_check_success=0` when upstream bumped the dist release format.

## 2026-04-24

### Added
- Initial HQPlayer Embedded update checker with RPM auto-download to `~/hqplayer-downloads` and NAA RSS check.
- HQPlayer Desktop update check (RSS-based) with `desktop_update_available` and `desktop_update_check_success` metrics.
- README with Prometheus alert examples for Embedded, NAA, and Desktop.
