# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-10-02

### Added

- USB-connected iPhone photo/video backup via ImageCaptureCore — no iCloud or
  Photos app required.
- Automatic organization into `<destination>/YY-MM/<City, Country>`, falling
  back to `<destination>/YY-MM` when a file has no GPS data, using EXIF/video
  metadata and reverse geocoding.
- Copy-then-verify: every file is size-checked against the source before
  being marked as backed up.
- Duplicate-aware scanning — re-scanning checks the destination folder and
  skips photos already backed up.
- Safe, confirmed deletion from the iPhone after a verified backup, plus a
  dedicated "Delete Backed-Up Photos" action for anything already backed up
  in a previous session.
- Live progress UI for scanning, backing up, and deleting, with clear
  success/partial-failure summaries and one-click retry for failed items.
- Mid-operation disconnect detection — unplugging the iPhone stops the
  current operation cleanly instead of hanging.
- Modern card-based UI with status pills and loading/empty/success states.
- Custom app icon, window title, About window, and website/attribution
  footer link.
- CI workflow (build check on push/PR) and Release workflow (builds,
  packages, and publishes `TidyRoll.zip` to GitHub Releases on tag push).

[0.1.0]: https://github.com/nogoodusername/TidyRoll/releases/tag/v0.1.0
