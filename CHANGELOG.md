# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-30

### Added

- Initial public release of the Windows GUI for Hikvision ASMP RMA
  local-change batch submission.
- RMA list retrieval with automatic pagination.
- Single-RMA test submission and full batch submission.
- Configurable `dealResult`, fault type, fault description, request delay and
  page size.
- Duplicate protection via `localchange_records.csv`; previously successful
  RMA IDs can be skipped.
- Live on-screen log and per-run UTF-8 log files under `logs/`.
- Portable PowerShell launcher (`Start-LocalChange.bat`) and a compiled
  single-file Windows executable.
- Reproducible `build.ps1` packaging script and SHA-256 checksum generation.

### Fixed

- Corrected field panel sizing so labels, text boxes and the skip checkbox are
  no longer clipped.
- Removed the DPI-aware manifest from the packaged executable to preserve the
  intended 980x720 layout on standard 96 DPI Windows desktops.

### Security

- `accesstoken` is kept in memory only and is no longer persisted to
  `localchange_config.json`.
- Tokens are masked in logs.
- Runtime logs, records, local configuration and build artifacts are excluded
  from version control.

### Known issues

- The ASMP endpoints used by this tool are undocumented and may change without
  notice.
- The executable is not code-signed, so Windows SmartScreen may show an
  "Unknown publisher" warning.
- A valid ASMP account, permission scope and unexpired session token are
  required; the tool does not perform login.
- Tested on Windows 10 x64 (build 19044); Windows 11 is expected to work but was
  not separately verified for this release.
- The executable is DPI-unaware to preserve the intended 980x720 layout. On
  high-DPI displays Windows may bitmap-scale the window, so text can look
  slightly soft.
