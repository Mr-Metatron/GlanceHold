# GlanceHold

## What This Is

GlanceHold 是一个 macOS 状态栏工具，用普通摄像头和 Apple Vision Framework 在本地判断用户是否正面向屏幕，并据此控制视频播放状态。第一版优先服务用户自己的网课/长视频观看场景，重点支持 IINA：看向屏幕时保持原来的倍速，看向其他地方时降到 1x，看回来后恢复原来的倍速；同时保留“看走暂停、看回恢复”的模式。

它不是眼动追踪，也不判断用户注视屏幕上的具体位置。它只做一个实用、轻量、隐私友好的头部朝向/离开检测层，并通过状态栏菜单提供开关、模式切换、校准和阈值调整。

## Core Value

当用户注意力离开屏幕时，GlanceHold 能可靠、克制地替用户处理视频速度或播放状态，并在用户回来时恢复到合适状态，且不误恢复用户手动暂停的视频。

## Current State

GlanceHold v1.1 shipped on 2026-06-13. The app is a local-only macOS status-bar utility with camera permission handling, AVFoundation/Vision attention monitoring, calibration and tuning, IINA plugin bridge playback control, Speed Control and Pause/Resume modes, Last Action feedback, stop-only disable/quit cleanup, English/Simplified Chinese localization, user docs, and real-camera plus real-IINA UAT evidence.

v1.1 hardened the runtime for longer real-world IINA viewing sessions: default-quiet structured diagnostics, bounded camera/Vision hot paths, semantic playback deduplication, generation-safe playback coordination, conservative attention/calibration/settings semantics, a no-token local IINA bridge trust model, legacy MPV production-boundary isolation, scalar ABBA resource evidence, and DiagnosticRuntimeMetrics closeout evidence.

v1.2 Phase 12 is complete. The English README, Simplified Chinese README, and IINA plugin README now form the public release documentation contract for privacy boundaries, local loopback bridge trust, IINA-first support, install/calibration/troubleshooting flow, unsigned/manual-install wording, and GitHub Release body fields.

v1.2 Phase 13 is complete. Maintainers now have a repeatable archive/export packaging path, a minimal app DMG, SHA-256 checksum generation, JSON release manifest generation, ignored generated output roots, and release-packaging documentation that keeps generated facts explicit for later phases.

v1.2 Phase 14 is complete. Public and maintainer docs now state the selected release trust path as unsigned and not notarized, requiring macOS manual open / Open Anyway handling; generated release manifests no longer include Apple trust fields or pending Phase 14 trust placeholders. The project is ready to plan Phase 15 IINA plugin distribution and compatibility work.

This PR keeps only the root planning handoff documents needed for the next developer to regain context quickly. Detailed per-phase planning logs, reviews, debug notes, and research artifacts are intentionally omitted from the public handoff.

## Current Milestone: v1.2 Distribution and Public Release Readiness

**Goal:** Prepare GlanceHold for a public/manual release by creating a reliable DMG package, a strong project README/introduction, and a release verification path.

**Target features:**
- Public README and concise project introduction that explain what GlanceHold does, who it is for, privacy boundaries, supported player path, installation, use, and troubleshooting.
- Repeatable macOS release packaging that can produce a DMG artifact for the app and clearly document what is or is not signed/notarized for this milestone.
- Release verification checklist and evidence covering build, DMG install, camera permission, IINA plugin setup, primary playback smoke tests, localization sanity, and privacy/local-only claims.

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
- ✓ v1.1 observability is implemented — Phase 7 added default-quiet structured diagnostics, session sequencing, scalar runtime summaries, and diagnostic-mode controls.
- ✓ v1.1 power hot-path work is implemented — Phase 8 bounded Vision analysis, deduplicated stable attention semantics, and removed stable-monitoring fallback snapshot polling.
- ✓ v1.1 bridge trust cleanup is implemented — Phase 08.1 and Phase 11 removed manual token-copy friction, added protocol-distinct setup/update states, and tested the command whitelist.
- ✓ v1.1 playback ownership safety is implemented — Phase 9 and Phase 09.1 closed stop/quit/mode replacement, confirmation failure, manual takeover, and PLAY evidence-indexing gaps.
- ✓ v1.1 attention and calibration semantics are implemented — Phase 10 tightened recovery through uncertain signals, calibration window requirements, reset behavior, scalar diagnostics, and settings repair.
- ✓ v1.1 reliability verification is complete — Phase 11 recorded scalar ABBA resource evidence, real IINA/camera UAT, DiagnosticRuntimeMetrics counters, legacy MPV target isolation, and a passed milestone audit.
- ✓ v1.2 public release documentation contract is complete — Phase 12 updated `README.md`, `README_zh.md`, and `IINAPlugin/README.md` so users and maintainers can understand fit, privacy/trust boundaries, setup, troubleshooting, and release-body requirements without private planning notes.
- ✓ v1.2 repeatable release packaging is implemented — Phase 13 added `scripts/package_release.sh`, `scripts/verify_phase13_packaging.sh`, `ReleasePackaging/ExportOptions.plist`, and `docs/release-packaging.md` so maintainers can produce an archive/export-based DMG, checksum, and manifest while keeping generated artifacts ignored and trust/plugin facts explicit.
- ✓ v1.2 release trust evidence path is documented and verified — Phase 14 locked README, Chinese README, packaging docs, package script, and static verifier to the unsigned/manual-install trust path while removing generated Apple trust fields from release manifests.

### Active

- [ ] Release verification should prove the packaged app still works for the IINA-first attention-control workflow.
- [ ] Optional hardening follow-ups remain candidates only if they directly support release confidence.

### Out of Scope

- Precise eye tracking — the product only needs practical head orientation / face presence detection.
- Cloud processing — privacy value depends on all visual processing staying local.
- General multi-player support in v1/v1.1 — first versions prioritize IINA because it matches the user's current pain point and reliability needs.
- Browser video control in v1/v1.1 — useful later, but not the immediate reliability need.
- Full settings window in v1/v1.1 — status bar controls are enough for the first usable versions.
- Shipping SemiUHPE as part of the app in v1 — GPLv3 licensing, model weight, PyTorch, and performance concerns make it unsuitable for the first slice.

## Context

The repository now contains the shipped local v1.1 app. The app target is a macOS status-bar utility with local camera permission handling, AVFoundation/Vision attention monitoring, calibration and tuning controls, IINA plugin bridge playback control, Last Action feedback, stop-only disable/quit cleanup, English/Simplified Chinese localization, structured diagnostics, bounded sampling, playback semantic deduplication, and final user documentation/UAT artifacts.

The current codebase is a single macOS app target using Swift 5.0, SwiftUI, macOS deployment target 14.0, App Sandbox, the camera entitlement, and a local IINA plugin bridge. `SemiUHPE/` remains a local ignored research checkout and should remain reference-only for v1/v1.1.

The first real product direction has been validated: while watching IINA at 2x or another user-selected speed, looking away drops playback to 1x and looking back restores the speed that was active before GlanceHold intervened. Pause/Resume remains available as the secondary mode, with manual pause protection preserved.

v1.1 closeout stats: 7 phases, 31 plans, 27/27 v1.1 requirements complete, 7/7 phase verification artifacts passed, 7/7 phase validation artifacts passed, and about 15,104 lines across tracked app, plugin, test, and top-level Markdown source files excluding planning archives and reference checkouts.

The v1.1 audit passed with non-blocking evidence-boundary notes: BRDG-02 loopback host-bind proof is warning-level because the plugin API host binding is not explicit in source, disable/quit cleanup is accepted through automated regression evidence rather than stable live observation, resource evidence is scalar ABBA CPU/RSS/connection/counter evidence with no fixed watt threshold, and one fresh broad XCTest audit rerun was inconclusive while existing phase artifacts remained accepted.

## Next Milestone Goals

v1.2 focuses on distribution and public release readiness:

- Create the public-facing README and short project introduction.
- Add a repeatable DMG release path for the macOS app.
- Document installation and IINA plugin setup clearly enough for a fresh user.
- Verify the packaged app against the IINA-first attention-control workflow.
- Keep launch-at-login, player expansion, and accuracy/model exploration deferred unless they become necessary for release trust.

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
| Prioritize runtime reliability and power before new product features in v1.1 | The current MVP works, but user-observed power draw and review findings threaten trust during long viewing sessions | Validated by v1.1 closeout |
| Make logging default-quiet but state-machine-rich when diagnostics are enabled | Normal users should not see log spam, while occasional state/playback bugs need breadcrumbs that survive after the fact | Validated in Phase 7 |
| Continue roadmap phase numbering from Phase 7 | v1.0 phases remain historical context and v1.1 can continue without directory collisions | Validated through v1.1 archival |
| Replace manual IINA bridge token copy with a low-friction local trust model | The intended workflow is a single-user local IINA integration, and the manual token/paste step blocks normal use while adding little practical value | Validated in Phase 08.1 and Phase 11 |
| Bound Vision and playback hot paths before broader feature work | Power trust depends on avoiding camera-rate analysis and repeated stable-state playback work | Validated in Phase 8 and Phase 11 resource evidence |
| Use generation checks and read-only confirmation evidence for playback ownership | Stop, quit, mode replacement, transient confirmations, and manual takeover need one session-bound authority | Validated in Phase 9 and Phase 09.1 |
| Treat uncertain attention/calibration/settings input conservatively | Recovery shortcuts, micro-window calibration, and unsafe persisted values can destabilize monitoring | Validated in Phase 10 |
| Keep concrete MPV IPC outside normal production target membership | The product path is the IINA plugin bridge; MPV IPC remains reference/experimental boundary material | Validated in Phase 11 |
| Accept scalar ABBA resource evidence without a fixed watt threshold for v1.1 | The power signal is noisy, so closeout should preserve privacy-safe scalar evidence and avoid overclaiming a watt target | Accepted with caveat in Phase 11 and milestone audit |
| Keep v1.2 release trust status in public docs and release-body wording, not generated manifest trust fields | The actual current release path is unsigned and not notarized; generated manifests should record build/artifact/environment/plugin facts without implying Developer ID evidence | Validated in Phase 14 |

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
*Last updated: 2026-06-13 after completing Phase 14 signing, notarization, and trust evidence*
