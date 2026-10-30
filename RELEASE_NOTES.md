# v1.0.0 · Initial public release

Portable Windows GUI for batch-submitting Hikvision ASMP RMA local-change
requests. This is the first public release, focused on a safe, repeatable
workflow: fetch pending RMAs, test one record, then submit the rest with
duplicate protection and a local audit log.

## Highlights

- **Single-file Windows executable** — no installer, no admin rights, no
  external runtime beyond the built-in Windows PowerShell 5.1.
- **Test before batch** — submit one selected RMA first, then run the remaining
  records with a configurable interval.
- **Duplicate protection** — previously successful RMA IDs are skipped using a
  local CSV record.
- **Token hygiene** — the ASMP `accesstoken` stays in memory only and is masked
  in logs.
- **Local audit trail** — live log panel plus one UTF-8 log file per run.

## Added

- RMA list retrieval with automatic pagination.
- Single-record and batch local-change submission.
- Configurable `dealResult`, fault type, fault description, delay and page size.
- Stop control and progress indicator during batch runs.
- Local submission history in `localchange_records.csv`.
- Per-run logs under `logs/localchange_YYYYMMDD_HHMMSS.log`.
- Reproducible `build.ps1` packaging script with SHA-256 generation.
- English and Chinese documentation, MIT license and security policy.

## Fixed

- Corrected field panel sizing so labels, text boxes and the skip checkbox are
  no longer clipped.
- Removed the DPI-aware manifest from the packaged executable to preserve the
  intended 980×720 layout on standard 96 DPI Windows desktops.
- Stopped persisting the `accesstoken` in `localchange_config.json`; old token
  fields are ignored on load.

## Known issues

- The ASMP endpoints used here are undocumented internal web APIs and may change
  without notice.
- A valid ASMP account, permission scope and unexpired session token are
  required. The tool does not perform login.
- The executable is **not code-signed**, so Windows SmartScreen may show an
  "Unknown publisher" warning.
- Logs contain full API payloads, serial numbers and customer information.
  Treat them as business-confidential data.
- Windows x64 only. There is no macOS/Linux build and no mobile version.
- Tested on Windows 10 x64 (build 19044); Windows 11 is expected to work but was
  not separately verified for this release.
- The executable is DPI-unaware to preserve the intended 980×720 layout. On
  high-DPI displays Windows may bitmap-scale the window, so text can look
  slightly soft.
- No auto-update mechanism. Download new releases manually.

## Release assets

| Asset | Purpose | System requirements |
| --- | --- | --- |
| `Hikvision-LocalChange-v1.0.0-win64.exe` | Portable application. Double-click to run; no installation. | Windows 10/11 x64, Windows PowerShell 5.1 (built in), network access to `asmp.hikvision.com`, writable application folder. |
| `checksums.txt` | SHA-256 checksum for the executable. | Any text editor or `Get-FileHash` on Windows. |

## SHA-256

```text
8ff039492f95566c8decbe47892d0786cf6f4b88bd99b5abcc0b89da47df6e56  Hikvision-LocalChange-v1.0.0-win64.exe
```

File size: **69,120 bytes** (67.5 KiB).

Verify after download:

```powershell
Get-FileHash .\Hikvision-LocalChange-v1.0.0-win64.exe -Algorithm SHA256
Get-Content .\checksums.txt
```

The two hashes must match exactly.

## Installation

1. Download the executable and `checksums.txt`.
2. Verify the SHA-256 hash.
3. Place the executable in a writable folder, such as
   `Documents\Tools\HikvisionLocalChange\`.
4. Double-click the executable.
5. Paste a valid ASMP `accesstoken`, fetch the RMA list, test one record, then
   start the batch.

Do not place the executable in `Program Files` unless the process has write
access to that folder; the tool creates its configuration, CSV record and logs
beside the executable.

## SmartScreen note

The executable is unsigned. Windows SmartScreen may display **"Windows protected
your PC"** or **"Unknown publisher"**. This is normal for an unsigned
open-source build. Verify the SHA-256 first, then choose **More info** →
**Run anyway**. If your organization blocks unsigned binaries, run the source
version through `Start-LocalChange.bat` instead.

## Source and license

- Source: https://github.com/szrd2026/hikvision-asmp-localchange
- License: MIT, Copyright (c) 2026 szrd2026
- This is an unofficial utility and is not affiliated with or endorsed by
  Hikvision. Use it only with accounts and systems you are authorized to
  operate.
