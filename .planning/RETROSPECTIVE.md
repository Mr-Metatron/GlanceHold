# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.0 — MVP

**Shipped:** 2026-06-08
**Phases:** 6 | **Plans:** 27 | **Tasks:** 71

### What Was Built

- Status-bar-first macOS utility shell with explicit permission, calibration, monitoring, mode, and quit controls.
- Pure attention debounce and playback ownership reducers with focused XCTest coverage before side effects.
- Local AVFoundation/Vision camera attention pipeline with scalar calibration, tuning, persistence, and safe unavailable states.
- IINA-first playback control through a local plugin bridge, covering Speed Control and Pause/Resume with manual pause protection.
- Checked tuning/current-value menus, IINA shortcut toggle, English/Simplified Chinese localization, Last Action feedback, stop-only disable/quit cleanup, user docs, and final real-camera plus real-IINA UAT.

### What Worked

- Building pure reducers first made later camera and playback side effects easier to test and repair.
- The IINA plugin bridge became the right v1 integration boundary after sandboxed direct IPC proved unsuitable.
- Gap closure phases were useful for live UAT findings: calibration, IINA status drift, manual pause monitoring, and copy density all got closed without destabilizing the core flow.
- Final Phase 6 UAT provided a strong single source of truth for the real daily-use path.

### What Was Inefficient

- Some early phases predated the later formal `VERIFICATION.md` and `VALIDATION.md` conventions, so milestone closeout needed retroactive evidence cleanup.
- Phase 4 direct IPC exploration was necessary but took a detour before landing on the plugin bridge path.
- Several Phase 5 summaries lacked standard frontmatter, which made strict audit extraction weaker than the actual evidence.

### Patterns Established

- Keep privacy-sensitive camera work local, transient, and isolated behind service boundaries.
- Treat playback ownership as explicit policy state; never infer resume/restore rights from player state alone.
- Route secondary control surfaces, such as IINA shortcuts, through the same safe primary action resolver as the status-bar menu.
- Record real hardware/player UAT in dedicated artifacts when macOS permissions, camera behavior, or IINA runtime behavior cannot be fully simulated.

### Key Lessons

1. Formal verification artifacts should be created at each phase close, even when UAT or validation evidence already exists.
2. Summary frontmatter is not just bookkeeping; milestone automation depends on it.
3. For sandboxed macOS utilities, prove integration reachability early and be ready to use a companion/plugin boundary.
4. Stop-only cleanup on disable/quit is safer and clearer than trying to restore playback during shutdown.

### Cost Observations

- Commits in milestone window: 149.
- Model mix: not tracked in repo artifacts.
- Notable: live UAT issues clustered around user-facing copy, calibration robustness, and integration-state freshness rather than the pure policy core.

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Key Change |
|---|---:|---|
| v1.0 | 6 | Established the local IINA-first MVP and tightened formal closeout evidence. |

### Cumulative Quality

| Milestone | Verification | UAT | Notes |
|---|---|---|---|
| v1.0 | 6/6 phase verification artifacts passed | Real-camera and real-IINA UAT passed | Manual pause safety, speed restore, localization, disable, and quit flows verified. |

### Top Lessons (Verified Across Milestones)

1. Keep pure policy separate from side effects before integrating camera/player systems.
2. Treat live macOS/IINA behavior as a first-class verification surface.
