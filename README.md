# GlanceHold

GlanceHold is a local macOS status-bar utility for long IINA viewing sessions. It uses the built-in camera and Apple Vision on your Mac to estimate whether your head is facing the screen, then applies conservative playback control when your attention leaves and returns.

The v1 flow is IINA-first and speed-first: in Speed Control mode, GlanceHold lowers IINA to 1x when you look away and restores the speed it captured when you come back. Pause/Resume mode is also available for users who prefer pause and resume behavior.

GlanceHold is not eye tracking. It does not know where on the screen you are looking. Camera frames are processed locally and are not uploaded, stored, or sent to a remote service.

## Quick Start

1. Build and launch GlanceHold on macOS 14 or later.
2. Install and enable the IINA plugin from `IINAPlugin/GlanceHoldBridge.iinaplugin`; see [IINAPlugin/README.md](IINAPlugin/README.md) for the plugin copy or development-link path.
3. Open IINA and load a playable video.
4. Open the GlanceHold status-bar menu and choose `Calibrate`.
5. Grant camera permission when macOS asks. Calibration starts only after you choose calibration or monitoring.
6. Face the screen normally until calibration succeeds.
7. Choose `Enable Monitoring`.
8. Use `Speed Control` for the default hold-at-1x behavior, or switch to `Pause/Resume`.

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

When the bridge is connected, the GlanceHold menu's IINA row should move from setup or unavailable states into idle, paused, playing, or not-controllable states depending on IINA playback.

### Last Action

`Last Action` appears only after GlanceHold performs playback or safety work, such as `Held speed at 1x`, `Restored speed to 2x`, `Paused by GlanceHold`, `Resumed playback`, `Manual pause detected`, or `Stopped monitoring`.

Readiness states such as camera permission, calibration needed, no face, looking away, recovering, and IINA availability stay in the Status and IINA rows instead of becoming Last Action entries.

### Disable Monitoring And Quit

`Disable Monitoring` stops attention monitoring and camera capture, clears GlanceHold's internal playback ownership, and records `Stopped monitoring`.

`Quit` stops monitoring, stops local status streams, clears GlanceHold playback ownership, and exits.

Both paths intentionally use stop-only cleanup. They do not restore speed or resume playback during shutdown, even if GlanceHold had recently lowered speed or paused IINA. The next monitoring session re-reads IINA state before making any new playback decision.

## Troubleshooting

### Camera Permission Or Calibration

If the menu says camera permission is needed or denied, choose the menu action shown by GlanceHold and grant camera access in macOS Settings. If calibration fails, face the screen, avoid strong side lighting, and try `Calibrate` again.

### IINA Unavailable Or Setup Needed

If IINA status is unavailable or setup-needed, confirm IINA is running, the GlanceHold IINA plugin is installed and enabled, and a playable video is loaded. Restart IINA after copying or linking plugin files.

### Speed Or Pause Does Not Change

Check that monitoring is enabled, calibration has succeeded, IINA is playing a controllable item, and the selected mode matches what you expect. In Speed Control mode, the visible change is speed lowering to 1x and later restoring. In Pause/Resume mode, the visible change is pause and resume.

### Manual Pause Or Takeover

If you manually pause or otherwise take over playback, GlanceHold stops monitoring for safety and shows `Manual pause detected`. Enable monitoring again when you want GlanceHold to take a fresh reading.

### Disable Monitoring Leaves IINA At 1x Or Paused

This is expected stop-only behavior. Disable Monitoring and Quit hand control back to you without sending restore or resume commands.
