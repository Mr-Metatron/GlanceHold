# Requirements: GlanceHold

**Defined:** 2026-06-05
**Core Value:** 当用户注意力离开屏幕时，GlanceHold 能可靠、克制地替用户处理视频速度或播放状态，并在用户回来时恢复到合适状态，且不误恢复用户手动暂停的视频。

## v1 Requirements

Requirements for the first usable local release. Each maps to roadmap phases.

### Status Bar App

- [x] **APP-01**: User can launch GlanceHold as a status-bar utility without needing a normal main window.
- [x] **APP-02**: User can enable and disable monitoring from the status bar menu.
- [x] **APP-03**: User can see current monitoring state from the status bar menu, including Off, Needs Camera Permission, Needs Calibration, Facing, Looking Away, No Face, Recovering, and IINA Unavailable.
- [x] **APP-04**: User can quit GlanceHold from the status bar menu.
- [x] **APP-05**: User can switch between Speed Control mode and Pause/Resume mode from the status bar menu.

### Privacy and Permissions

- [ ] **PRIV-01**: User is prompted for camera permission only as part of an explicit monitoring/calibration action.
- [x] **PRIV-02**: User can understand from app/menu copy that camera processing is local-only.
- [x] **PRIV-03**: GlanceHold does not upload, store, or persist camera frames, screenshots, face images, or video clips.
- [x] **PRIV-04**: If camera permission is denied or camera capture is unavailable, GlanceHold shows a recoverable status and sends no playback commands.
- [x] **PRIV-05**: Disabling or quitting GlanceHold stops camera capture.

### Attention Detection

- [x] **ATTN-01**: GlanceHold uses AVFoundation camera capture and Apple Vision face/head-pose observations as the v1 attention signal.
- [x] **ATTN-02**: User can calibrate a neutral facing-screen pose from the status bar menu.
- [x] **ATTN-03**: If calibration fails because no stable face is detected, GlanceHold reports failure and preserves the previous valid calibration when one exists.
- [x] **ATTN-04**: User can recalibrate without restarting the app.
- [x] **ATTN-05**: User can adjust head-turn sensitivity or threshold from the status bar menu.
- [x] **ATTN-06**: User can adjust away delay and recovery delay from the status bar menu.
- [x] **ATTN-07**: GlanceHold classifies attention through a debounced state machine rather than directly acting on single Vision frames.
- [x] **ATTN-08**: GlanceHold distinguishes at least Facing, Looking Away, No Face, and Recovering states internally and in user-visible status.

### IINA Playback

- [x] **IINA-01**: GlanceHold can detect whether IINA is available and whether a playable item is idle, paused, or playing.
- [x] **IINA-02**: GlanceHold can read the current IINA playback speed before it intervenes.
- [x] **IINA-03**: In Speed Control mode, when the user looks away or leaves frame beyond the configured delay, GlanceHold sets IINA playback speed to 1x.
- [x] **IINA-04**: In Speed Control mode, when the user returns and recovery delay passes, GlanceHold restores the playback speed captured before its intervention.
- [x] **IINA-05**: Speed restoration supports arbitrary original speeds such as 1.25x, 1.5x, and 2x, not only a hard-coded 2x value.
- [x] **IINA-06**: In Pause/Resume mode, when the user looks away or leaves frame beyond the configured delay, GlanceHold pauses IINA.
- [x] **IINA-07**: In Pause/Resume mode, when the user returns and recovery delay passes, GlanceHold resumes IINA only if GlanceHold caused the pause.
- [x] **IINA-08**: If IINA is closed, idle, disconnected, or not controllable, GlanceHold shows an unavailable/idle status and sends no playback command.

### Safety and Ownership

- [x] **SAFE-01**: GlanceHold never auto-resumes a video that the user manually paused.
- [x] **SAFE-02**: GlanceHold tracks whether it currently owns a speed override before attempting to restore speed.
- [x] **SAFE-03**: GlanceHold tracks whether it currently owns a pause before attempting to resume playback.
- [x] **SAFE-04**: GlanceHold suppresses duplicate playback commands while an owned speed or pause intervention is already active.
- [x] **SAFE-05**: Unknown, uncalibrated, ambiguous, denied-permission, camera-unavailable, or IINA-unavailable states produce safe no-op behavior.
- [x] **SAFE-06**: Disabling or quitting GlanceHold releases or best-effort restores owned playback interventions according to the selected mode and current known IINA state.

### Preferences and Feedback

- [x] **PREF-01**: GlanceHold persists selected mode, sensitivity/threshold, away delay, recovery delay, and last valid scalar calibration data across launches.
- [x] **PREF-02**: GlanceHold exposes a clear reset/recalibration path for bad persisted calibration or settings.
- [x] **PREF-03**: Status bar menu shows the last meaningful action, such as Held speed at 1x, Restored 2x, Paused by GlanceHold, Manual pause detected, or No action.
- [x] **PREF-04**: Sensitivity and tuning menus visibly indicate the currently selected option, matching the existing checked mode-selection behavior.

### IINA Plugin Convenience and Localization

- [x] **CONV-02**: User can start or stop monitoring from IINA through a GlanceHold plugin menu item/key binding without bypassing permission, calibration, manual pause, or playback ownership safety rules.
- [x] **I18N-01**: User-facing app strings are routed through localization resources rather than scattered hard-coded Swift literals.
- [x] **I18N-02**: English and Simplified Chinese localizations cover the v1 status-bar app surface, including actions, statuses, detail text, tuning labels, alerts, and shortcut copy.

### Verification

- [x] **VER-01**: Pure attention state-machine behavior is covered by synthetic sequence tests for facing, away, no-face, recovery, and jitter.
- [x] **VER-02**: Playback policy behavior is covered by tests for speed capture/restore, pause ownership, manual pause protection, duplicate command suppression, and safe no-op states.
- [x] **VER-03**: The app has a manual verification checklist covering camera permission grant/deny, calibration success/failure, IINA open/closed/idle, speed mode, pause mode, manual pause, disable, and quit.
- [ ] **VER-04**: The macOS app builds successfully after the status-bar, camera/Vision, and IINA integration changes.

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Additional Players

- **PLYR-01**: User can control browser video playback.
- **PLYR-02**: User can control VLC playback.
- **PLYR-03**: User can control QuickTime Player playback.
- **PLYR-04**: User can configure per-player behavior profiles.

### Convenience

- **CONV-01**: User can enable launch-at-login.
- **CONV-03**: User can open an optional diagnostics window with camera preview or pose debugging.

### Distribution

- **DIST-01**: User can install a signed/notarized build.
- **DIST-02**: User can receive app updates through a defined update mechanism.

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Precise eye tracking or gaze-point detection | v1 only needs practical face presence and head orientation. |
| Cloud vision, analytics, telemetry, or remote frame processing | Violates the local-only privacy value. |
| Saving screenshots, face images, camera frames, or video clips | Not required for detection and creates sensitive data risk. |
| Browser, VLC, QuickTime, Spotify, or generic player support in v1 | IINA-first scope is needed to solve the immediate pain point reliably. |
| Full settings window in v1 | Status bar controls are enough for the first usable utility. |
| SemiUHPE integration in v1 | GPLv3, PyTorch/model distribution, size, and performance concerns are too high for v1. |
| Fatigue, blink, posture, break reminders, meeting detection, or wellness coaching | Adjacent ideas, but they dilute the playback-control product. |
| Virtual camera, fake presence, or meeting-presence tools | Unrelated to the product goal and creates ethical/permission concerns. |
| App Store, payment, licensing, or auto-update work in v1 | Distribution concerns can wait until local behavior is proven. |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| APP-01 | Phase 1 | Complete |
| APP-02 | Phase 1 | Complete |
| APP-03 | Phase 1 | Complete |
| APP-04 | Phase 1 | Complete |
| APP-05 | Phase 1 | Complete |
| PRIV-01 | Phase 1 | Pending |
| PRIV-02 | Phase 1 | Complete |
| PRIV-03 | Phase 3 | Complete |
| PRIV-04 | Phase 3 | Complete |
| PRIV-05 | Phase 3 | Complete |
| ATTN-01 | Phase 3 | Complete |
| ATTN-02 | Phase 3 | Complete |
| ATTN-03 | Phase 3 | Complete |
| ATTN-04 | Phase 3 | Complete |
| ATTN-05 | Phase 3 | Complete |
| ATTN-06 | Phase 3 | Complete |
| ATTN-07 | Phase 2 | Complete |
| ATTN-08 | Phase 3 | Complete |
| IINA-01 | Phase 4 | Complete |
| IINA-02 | Phase 4 | Complete |
| IINA-03 | Phase 4 | Complete |
| IINA-04 | Phase 4 | Complete |
| IINA-05 | Phase 4 | Complete |
| IINA-06 | Phase 4 | Complete |
| IINA-07 | Phase 4 | Complete |
| IINA-08 | Phase 4 | Complete |
| SAFE-01 | Phase 2 | Complete |
| SAFE-02 | Phase 2 | Complete |
| SAFE-03 | Phase 2 | Complete |
| SAFE-04 | Phase 2 | Complete |
| SAFE-05 | Phase 2 | Complete |
| SAFE-06 | Phase 6 | Complete |
| PREF-01 | Phase 3 | Complete |
| PREF-02 | Phase 3 | Complete |
| PREF-03 | Phase 6 | Complete |
| PREF-04 | Phase 5 | Complete |
| CONV-02 | Phase 5 | Complete |
| I18N-01 | Phase 5 | Complete |
| I18N-02 | Phase 5 | Complete |
| VER-01 | Phase 2 | Complete |
| VER-02 | Phase 2 | Complete |
| VER-03 | Phase 6 | Complete |
| VER-04 | Phase 6 | Pending |

**Coverage:**
- v1 requirements: 43 total
- Mapped to phases: 43
- Unmapped: 0

---
*Requirements defined: 2026-06-05*
*Last updated: 2026-06-07 after Phase 5 completion*
