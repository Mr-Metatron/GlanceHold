# GlanceHold

[简体中文说明](README_zh.md)

GlanceHold is a macOS status-bar utility for long video sessions in IINA. It uses your Mac's built-in camera and Apple Vision to estimate whether your head is facing the screen, then applies conservative playback control when your attention leaves and returns.

GlanceHold currently supports IINA. In Speed Control mode, it lowers IINA to 1x when you look away and restores the speed it captured when you come back. Pause/Resume mode is available if you prefer pause and resume behavior.

Camera frames stay on your Mac. Camera frames are processed locally, not saved, and not uploaded. GlanceHold uses a local loopback bridge to communicate with the GlanceHold Bridge IINA plugin; see [IINAPlugin/README.md](IINAPlugin/README.md) for protocol and trust-model details.

GlanceHold is not eye tracking. It does not know where on the screen you are looking.

## Contents

- [Is This For Me?](#is-this-for-me)
- [Compatibility And Limits](#compatibility-and-limits)
- [Install From Latest Release](#install-from-latest-release)
- [Calibration Guidance](#calibration-guidance)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)
- [GitHub Release Body Contract](#github-release-body-contract)
- [Developer And Source Path](#developer-and-source-path)

## Is This For Me?

GlanceHold is for IINA users who watch courses, lectures, or long videos and want playback to become less demanding when they look away. The supported path for now is IINA with the matching GlanceHold Bridge plugin.

Choose Speed Control when you normally watch faster than 1x and want GlanceHold to temporarily hold playback at 1x while you are away. Choose Pause/Resume when you want GlanceHold to pause only when it caused the pause and resume only when it owns that pause.

## Compatibility And Limits

- Requires macOS 14 or later.
- Requires a working camera and macOS camera permission.
- Requires IINA plus the matching GlanceHold Bridge plugin.
- Other players are not supported by the current release.
- GlanceHold estimates a practical facing-screen signal; it does not identify what part of the screen you are looking at.

## Install From Latest Release

1. Open the [Latest Release](https://github.com/Mr-Metatron/GlanceHold/releases/latest).
2. Read that release body for the matching GlanceHold app DMG and GlanceHold Bridge plugin package. The release body is the source of truth for exact files, including `GlanceHold-<app-version>-build-<build>.dmg` and `GlanceHoldBridge-<app-version>-build-<build>.iinaplgz`.
3. Verify the downloaded app artifact against the SHA-256 checksum stated in that release body before launching it.
4. Unsigned and not notarized; install requires macOS manual open / Open Anyway. If macOS blocks the first launch, right-click the app and choose Open, or use System Settings -> Privacy & Security -> Open Anyway after you have verified the checksum.
5. Install the matching GlanceHold Bridge plugin: use `GlanceHoldBridge-<app-version>-build-<build>.iinaplgz` from the same GitHub Release as the app, or from the same DMG, open/install it with IINA, restart IINA, confirm `GlanceHold Bridge` is enabled in IINA, then return to GlanceHold. Detailed plugin instructions live in [IINAPlugin/README.md](IINAPlugin/README.md).
6. Open IINA and load a playable video.
7. Launch GlanceHold, open the status-bar menu, and choose `Calibrate Facing Pose`.
8. Grant camera permission when macOS asks. Camera access starts only after you choose calibration or monitoring.
9. Face the screen in your normal viewing position and normal lighting until calibration succeeds.
10. Choose `Enable Monitoring`.
11. Use `Speed Control` for the default hold-at-1x behavior, or switch to `Pause/Resume`.
12. Use `Reset Calibration` later if your saved facing pose no longer matches your normal setup.

## Calibration Guidance

Calibration is needed before monitoring can use camera signals. Sit where you normally watch IINA, face the screen naturally, keep your face visible to the camera, and use steady room lighting without strong side glare or backlight.

If calibration fails, stay facing the screen and try again after improving lighting or camera visibility. If a previous valid calibration exists, GlanceHold keeps it when a retry fails. Use `Reset Calibration` when you move to a different desk/camera angle, change your seating position, or the saved pose feels wrong; after reset, run `Calibrate Facing Pose` again before enabling monitoring.

## Developer And Source Path

For source work, open `GlanceHold.xcodeproj` in Xcode or build/run the `GlanceHold` scheme from Xcode. The app target uses AVFoundation for camera capture, Vision for the local facing-screen signal, App Sandbox camera entitlement, and `com.apple.security.network.client` for the local WebSocket bridge to IINA.

Plugin protocol and local trust-model details live in [IINAPlugin/README.md](IINAPlugin/README.md). The source-tree plugin and development-link path are for development and local testing, not the default release-user path. Run the bridge protocol harness with:

```zsh
node IINAPlugin/GlanceHoldBridge.protocol.test.js
```

## Usage

The status-bar menu shows the current monitoring status, the current IINA status when available, and `Last Action` after GlanceHold performs a meaningful playback or safety action.

### Speed Control

Speed Control is the primary v1 mode. When you look away or leave the frame for the configured away delay, GlanceHold sets IINA speed to 1x. When you face the screen again and the recovery delay passes, it restores the speed captured before GlanceHold intervened, including values such as 1.25x, 1.5x, or 2x.

### Pause/Resume

Pause/Resume pauses IINA when you look away and resumes only when GlanceHold caused the pause. If you pause IINA manually, GlanceHold treats that as user control and does not auto-resume the video.

### Calibration

Calibration records your neutral facing-screen pose. If calibration fails because no stable face is detected, try again while facing the screen in normal lighting. When a previous valid calibration exists, failed calibration keeps the previous calibration.

Use `Reset Calibration` when the saved pose feels wrong. After reset, monitoring returns to the calibration-needed state.

### IINA Plugin

The IINA plugin lets the sandboxed status-bar app communicate with IINA through a narrow local bridge. The app uses it to read IINA status, set speed, pause, resume, and receive the plugin's `Option-G` monitoring toggle request.

GlanceHold connects to `ws://127.0.0.1:47873`. Other processes on the same Mac can attempt to connect to that local port, so the plugin accepts only the GlanceHold protocol shape and whitelisted requests: `snapshot`, `setSpeed`, `pause`, and `resume`. No request token is required.

When the bridge is connected, the GlanceHold menu's IINA row should move from setup or unavailable states into idle, paused, playing, or not-controllable states depending on IINA playback.

### Last Action

`Last Action` appears only after GlanceHold performs playback or safety work, such as `Held speed at 1x`, `Restored speed to 2x`, `Paused by GlanceHold`, `Resumed playback`, `Manual pause detected`, or `Stopped monitoring`.

Readiness states such as camera permission, calibration needed, no face, looking away, recovering, and IINA availability stay in the Status and IINA rows instead of becoming Last Action entries.

### Disable Monitoring And Quit

`Disable Monitoring` stops attention monitoring and camera capture, clears GlanceHold's internal playback ownership, and records `Stopped monitoring`.

`Quit` stops monitoring, stops local status streams, clears GlanceHold playback ownership, and exits.

Both paths intentionally use stop-only cleanup. They do not restore speed or resume playback during shutdown, even if GlanceHold had recently lowered speed or paused IINA. The next monitoring session re-reads IINA state before making any new playback decision.

## Troubleshooting

### Camera Permission Needed Or Denied

If the menu says camera permission is needed or denied, choose the menu action shown by GlanceHold and grant camera access in macOS Settings. If permission was previously denied, open System Settings, allow camera access for GlanceHold, then enable monitoring again.

### Calibration Failed

If calibration failed, face the screen in your normal watching position, improve lighting or camera visibility, and choose `Calibrate Facing Pose` again. When a previous valid calibration exists, GlanceHold keeps it after a failed retry.

### Reset Calibration

Use `Reset Calibration` when your desk, camera angle, seating position, or normal viewing posture changes. After reset, monitoring returns to calibration-needed state and you must run `Calibrate Facing Pose` again.

### IINA Bridge Waiting Or Unavailable

If the IINA row shows `IINA Bridge Waiting`, setup needed, or unavailable, confirm IINA is open, the matching GlanceHold Bridge plugin is installed and enabled, and a playable video is loaded. Restart IINA after installing or changing the plugin.

### IINA Bridge Update Needed

Update or reinstall the GlanceHold IINA plugin, then restart IINA.

### Speed/Pause Not Changing

If speed/pause not changing is the visible symptom, check that monitoring is enabled, calibration has succeeded, IINA is playing a controllable item, the GlanceHold Bridge is connected, and the selected mode matches what you expect. In Speed Control mode, the visible change is speed lowering to 1x and later restoring. In Pause/Resume mode, the visible change is pause and resume.

### Manual Pause Detected

If you manually pause or otherwise take over playback, GlanceHold stops monitoring for safety and shows `Manual pause detected`. This is the manual pause detected safety path. Enable monitoring again when you want GlanceHold to take a fresh reading.

### Disable Monitoring Leaves IINA At 1x Or Paused

This is expected stop-only behavior. This troubleshooting item covers disable monitoring leaving IINA at 1x or paused. Disable Monitoring and Quit hand control back to you without sending restore or resume commands.

## GitHub Release Body Contract

Each GitHub Release body is the authoritative release-note location for that release. The README links to the [Latest Release](https://github.com/Mr-Metatron/GlanceHold/releases/latest), but release-specific facts belong in the release body for the exact version being downloaded.

Every GitHub Release body must include these fields: App version/build; IINA Bridge plugin package filename; IINA bridge plugin version; Bridge protocol version; DMG filename; SHA-256 checksum; Signing/notarization status; Verified macOS; Verified Xcode; Verified IINA; Known limitations.

- App version/build
- IINA Bridge plugin package filename: `GlanceHoldBridge-<app-version>-build-<build>.iinaplgz`
- IINA bridge plugin version
- Bridge protocol version
- DMG filename
- SHA-256 checksum
- Signing/notarization status: Unsigned and not notarized; install requires macOS manual open / Open Anyway.
- Verified macOS
- Verified Xcode
- Verified IINA
- Known limitations

Known limitations in the release body should list only new, changed, or especially important release-specific limitations; baseline limitations stay in README.
