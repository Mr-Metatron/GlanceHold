# Milestones

## v1.1 Runtime Reliability and Power Budget (Shipped: 2026-06-13)

**Delivered:** Runtime reliability and power-budget hardening for long IINA sessions, with default-quiet diagnostics, bounded hot paths, safer playback ownership, and a no-token local bridge trust model.

**Phases completed:** 7 phases, 31 plans, 69 tasks

**Key accomplishments:**

- Added default-quiet structured diagnostics with session sequencing, scalar privacy-safe fields, transition breadcrumbs, and runtime metrics summaries.
- Reduced hot-path work by throttling Vision analysis, deduplicating stable attention semantics, and avoiding repeated stable-state playback snapshots.
- Hardened playback ownership across stop, quit, mode replacement, transient confirmation failures, and manual takeover paths.
- Tightened attention, calibration, and settings semantics so uncertain samples cannot bypass recovery, calibration requires real stable windows, reset preserves tuning, and corrupt persisted values are repaired.
- Replaced manual IINA bridge token-copy friction with a no-token local trust model, protocol-distinct setup/update states, command whitelist tests, and a clear legacy MPV production boundary.
- Closed v1.1 with scalar ABBA resource evidence, real IINA/camera UAT, DiagnosticRuntimeMetrics counters, and a passed milestone audit.

**Stats:**

- 324 files changed from `v1.0..HEAD` before archival (`+37,454/-1,288`)
- 243 commits in the milestone window
- About 15,104 lines across tracked app, plugin, test, and top-level Markdown source files, excluding planning archives and reference checkouts
- 7 phases, 31 plans, 69 tasks
- 5 calendar days from first v1.1 commit to closeout (2026-06-08 -> 2026-06-13)

**Git range:** `bdf3599 feat(07-01)` -> `7e0d80e docs(quick-260613-269)`

**Archived:** `milestones/v1.1-ROADMAP.md`, `milestones/v1.1-REQUIREMENTS.md`, `milestones/v1.1-MILESTONE-AUDIT.md`, `milestones/v1.1-phases/`

**Known non-blocking follow-ups:** BRDG-02 explicit host-bind proof if IINA supports it, stronger direct watt/energy evidence if desired, and a cwd-independent Phase 11 MPV-boundary script.

**What's next:** Fresh next-milestone requirements and roadmap via `$gsd-new-milestone`.

---

## v1.0 MVP (Shipped: 2026-06-08)

**Phases completed:** 6 phases, 27 plans, 71 tasks

**Key accomplishments:**

- Pure monitoring state model with XCTest coverage for status vocabulary, mode copy, and enable/disable transitions
- Native MenuBarExtra shell with status, monitoring, mode, privacy, about, and quit controls
- Explicit camera permission handling and manual verification baseline for the status-bar shell
- Foundation-only timestamped attention reducer with deterministic debounce, recovery, jitter, and unsafe-input XCTest coverage
- Foundation-only playback ownership reducer emitting safe intents for speed hold/restore, pause/resume, and manual takeover stop-monitoring
- Scalar attention settings, graded calibration quality, safe replacement decisions, and UserDefaults-backed tuning persistence
- Local AVFoundation/Vision attention signal with a safe monitor coordinator and fake-service XCTest coverage
- Status-bar calibration and tuning controls backed by persisted settings and monitor-safe visible states
- Direct IINA/mpv JSON IPC client and adapter with safe unavailable mapping, speed command coverage, and live socket viability evidence
- Debounced attention to PlaybackPolicy to IINA adapter coordinator for owned speed hold and restore
- Owned IINA Pause/Resume commands with conservative manual takeover stop-monitoring behavior
- Status-bar player state is wired and tested; direct IPC is blocked in the sandboxed app, so the next real-control path is the IINA plugin bridge fallback.
- Bundled IINA plugin bridge and Swift adapter replaced the failed sandboxed direct IPC runtime path, with status freshness carried into 04-06 before Phase 4 closeout.
- Push-first IINA plugin status events now keep the GlanceHold menu fresh without one-second app-side polling or a second playback-command path.
- Neutral IINA bridge-waiting menu copy now replaces the misleading plugin-missing wording for unreachable setup states.
- The Phase 4 calibration and IINA status UAT blockers are code-fixed and ready for live retest from Test 3.
- Stable-window calibration with bounded camera sampling and privacy-safe diagnostics for the Phase 4 live retest blocker
- Pause/Resume manual pause now stops camera monitoring; Test 7 live retest passed
- SwiftUI tuning menus now show current values in parent labels and native checked child rows from a testable presentation model
- Focused status-bar menu and localization copy fixes for the three diagnosed Phase 5 UAT gaps.
- Confirmation-gated Last Action feedback for playback and safety events in the status-bar menu
- Disable and Quit cleanup now stop monitoring/camera ownership without restoring speed or resuming playback
- IINA-first user docs plus a scenario-organized manual UAT artifact for final real-camera and real-IINA closeout.
- Automated XCTest/build evidence plus real-camera and real-IINA UAT pass for v1 closeout

---
