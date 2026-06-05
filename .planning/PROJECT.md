# GlanceHold

## What This Is

GlanceHold 是一个 macOS 状态栏工具，用普通摄像头和 Apple Vision Framework 在本地判断用户是否正面向屏幕，并据此控制视频播放状态。第一版优先服务用户自己的网课/长视频观看场景，重点支持 IINA：看向屏幕时保持原来的倍速，看向其他地方时降到 1x，看回来后恢复原来的倍速；同时保留“看走暂停、看回恢复”的模式。

它不是眼动追踪，也不判断用户注视屏幕上的具体位置。它只做一个实用、轻量、隐私友好的头部朝向/离开检测层，并通过状态栏菜单提供开关、模式切换、校准和阈值调整。

## Core Value

当用户注意力离开屏幕时，GlanceHold 能可靠、克制地替用户处理视频速度或播放状态，并在用户回来时恢复到合适状态，且不误恢复用户手动暂停的视频。

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

### Active

- [ ] Convert the app from a normal placeholder window into a status-bar-first utility with no required full main window.
- [ ] Use AVFoundation camera capture plus Apple Vision face/head-pose observations locally; do not upload, store, or send camera frames.
- [ ] Implement a calibration flow that samples the user's neutral facing-screen pose before monitoring.
- [ ] Let the user adjust head-turn threshold and recovery timing from the status bar menu.
- [ ] Support a primary "speed control" mode for IINA: restore the user's original playback speed when facing screen, switch to 1x when looking away.
- [ ] Support a secondary "play/pause" mode: pause when looking away or absent, resume only if GlanceHold caused the pause.
- [ ] Respect user manual pause state; GlanceHold must not auto-resume a video the user manually paused.
- [ ] Allow speed changes to remain automatically managed by GlanceHold while monitoring is active.
- [ ] Provide status-bar menu controls for enable/disable monitoring, current status, mode switching, calibration, threshold adjustment, and recovery delay.
- [ ] Keep SemiUHPE out of v1 implementation unless a later phase explicitly revisits model accuracy and licensing.

### Out of Scope

- Precise eye tracking — the product only needs practical head orientation / face presence detection.
- Cloud processing — privacy value depends on all visual processing staying local.
- General multi-player support in v1 — first version prioritizes IINA because it matches the user's current pain point.
- Browser video control in v1 — useful later, but not the immediate need.
- Full settings window in v1 — status bar controls are enough for the first usable version.
- Shipping SemiUHPE as part of the app in v1 — GPLv3 licensing, model weight, PyTorch, and performance concerns make it unsuitable for the first slice.

## Context

The repository is currently an early macOS SwiftUI scaffold with tested pure domain logic. The app target exists, Phase 1 established status-bar and permission-state foundations, and Phase 2 added pure attention/playback reducers with XCTest coverage. The product behavior in `README.md` is still not end-to-end implemented yet: there is no camera capture, Vision analysis, real playback transport, calibration UI, or IINA adapter.

The current codebase map lives in `.planning/codebase/`. It records that the app is a single macOS target using Swift 5.0, SwiftUI, macOS deployment target 14.0, App Sandbox, and camera entitlement. It also records that `SemiUHPE/` is a local ignored research checkout and should remain reference-only for now.

The first real product direction is user-specific and concrete: while watching IINA at 2x or another user-selected speed, looking away should drop playback to 1x rather than necessarily pausing. Looking back should restore the speed that was active before GlanceHold intervened. The pause/resume mode remains available, but speed control is the higher-priority pain point.

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
| Build as a macOS status bar utility, not a full-window app | The tool should stay ambient and controllable without interrupting video watching | — Pending |
| Use Apple Vision Framework for v1 | Native, local, lightweight, avoids PyTorch/model/license burden | — Pending |
| Prioritize IINA for first playback integration | User's immediate pain point is watching video in IINA, especially 2x to 1x speed behavior | — Pending |
| Make speed-control mode the primary v1 mode | Looking away should often reduce cognitive pressure by dropping to 1x instead of stopping playback | Pure policy validated in Phase 2; real IINA transport pending |
| Keep play/pause as a selectable secondary mode | README's original behavior remains useful and should be available | Pure policy validated in Phase 2; real IINA transport pending |
| Restore the user's original playback speed when they look back | Preserves the user's chosen speed instead of hard-coding 2x | Pure speed ownership validated in Phase 2 |
| Respect manual pause but continue auto-managing speed | User explicitly wants pause protection first; speed can stay under GlanceHold control during monitoring | Pure pause/speed ownership validated in Phase 2 |
| Implement both startup calibration and menu-adjustable thresholds | Calibration handles camera/screen geometry; manual tuning handles edge cases | — Pending |
| Keep SemiUHPE out of v1 implementation | It is useful reference material but creates licensing, dependency, and performance risk | — Pending |

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
*Last updated: 2026-06-05 after Phase 2 completion*
