# Roadmap: GlanceHold

## Milestones

- ✅ **v1.0 MVP** — Phases 1-6 (shipped 2026-06-08) — [archive](milestones/v1.0-ROADMAP.md)
- 🚧 **v1.1 Runtime Reliability and Power Budget** — Phases 7-11 plus inserted Phases 08.1 and 09.1 (gap closure inserted 2026-06-12)

## Phases

<details>
<summary>✅ v1.0 MVP (Phases 1-6) — SHIPPED 2026-06-08</summary>

- [x] Phase 1: Status-Bar Shell, Permission Trust, and Verification Baseline (3/3 plans) — completed 2026-06-06
- [x] Phase 2: Pure Attention State Machine and Playback Policy (2/2 plans) — completed 2026-06-05
- [x] Phase 3: Local Camera, Vision Signal, Calibration, and Tuning (3/3 plans) — completed 2026-06-06
- [x] Phase 4: IINA Adapter Spike and End-to-End Playback Control (10/10 plans) — completed 2026-06-07
- [x] Phase 5: Control Polish, IINA Shortcut, and i18n (5/5 plans) — completed 2026-06-08
- [x] Phase 6: End-to-End UX Hardening and Manual UAT (4/4 plans) — completed 2026-06-08

</details>

<details open>
<summary>🚧 v1.1 Runtime Reliability and Power Budget (Phases 7-11 plus inserted 08.1 and 09.1) — GAP CLOSURE INSERTED</summary>

- [x] Phase 7: Structured Runtime Logging and Diagnostics Foundation (5/5 plans) — completed 2026-06-09
- [x] Phase 8: Power Hot Path Sampling and Notification Deduplication — completed 2026-06-10
- [x] Phase 08.1: IINA bridge local trust model and setup-error UX (INSERTED) — completed 2026-06-10
- [x] Phase 9: Playback Coordinator Ownership and Async Safety — completed 2026-06-11
- [ ] Phase 09.1: Close gap: Phase 09 verification evidence (INSERTED) — not planned yet
- [x] Phase 10: Attention Semantics, Calibration Robustness, and Settings Validation — completed 2026-06-11
- [x] Phase 11: IINA Bridge Security, Legacy Boundary, and Reliability Verification — completed 2026-06-12

</details>

## v1.1 Phase Details

### Phase 7: Structured Runtime Logging and Diagnostics Foundation

**Goal:** Add default-quiet, structured runtime observability before changing the hot paths, so later power and playback fixes are measurable and occasional bugs leave useful breadcrumbs.

**Requirements:** OBS-01, OBS-02, OBS-03, OBS-04, OBS-05

**Success criteria:**

1. Normal monitoring does not emit per-frame or repeated stable-state logs at default levels.
2. Logs include a monitoring session identifier and sequence that can connect camera, attention, playback, and bridge events.
3. Attention state-machine transitions are logged only on meaningful transitions or diagnostic mode, with enough fields to explain recovery and playback emission decisions.
4. Stop or periodic summaries report frames received/analyzed, analyzer rate, semantic transitions, playback snapshots, commands, dropped samples, and analysis latency.
5. High-detail diagnostics can be enabled for targeted debugging without changing default user behavior.

### Phase 8: Power Hot Path Sampling and Notification Deduplication

**Goal:** Reduce the user-observed power overhead by decoupling camera frame rate from Vision analysis and ensuring stable attention states do not trigger repeated playback work.

**Requirements:** PWR-01, PWR-02, PWR-03, PWR-04

**Success criteria:**

1. Stable facing monitoring analyzes at a bounded low rate rather than every delivered camera frame.
2. Repeated identical attention states do not emit duplicate playback semantic notifications.
3. Stable-state playback snapshot and WebSocket round-trip counts are bounded by semantic changes or explicit low-frequency refresh.
4. Fake 30fps input tests assert analyzer, notification, snapshot, and command upper bounds.
5. Runtime metrics from Phase 7 show the expected reductions during tests.

### Phase 08.1: IINA bridge local trust model and setup-error UX (INSERTED)

**Goal:** Replace the rejected manual IINA bridge token/paste model with an explicit low-friction local trust model, clear setup/auth error states, and updated requirements before playback ownership work continues.
**Requirements**: BRDG-01, BRDG-02, BRDG-03, BRDG-05
**Depends on:** Phase 8
**Plans:** 6/6 plans complete
**Verification:** gap closure complete — see `08.1-06-SUMMARY.md`; re-run verification when ready

**Success criteria:**

1. Normal local IINA use does not require copying a token from GlanceHold into IINA plugin preferences.
2. The bridge threat model is documented as a local single-user loopback integration with a narrow protocol surface, not a general remote-control API.
3. If any auth/setup failure remains, GlanceHold surfaces a specific setup/auth state instead of collapsing `unauthorized` into generic `IINA unavailable`.
4. Bridge diagnostics and docs continue to avoid tokens, raw bridge payloads, media paths, media titles, camera frames, and raw Vision data.
5. Phase 11 inherits this trust model for final protocol tests and real IINA/camera verification rather than reintroducing manual pairing friction.

### Phase 9: Playback Coordinator Ownership and Async Safety

**Goal:** Make playback side effects serial, session-bound, and invalidated by stop, quit, and mode replacement so old tasks cannot control IINA after monitoring is no longer active.

**Requirements:** PLAY-01, PLAY-02, PLAY-03, PLAY-04

**Plans:** 3/3 plans complete

Plans:
**Wave 1**

- [x] 09-01-PLAN.md — Add async playback ownership regression harness and Wave 0 coverage

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 09-02-PLAN.md — Harden coordinator invalidation, serialization, and latest-state app scheduling

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 09-03-PLAN.md — Preserve ownership across transient confirmation failures and tighten manual takeover

**Success criteria:**

1. Playback coordinator mutable state is isolated through actor, main-actor, or a serial executor.
2. Stop, quit, and mode replacement invalidate in-flight `handleAttentionState` work before any command or callback can run.
3. Command success plus transient confirmation snapshot failure preserves GlanceHold ownership until a trusted follow-up snapshot or bounded retry resolves it.
4. Manual pause, play, and speed takeover still stop monitoring without restore/resume side effects.
5. Delayed fake adapter tests cover stop-during-snapshot, stop-during-execute, mode replacement, and confirmation failure paths.

### Phase 09.1: Close gap: Phase 09 verification evidence (INSERTED)

**Goal:** Create the missing Phase 09 verification artifact and confirm the v1.1 milestone audit no longer treats PLAY-01 through PLAY-04 as orphaned.
**Requirements**: PLAY-01, PLAY-02, PLAY-03, PLAY-04
**Depends on:** Phase 9
**Plans:** 1/1 plans complete

Plans:
- [x] 09.1-01-PLAN.md — Create Phase 09 verification evidence and confirm PLAY audit closure

### Phase 10: Attention Semantics, Calibration Robustness, and Settings Validation

**Goal:** Tighten the pure attention and calibration rules that can cause premature recovery, false high-quality calibration, or settings-driven instability.

**Requirements:** ATT-01, ATT-02, ATT-03, ATT-04, ATT-05, ATT-06

**Success criteria:**

1. `lookingAway -> ambiguous/unknown -> facing` cannot jump directly to `facing`; it must satisfy recovery delay.
2. Short transient unavailable signals are distinct from sustained unavailable state.
3. Reset Calibration removes only calibration and preserves mode, sensitivity, thresholds, and delays.
4. Calibration acceptance requires a stable window with minimum sample count and duration, not just a three-frame micro-window.
5. Calibration diagnostics expose selected window duration and continue to avoid storing or logging camera frames.
6. Settings load validates or migrates unsafe persisted values into bounded safe ranges.

### Phase 11: IINA Bridge Security, Legacy Boundary, and Reliability Verification

**Goal:** Close the milestone by verifying the revised local bridge trust boundary, clarifying the legacy MPV backend, and testing the whole runtime with automated stress tests plus real IINA/camera use.

**Requirements:** PWR-05, BRDG-01, BRDG-02, BRDG-03, BRDG-04, VER-01, VER-02

**Plans:** 5/5 plans executed; phase verification passed

Plans:
**Wave 1**

- [x] 11-01-PLAN.md — Extract shared playback types for production bridge independence
- [x] 11-03-PLAN.md — Add bridge no-token static and command-whitelist protocol gates
- [x] 11-04-PLAN.md — Build scalar ABBA resource sampler

**Wave 2** *(blocked on 11-01 completion)*

- [x] 11-02-PLAN.md — Isolate legacy MPV IPC from production target membership

**Wave 3** *(blocked on 11-02, 11-03, 11-04 completion)*

- [x] 11-05-PLAN.md — Complete automated closeout, real IINA/camera UAT, and Phase 8 back-reference

**Success criteria:**

1. Final bridge behavior matches the Phase 08.1 local trust model without requiring manual token copy/paste for normal use.
2. Setup/auth failures, if any remain, are protocol-distinct and user-visible instead of being reported as generic IINA unavailability.
3. Bridge security behavior is covered by protocol-level tests.
4. Legacy MPV IPC is either removed from production or isolated as experimental with shared mapping and clear comments/tests.
5. Full regression coverage includes concurrency, high-frequency input, attention semantics, calibration windows, settings validation, and bridge auth.
6. Manual UAT covers real IINA playback, real camera monitoring, disable/quit cleanup, diagnostic log capture, and before/after power observation.

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|---|---|---:|---|---|
| 1. Status-Bar Shell, Permission Trust, and Verification Baseline | v1.0 | 3/3 | Complete | 2026-06-06 |
| 2. Pure Attention State Machine and Playback Policy | v1.0 | 2/2 | Complete | 2026-06-05 |
| 3. Local Camera, Vision Signal, Calibration, and Tuning | v1.0 | 3/3 | Complete | 2026-06-06 |
| 4. IINA Adapter Spike and End-to-End Playback Control | v1.0 | 10/10 | Complete | 2026-06-07 |
| 5. Control Polish, IINA Shortcut, and i18n | v1.0 | 5/5 | Complete | 2026-06-08 |
| 6. End-to-End UX Hardening and Manual UAT | v1.0 | 4/4 | Complete | 2026-06-08 |
| 7. Structured Runtime Logging and Diagnostics Foundation | v1.1 | 5/5 | Complete    | 2026-06-09 |
| 8. Power Hot Path Sampling and Notification Deduplication | v1.1 | 6/6 | Complete   | 2026-06-10 |
| 08.1. IINA bridge local trust model and setup-error UX | v1.1 | 6/6 | Complete    | 2026-06-10 |
| 9. Playback Coordinator Ownership and Async Safety | v1.1 | 3/3 | Complete   | 2026-06-11 |
| 09.1. Close gap: Phase 09 verification evidence | v1.1 | 1/1 | Complete   | 2026-06-12 |
| 10. Attention Semantics, Calibration Robustness, and Settings Validation | v1.1 | 4/4 | Complete    | 2026-06-11 |
| 11. IINA Bridge Security, Legacy Boundary, and Reliability Verification | v1.1 | 5/5 | Complete | 2026-06-12 |

## Next

Plan urgent Phase 09.1 gap closure:

```bash
$gsd-plan-phase 09.1
```

Phase 11 is complete: live Speed Control, Pause/Resume, manual takeover, bridge setup/status, `phase11-abba` resource evidence, automated cleanup safety evidence, and DiagnosticRuntimeMetrics unified-log counters passed.
