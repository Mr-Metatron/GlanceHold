# Milestones

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
