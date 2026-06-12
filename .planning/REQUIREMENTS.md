# Requirements: GlanceHold v1.1 Runtime Reliability and Power Budget

**Defined:** 2026-06-09
**Core Value:** 当用户注意力离开屏幕时，GlanceHold 能可靠、克制地替用户处理视频速度或播放状态，并在用户回来时恢复到合适状态，且不误恢复用户手动暂停的视频。

## v1.1 Requirements

### Observability and Diagnostics

- [x] **OBS-01**: User can run GlanceHold normally without per-frame or repetitive log spam at default log levels.
- [x] **OBS-02**: Developer can correlate a monitoring session across camera, attention, playback, and bridge logs using a session identifier and monotonic event sequence.
- [x] **OBS-03**: Developer can diagnose attention-state surprises from structured state-machine transition logs that include raw signal class, previous state, next state, candidate state, threshold context, and whether a playback event was emitted.
- [x] **OBS-04**: Developer can inspect low-frequency runtime metrics for frames received, frames analyzed, analyzer rate, semantic state changes, playback snapshots, playback commands, dropped samples, and analysis latency.
- [x] **OBS-05**: Developer can enable high-detail diagnostics for targeted debugging without permanently changing normal-user logging behavior.

### Power Hot Path

- [x] **PWR-01**: User can monitor stable facing attention without Vision analysis running at camera frame rate.
- [x] **PWR-02**: User can remain in the same attention state without duplicate semantic notifications triggering repeated playback snapshots.
- [x] **PWR-03**: User can monitor IINA without stable-state playback checks creating high-frequency WebSocket round trips.
- [x] **PWR-04**: Developer can verify power hot-path behavior with fake high-frame-rate tests that bound analyzer calls, semantic notifications, playback snapshots, and commands.
- [x] **PWR-05**: User can compare before/after power behavior with a manual measurement checklist focused on the previously observed ~5W overhead.

### Playback Ownership Safety

- [x] **PLAY-01**: User can disable monitoring, quit GlanceHold, or switch modes without in-flight playback tasks later changing IINA speed or playback state.
- [x] **PLAY-02**: Developer can reason about playback coordinator state through actor, main-actor, or serial-executor isolation rather than unsynchronized mutable async state.
- [x] **PLAY-03**: User keeps GlanceHold-owned speed or pause ownership across transient confirmation snapshot failures when the command itself succeeded.
- [x] **PLAY-04**: User manual pause, play, or speed takeover remains protected and stops monitoring without unwanted restore or resume behavior.

### Attention and Calibration Semantics

- [x] **ATT-01**: User returning from looking away does not bypass recovery delay because of a brief ambiguous, unknown, or unavailable signal.
- [x] **ATT-02**: User sees sustained camera or Vision unavailability degrade to an unavailable state without confusing it with short transient uncertainty.
- [x] **ATT-03**: User can reset calibration without losing mode, sensitivity, delay, or threshold settings.
- [x] **ATT-04**: User calibration cannot be accepted as high quality from a tiny stable micro-window that does not meet minimum sample-count and duration requirements.
- [x] **ATT-05**: Developer can inspect calibration diagnostics including selected window duration, selected sample count, spread, quality, and failure reason.
- [x] **ATT-06**: UserDefaults settings are validated or migrated on load so corrupt, non-finite, negative, or out-of-range timing/threshold values cannot destabilize monitoring.

### IINA Bridge and Legacy Boundary

- [x] **BRDG-01**: User can use the local IINA bridge without manually copying a GlanceHold token into IINA plugin preferences.
- [x] **BRDG-02**: Developer can reason from an explicit local single-user bridge trust model that treats loopback transport, narrow commands, plugin enablement, and local-only diagnostics as the security boundary for v1.1.
- [x] **BRDG-03**: User sees protocol-distinct setup/auth bridge failures instead of `unauthorized` being collapsed into generic `IINA unavailable`.
- [x] **BRDG-04**: Developer can clearly see whether the legacy MPV IPC backend is removed from production or isolated as experimental code with a single shared status mapping path.
- [x] **BRDG-05**: Developer can test the revised bridge trust behavior with protocol-level tests, not only source-string checks.

### Verification and Regression Coverage

- [x] **VER-01**: Developer can run focused regression tests for concurrent stop-during-await, mode replacement, high-frequency fake camera input, ambiguous recovery, confirmation failure ownership, calibration micro-windows, settings validation, and bridge authentication.
- [x] **VER-02**: User can complete a real IINA plus camera UAT pass covering speed hold/restore, pause/resume, manual takeover, disable/quit cleanup, power observation, and diagnostic log capture.

## Future Requirements

### Distribution

- **DIST-01**: User can install a signed and notarized GlanceHold build.
- **DIST-02**: User can receive updates through a documented update path.

### Convenience

- **CONV-01**: User can configure launch at login.
- **CONV-02**: User can open a troubleshooting or diagnostics window from the menu bar.

### Player Expansion

- **PLYR-01**: User can control browser video with GlanceHold.
- **PLYR-02**: User can control VLC, QuickTime, or other local players through explicit player profiles.

## Out of Scope

| Feature | Reason |
|---------|--------|
| New player support in v1.1 | Runtime reliability and power must be stable for IINA before expanding integrations. |
| Distribution/signing/notarization | Important later, but does not address the current power and trust risks. |
| Full settings window | v1.1 may add diagnostic plumbing, but not a new settings surface unless required for verification. |
| Cloud logging or frame upload | Privacy requires all camera processing and diagnostics to remain local. |
| Eye tracking or gaze target detection | The product remains head-orientation and face-presence based. |
| Shipping SemiUHPE/model weights | Licensing and dependency risks remain outside the v1.1 hardening scope. |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| OBS-01 | Phase 7 | Complete |
| OBS-02 | Phase 7 | Complete |
| OBS-03 | Phase 7 | Complete |
| OBS-04 | Phase 7 | Complete |
| OBS-05 | Phase 7 | Complete |
| PWR-01 | Phase 8 | Complete |
| PWR-02 | Phase 8 | Complete |
| PWR-03 | Phase 8 | Complete |
| PWR-04 | Phase 8 | Complete |
| PWR-05 | Phase 11 | Complete |
| PLAY-01 | Phase 9 | Complete |
| PLAY-02 | Phase 9 | Complete |
| PLAY-03 | Phase 9 | Complete |
| PLAY-04 | Phase 9 | Complete |
| ATT-01 | Phase 10 | Complete |
| ATT-02 | Phase 10 | Complete |
| ATT-03 | Phase 10 | Complete |
| ATT-04 | Phase 10 | Complete |
| ATT-05 | Phase 10 | Complete |
| ATT-06 | Phase 10 | Complete |
| BRDG-01 | Phase 08.1 | Complete |
| BRDG-02 | Phase 08.1 | Complete |
| BRDG-03 | Phase 08.1 | Complete |
| BRDG-04 | Phase 11 | Complete |
| BRDG-05 | Phase 08.1, Phase 11 | Complete |
| VER-01 | Phase 11 | Complete |
| VER-02 | Phase 11 | Complete |

**Coverage:**
- v1.1 requirements: 27 total
- Mapped to phases: 27
- Unmapped: 0

---
*Requirements defined: 2026-06-09*
*Last updated: 2026-06-12 after Phase 11 cleanup evidence was accepted via automated regressions and Diagnostic counters were extracted from unified logs*
