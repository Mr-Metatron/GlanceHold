# GitHub Release Body Template

Use this template for the public GitHub Release body for each GlanceHold release.
Fill it from the generated release manifest, checksum file, package output, and
final release verification evidence. Keep detailed UAT tables, GSD phase records, and private planning artifacts outside the public GitHub Release body per D-16.

## Release Summary

- App version/build: `<app-version> / <build>`
- Signing/notarization status: Unsigned and not notarized; install requires macOS manual open / Open Anyway.
- Verification summary: `<one-paragraph high-level result from final release verification>`

Suggested summary text:

GlanceHold `<app-version>` build `<build>` is an IINA-first macOS status-bar
utility that uses local camera processing and Apple Vision to estimate whether
the user's head is facing the screen. This release was verified from the packaged
artifact and matching IINA Bridge plugin package for the environment listed
below.

## Assets

- DMG filename: `GlanceHold-<app-version>-build-<build>.dmg`
- SHA-256 checksum: `<sha256-from-GlanceHold-<app-version>-build-<build>.dmg.sha256>`
- IINA Bridge plugin package filename: `GlanceHoldBridge-<app-version>-build-<build>.iinaplgz`
- IINA Bridge plugin version: `<plugin-version-from-manifest>`
- Bridge protocol version: `<bridge-protocol-version-from-manifest>`

Download the app DMG and the IINA Bridge plugin package from this same GitHub
Release. Do not mix app and plugin files from different releases.

## Verification

- Verified macOS: `<macOS version and hardware family>`
- Verified Xcode: `<Xcode version used for archive/export and tests>`
- Verified IINA: `<IINA version used for plugin install and playback smoke>`
- Verification summary: `<PASS/FAIL high-level source gates, package gates, copied-app UAT, and public claim audit result>`

Public release notes should include only the high-level verification result and
release facts. Detailed UAT tables, GSD phase records, and private planning
artifacts must remain outside the public GitHub Release body.

## Install Notes

1. Verify the downloaded DMG against the SHA-256 checksum above before launching.
2. Install `GlanceHold.app` from `GlanceHold-<app-version>-build-<build>.dmg`.
3. Unsigned and not notarized; install requires macOS manual open / Open Anyway.
4. Install `GlanceHoldBridge-<app-version>-build-<build>.iinaplgz` from this same
   release or from the same DMG by opening it with IINA, then restart IINA.
5. Launch IINA with a playable video, launch GlanceHold, calibrate facing pose,
   and enable monitoring.

## Known Limitations

- Known limitations: `<release-specific limitations or "Same as README baseline limitations">`
- Current verified playback target is IINA with the matching GlanceHold Bridge plugin.
- Other players are not supported by this release.
- GlanceHold is practical head-orientation / face-presence detection, not eye tracking.
- Camera frames are processed locally on the Mac and are not saved or uploaded by GlanceHold.
- The IINA bridge uses local loopback communication on the same Mac and is not a
  general remote-control API.

## Maintainer Pre-Publication Check

- App version/build matches the generated manifest and app bundle.
- DMG filename matches `GlanceHold-<app-version>-build-<build>.dmg`.
- SHA-256 checksum matches the generated `.dmg.sha256` file and manifest value.
- IINA Bridge plugin package filename matches `GlanceHoldBridge-<app-version>-build-<build>.iinaplgz`.
- IINA Bridge plugin version and Bridge protocol version match the generated manifest.
- Signing/notarization status uses the exact unsigned/manual-install sentence above.
- Verified macOS, Verified Xcode, and Verified IINA match final verification evidence.
- Verification summary is high-level only and does not include detailed private UAT tables.
- Known limitations do not claim support for unsupported players or future distribution channels.
- Detailed UAT tables, GSD phase records, and private planning artifacts are not copied
  into the public GitHub Release body.
