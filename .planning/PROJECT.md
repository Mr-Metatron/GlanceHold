# GlanceHold

## What This Is

GlanceHold 是一个 macOS 状态栏工具，用普通摄像头和 Apple Vision Framework 在本地判断用户是否正面向屏幕，并据此控制视频播放状态。第一版优先服务用户自己的网课/长视频观看场景，重点支持 IINA：看向屏幕时保持原来的倍速，看向其他地方时降到 1x，看回来后恢复原来的倍速；同时保留“看走暂停、看回恢复”的模式。

它不是眼动追踪，也不判断用户注视屏幕上的具体位置。它只做一个实用、轻量、隐私友好的头部朝向/离开检测层，并通过状态栏菜单提供开关、模式切换、校准和阈值调整。

## Core Value

当用户注意力离开屏幕时，GlanceHold 能可靠、克制地替用户处理视频速度或播放状态，并在用户回来时恢复到合适状态，且不误恢复用户手动暂停的视频。

## Current State

GlanceHold v1.0 MVP shipped on 2026-06-08. The app is a local-only macOS status-bar utility with camera permission handling, AVFoundation/Vision attention monitoring, calibration and tuning, IINA plugin bridge playback control, Speed Control and Pause/Resume modes, Last Action feedback, stop-only disable/quit cleanup, English/Simplified Chinese localization, user docs, and real-camera plus real-IINA UAT evidence.

The v1.0 planning archive lives in `.planning/milestones/`:

- `v1.0-ROADMAP.md`
- `v1.0-REQUIREMENTS.md`
- `v1.0-MILESTONE-AUDIT.md`

## Current Milestone: v1.1 Runtime Reliability and Power Budget

**Goal:** Make GlanceHold reliable, quiet, diagnosable, and power-conscious during long real-world IINA viewing sessions.

**Target features:**

- Structured runtime logging and diagnostics with levels, session IDs, state-machine transition breadcrumbs, and low-frequency metrics summaries.
- Power hot-path control for camera/Vision sampling, duplicate attention notifications, and redundant playback snapshots.
- Playback ownership safety so stop, quit, and mode changes invalidate in-flight playback tasks before they can control IINA.
- Attention semantics and calibration robustness fixes for transient unavailable signals, confirmation failures, reset calibration, settings validation, and stable-window calibration.
- IINA bridge security and legacy backend boundary cleanup, with final stress and live-use verification.

## Requirements

### Validated

- ✓ macOS app scaffold exists — `GlanceHold.xcodeproj` defines a single `GlanceHold` app target.
- ✓ SwiftUI entry point exists — `GlanceHold/GlanceHoldApp.swift` launches `ContentView`.
- ✓ Camera permission groundwork exists — `GlanceHold/Info.plist` includes `NSCameraUsageDescription`.
- ✓ App sandbox and camera entitlement exist — `GlanceHold/GlanceHold.entitlements` enables sandbox and camera access.
- ✓ Product concept is documented — `README.md` states local camera processing, privacy posture, and attention-aware playback control goal.
- ✓ Research reference is separated — `SemiUHPE/` is ignored by git and treated as local reference, not app product code.
- ✓ Pure debounced attention state machine exists — Phase 2 added `AttentionStateMachine` with timestamped facing/away/no-face/recovery behavior.
- ✓ Pure playback ownership policy exists — Phase 2 added intent-only speed and pause ownership reducers with manual takeover protection.
- ✓ Phase 2 safety behavior is tested — XCTest covers attention jitter/recovery, speed capture/restore, pause ownership, duplicate suppression, missing speed, unavailable player state, and manual takeover no-op/stop-monitoring behavior.
- ✓ Status-bar-first app shell is implemented — Phase 1 converted GlanceHold into an ambient menu-bar utility with explicit controls.
- ✓ Local AVFoundation/Vision monitoring is implemented — Phase 3 added camera capture, Vision pose analysis, calibration, and settings persistence without uploading or storing frames.
- ✓ IINA-first playback integration is implemented — Phase 4 validated the local IINA plugin bridge, player status, Speed Control, Pause/Resume, and manual takeover behavior.
- ✓ Control polish and localization are implemented — Phase 5 added checked tuning controls, IINA plugin shortcut routing, and English/Simplified Chinese localization.
- ✓ Final v1 hardening is complete — Phase 6 added Last Action feedback, stop-only disable/quit cleanup, user docs, full XCTest/build/plugin checks, and real-camera plus real-IINA UAT.

### Active

- [ ] v1.1 Runtime Reliability and Power Budget requirements are defined in `.planning/REQUIREMENTS.md`.
- [ ] v1.1 roadmap continues from Phase 7 and prioritizes logging/diagnostics before power and ownership changes.
- [ ] User-observed ~5W extra power draw during monitoring is treated as a primary regression target for v1.1.
- [ ] Staff review findings are triaged into implementation phases without expanding scope into distribution or broader player support.

### Out of Scope

- Precise eye tracking — the product only needs practical head orientation / face presence detection.
- Cloud processing — privacy value depends on all visual processing staying local.
- General multi-player support in v1 — first version prioritizes IINA because it matches the user's current pain point.
- Browser video control in v1 — useful later, but not the immediate need.
- Full settings window in v1 — status bar controls are enough for the first usable version.
- Shipping SemiUHPE as part of the app in v1 — GPLv3 licensing, model weight, PyTorch, and performance concerns make it unsuitable for the first slice.

## Context

The repository now contains the shipped local v1.0 MVP. The app target is a macOS status-bar utility with local camera permission handling, AVFoundation/Vision attention monitoring, calibration and tuning controls, IINA plugin bridge playback control, Last Action feedback, stop-only disable/quit cleanup, English/Simplified Chinese localization, and final user documentation/UAT artifacts.

The current codebase map lives in `.planning/codebase/`. It records that the app is a single macOS target using Swift 5.0, SwiftUI, macOS deployment target 14.0, App Sandbox, camera entitlement, and a local IINA plugin bridge. `SemiUHPE/` remains a local ignored research checkout and should remain reference-only for v1.

The first real product direction has been validated: while watching IINA at 2x or another user-selected speed, looking away drops playback to 1x and looking back restores the speed that was active before GlanceHold intervened. Pause/Resume remains available as the secondary mode, with manual pause protection preserved.

Milestone closeout stats: 6 phases, 27 plans, 43/43 v1 requirements complete, 6/6 phase verification artifacts passed, and about 7,198 lines across tracked Swift/JavaScript/Markdown source and planning files excluding `SemiUHPE/`.

The v1.1 milestone is driven by two inputs: the user's real-use observation that monitoring can add roughly 5W of power draw, and a staff-engineer code review of the current runtime orchestration. The review found credible risks around every-frame state notifications, full-frame-rate Vision analysis, playback snapshots triggered by duplicate attention states, unstructured playback tasks that survive stop/mode changes, transient unavailable signals bypassing recovery delay, short calibration windows, reset-calibration data loss, and IINA bridge authentication gaps.

## Next Milestone Goals

v1.1 focuses on runtime hardening before adding product surface area:

- Default-quiet structured logging and diagnostic metrics that can explain occasional state-machine or playback-control surprises.
- Lower-power monitoring through sampling, semantic notification deduplication, and snapshot throttling.
- Strong playback ownership boundaries for stop, quit, mode switch, command confirmation, and manual takeover paths.
- More conservative attention recovery and calibration semantics, backed by deterministic tests.
- IINA bridge authentication cleanup and clear production/legacy backend boundaries.

Deferred directions remain: distribution readiness, launch-at-login convenience, broader player support, and model-based accuracy work.

## Constraints

- **Tech stack**: macOS Swift/SwiftUI app — existing project is an Xcode macOS application target.
- **Detection approach**: Apple Vision Framework first — fastest native path, no model distribution burden, fits privacy goal.
- **Camera handling**: Local-only visual processing — camera frames must not be uploaded, stored, or sent to remote services.
- **Primary playback target**: IINA first — chosen because it matches the current user pain point.
- **UI scope**: Status-bar-first utility — no full window is required for v1.
- **User safety**: Manual pause must be respected — auto-resume is allowed only for pauses caused by GlanceHold.
- **Speed behavior**: GlanceHold may automatically manage playback speed while monitoring is active — manual pause protection is stricter than manual speed protection for v1.
- **Licensing**: SemiUHPE remains reference-only — GPLv3 and research-stack dependencies are not acceptable for v1 product code.
- **Reliability**: Debounce and recovery delay are required — raw Vision observations are noisy and must not directly trigger rapid media actions.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Build as a macOS status bar utility, not a full-window app | The tool should stay ambient and controllable without interrupting video watching | Validated in Phase 1 and final UAT |
| Use Apple Vision Framework for v1 | Native, local, lightweight, avoids PyTorch/model/license burden | Validated in Phase 3 |
| Prioritize IINA for first playback integration | User's immediate pain point is watching video in IINA, especially 2x to 1x speed behavior | Validated in Phase 4 and final UAT |
| Make speed-control mode the primary v1 mode | Looking away should often reduce cognitive pressure by dropping to 1x instead of stopping playback | Validated end-to-end in Phase 4 and final UAT |
| Keep play/pause as a selectable secondary mode | README's original behavior remains useful and should be available | Validated end-to-end in Phase 4 and final UAT |
| Restore the user's original playback speed when they look back | Preserves the user's chosen speed instead of hard-coding 2x | Validated by policy tests, IINA live checks, and final UAT |
| Respect manual pause but continue auto-managing speed | User explicitly wants pause protection first; speed can stay under GlanceHold control during monitoring | Validated by tests and final UAT |
| Implement both startup calibration and menu-adjustable thresholds | Calibration handles camera/screen geometry; manual tuning handles edge cases | Validated in Phase 3 and final UAT |
| Keep SemiUHPE out of v1 implementation | It is useful reference material but creates licensing, dependency, and performance risk | Maintained through v1 |
| Prioritize runtime reliability and power before new product features in v1.1 | The current MVP works, but user-observed power draw and review findings threaten trust during long viewing sessions | Pending v1.1 |
| Make logging default-quiet but state-machine-rich when diagnostics are enabled | Normal users should not see log spam, while occasional state/playback bugs need breadcrumbs that survive after the fact | Pending v1.1 |
| Continue roadmap phase numbering from Phase 7 | v1.0 phases remain historical context and v1.1 can continue without directory collisions | Pending v1.1 |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `$gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `$gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-06-09 after starting v1.1 Runtime Reliability and Power Budget*
