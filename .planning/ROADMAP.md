# Roadmap: GlanceHold

## Overview

GlanceHold v1 delivers a speed-first macOS status-bar utility for IINA. The roadmap starts with a trustworthy menu-bar shell, locks the attention and playback ownership rules in pure tests, connects local AVFoundation/Vision calibration, proves real IINA control, polishes control affordances with an IINA plugin shortcut and localization, then hardens the end-to-end MVP with manual UAT and failure-state polish.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Status-Bar Shell, Permission Trust, and Verification Baseline** - Users can run GlanceHold as an ambient menu-bar utility with explicit controls and privacy/permission trust. (completed 2026-06-06)
- [x] **Phase 2: Pure Attention State Machine and Playback Policy** - The trust-critical attention debounce and playback ownership rules are deterministic and test-covered before side effects exist. (completed 2026-06-05)
- [x] **Phase 3: Local Camera, Vision Signal, Calibration, and Tuning** - Users can calibrate and tune a local Vision-based attention signal that drives visible attention states. (completed 2026-06-06)
- [x] **Phase 4: IINA Adapter Spike and End-to-End Playback Control** - GlanceHold controls real IINA playback for speed and pause modes through a validated adapter. (completed 2026-06-07)
- [x] **Phase 5: Control Polish, IINA Shortcut, and i18n** - Users can tune, toggle, and read GlanceHold more comfortably through checked menu controls, an IINA plugin monitoring shortcut, and English/Chinese localization. (completed 2026-06-07)
- [ ] **Phase 6: End-to-End UX Hardening and Manual UAT** - The MVP is safe to use across real camera/player failures, disable/quit flows, and manual acceptance checks.

## Phase Details

### Phase 1: Status-Bar Shell, Permission Trust, and Verification Baseline

**Goal:** Users can run GlanceHold as an ambient status-bar utility with explicit monitoring controls and permission/privacy trust.
**Mode:** mvp
**Depends on:** Nothing (first phase)
**Requirements:** APP-01, APP-02, APP-03, APP-04, APP-05, PRIV-01, PRIV-02
**Success Criteria** (what must be TRUE):

  1. User can launch GlanceHold from the status bar without needing a normal main window.
  2. User can enable or disable monitoring, switch between Speed Control and Pause/Resume, and quit from the status-bar menu.
  3. User can see a current status row whose vocabulary includes Off, permission/calibration needs, attention states, and IINA unavailable.
  4. Camera permission is requested only after an explicit monitoring or calibration action, and the menu copy makes local-only processing clear.

**Plans:** 3/3 plans complete
**UI hint**: yes

### Phase 2: Pure Attention State Machine and Playback Policy

**Goal:** GlanceHold has testable attention and playback ownership semantics before camera or IINA side effects exist.
**Mode:** mvp
**Depends on:** Phase 1
**Requirements:** ATTN-07, SAFE-01, SAFE-02, SAFE-03, SAFE-04, SAFE-05, VER-01, VER-02
**Success Criteria** (what must be TRUE):

  1. Synthetic facing, away, no-face, recovery, and jitter sequences produce stable debounced attention transitions.
  2. Speed policy captures the first pre-intervention speed, emits one hold-at-1x intent, and restores the same arbitrary speed only while GlanceHold owns the override.
  3. Pause policy resumes only pauses owned by GlanceHold; manual-pause sequences produce no auto-resume intent.
  4. Unknown, uncalibrated, ambiguous, denied, camera-unavailable, and IINA-unavailable inputs produce safe no-op intents.
  5. Repeated away or recovery inputs do not produce duplicate playback commands while an owned intervention is already active.

**Plans:** 2/2 plans complete
Plans:
**Wave 1**

- [x] 02-01-PLAN.md — Pure timestamped attention reducer and synthetic sequence tests.

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 02-02-PLAN.md — Pure playback ownership policy, intents, takeover handling, and tests.

### Phase 3: Local Camera, Vision Signal, Calibration, and Tuning

**Goal:** Users can calibrate and tune a local AVFoundation/Vision attention signal that drives visible Facing, Looking Away, No Face, and Recovering states.
**Mode:** mvp
**Depends on:** Phase 2
**Requirements:** PRIV-03, PRIV-04, PRIV-05, ATTN-01, ATTN-02, ATTN-03, ATTN-04, ATTN-05, ATTN-06, ATTN-08, PREF-01, PREF-02
**Success Criteria** (what must be TRUE):

  1. User can grant or deny camera access through explicit actions; denied or unavailable camera states are recoverable and send no playback commands.
  2. User can calibrate and recalibrate a neutral facing pose; failed calibration reports failure and preserves the previous valid calibration when one exists.
  3. User can adjust head-turn threshold, away delay, and recovery delay from the status-bar menu, and mode/settings/calibration persist across launches.
  4. User-visible attention status updates from local AVFoundation camera capture plus Apple Vision face/head-pose observations.
  5. Camera frames are processed locally without upload, storage, or persistence, and disabling or quitting stops camera capture.

**Plans:** 3/3 plans complete
Plans:
**Wave 1**

- [x] 03-01-PLAN.md — Pure settings, scalar calibration, raw classifier, persistence, and tests.

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 03-02-PLAN.md — Local AVFoundation capture, Vision pose analyzer, attention monitor coordinator, and tests.

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 03-03-PLAN.md — Status-bar calibration, tuning, reset, visible attention states, and full Phase 3 verification.

**UI hint**: yes

### Phase 4: IINA Adapter Spike and End-to-End Playback Control

**Goal:** As a video learner, I want to let GlanceHold control IINA speed and pause, so that playback follows my attention.
**Mode:** mvp
**Depends on:** Phase 3
**Requirements:** IINA-01, IINA-02, IINA-03, IINA-04, IINA-05, IINA-06, IINA-07, IINA-08
**Success Criteria** (what must be TRUE):

  1. With IINA running, GlanceHold can show whether IINA is available, idle, paused, or playing, and can read current playback speed before acting.
  2. In Speed Control mode, looking away or leaving frame beyond the configured delay sets IINA playback speed to 1x.
  3. In Speed Control mode, returning after recovery restores the speed captured before GlanceHold intervened, including arbitrary speeds such as 1.25x, 1.5x, and 2x.
  4. In Pause/Resume mode, looking away or leaving frame pauses IINA, and returning resumes only when GlanceHold caused the pause.
  5. If IINA is closed, idle, disconnected, or not controllable, user-visible status reports that state and no playback command is sent.

**Plans:** 10/10 plans complete
Plans:
**Wave 1**

- [x] 04-01-PLAN.md — Direct mpv JSON IPC adapter/client speed slice with fake-transport tests.

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 04-02-PLAN.md — Speed Control coordinator connecting debounced attention, PlaybackPolicy, and IINA adapter.

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 04-03-PLAN.md — Pause/Resume and conservative manual takeover handling.

**Wave 4** *(blocked on Wave 3 completion; has live IINA checkpoint)*

- [x] 04-04-PLAN.md — Status-bar player status wiring and live IINA direct IPC validation.

**Wave 5** *(blocked on Wave 4 completion; has plugin bridge live checkpoint)*

- [x] 04-05-PLAN.md — Bundled IINA plugin bridge fallback, primary runtime adapter, plugin-aware menu status, and normal-user live validation.

**Wave 6** *(blocked on Wave 5 completion; has pushed-status live checkpoint)*

- [x] 04-06-PLAN.md — Push-first IINA plugin status stream, Swift subscription handling, and low-frequency fallback.

**Wave 7** *(gap closure for Phase 4 UAT copy issue)*

- [x] 04-07-PLAN.md — Neutral `IINA Bridge Waiting` copy for unreachable plugin bridge setup states.

**Wave 8** *(gap closure for Phase 4 UAT blockers)*

- [x] 04-08-PLAN.md — Repair live calibration failure feedback/sample tolerance and IINA status fallback drift.

**Wave 9** *(gap closure for Phase 4 live calibration retest blocker)*

- [x] 04-09-PLAN.md — Robust stable-window calibration and bounded sampling for repeated `Calibration Failed` live retest.

**Wave 10** *(gap closure for Phase 4 UAT manual pause monitoring issue)*

- [x] 04-10-PLAN.md — Stop app-level monitoring when Pause/Resume manual pause/takeover is detected.

### Phase 5: Control Polish, IINA Shortcut, and i18n

**Goal:** Users can tune, toggle, and read GlanceHold more comfortably through checked menu controls, an IINA plugin monitoring shortcut, and complete English/Chinese localization for the v1 app surface.
**Mode:** mvp
**Depends on:** Phase 4
**Requirements:** PREF-04, CONV-02, I18N-01, I18N-02
**Success Criteria** (what must be TRUE):

  1. Sensitivity/tuning menus visibly mark the currently selected option while preserving the existing checked mode-selection behavior.
  2. User can start or stop monitoring from IINA using a GlanceHold plugin menu item/key binding, without adding macOS-wide hotkey permissions and without bypassing permission, calibration, manual pause, or playback ownership safety rules.
  3. User-facing status-bar menu text, actions, status details, and alerts are routed through localization resources rather than scattered hard-coded strings.
  4. English and Simplified Chinese localizations cover the v1 status-bar app surface, including monitoring status, IINA/player status, calibration/reset prompts, tuning labels, and shortcut copy.

**Plans:** 5/5 plans complete
Plans:
**Wave 1**

- [x] 05-01-PLAN.md — Checked tuning menu current-value and selected-state presentation.

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 05-02-PLAN.md — IINA plugin monitoring shortcut and safe app-side toggle routing.

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 05-03-PLAN.md — English/Simplified Chinese Apple-native localization resources and routing.

**Wave 4** *(blocked on Wave 3 completion; has lightweight human check)*

- [x] 05-04-PLAN.md — Integrated verification, plugin syntax check, and live-check handoff.

**Wave 5** *(gap closure for Phase 5 UAT copy and mode-picker issues)*

- [x] 05-05-PLAN.md — Mode picker current-value label and concise IINA/privacy copy gap closure.
**UI hint**: yes

### Phase 6: End-to-End UX Hardening and Manual UAT

**Goal:** The GlanceHold MVP is safe and clear enough for manual daily use across real camera, calibration, IINA, disable, and quit scenarios.
**Mode:** mvp
**Depends on:** Phase 5
**Requirements:** SAFE-06, PREF-03, VER-03, VER-04
**Success Criteria** (what must be TRUE):

  1. User can see the last meaningful action in the status-bar menu, such as Held speed at 1x, Restored speed, Paused by GlanceHold, Manual pause detected, or No action.
  2. Disabling or quitting GlanceHold stops monitoring and releases or best-effort restores owned playback interventions according to selected mode and known IINA state.
  3. User can complete a manual verification checklist covering permission grant/deny, calibration success/failure, IINA open/closed/idle, Speed Control mode, Pause/Resume mode, manual pause, IINA plugin shortcut toggle, localization sanity, disable, and quit.
  4. The macOS app builds successfully after the status-bar, camera/Vision, IINA integration, shortcut, and localization changes.

**Plans:** 2/4 plans executed
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Status-Bar Shell, Permission Trust, and Verification Baseline | 3/3 | Complete   | 2026-06-06 |
| 2. Pure Attention State Machine and Playback Policy | 2/2 | Complete   | 2026-06-05 |
| 3. Local Camera, Vision Signal, Calibration, and Tuning | 3/3 | Complete   | 2026-06-06 |
| 4. IINA Adapter Spike and End-to-End Playback Control | 10/10 | Complete   | 2026-06-07 |
| 5. Control Polish, IINA Shortcut, and i18n | 5/5 | Complete   | 2026-06-08 |
| 6. End-to-End UX Hardening and Manual UAT | 2/4 | In Progress|  |
