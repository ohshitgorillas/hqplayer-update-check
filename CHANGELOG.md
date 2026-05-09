# Changelog

## 2026-05-09

### Fixed
- Version regex now accepts decimal RPM release tags (e.g. `5.17.2-48.1.fc43`). Previously required integer release, causing `hqplayer_update_check_success=0` when upstream bumped the dist release format.

## 2026-04-24

### Added
- Initial HQPlayer Embedded update checker with RPM auto-download to `~/hqplayer-downloads` and NAA RSS check.
- HQPlayer Desktop update check (RSS-based) with `desktop_update_available` and `desktop_update_check_success` metrics.
- README with Prometheus alert examples for Embedded, NAA, and Desktop.
