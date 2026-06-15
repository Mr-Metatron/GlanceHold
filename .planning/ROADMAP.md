# Roadmap: GlanceHold

## Milestones

- ✅ **v1.0 MVP** — Phases 1-6 (shipped 2026-06-08)
- ✅ **v1.1 Runtime Reliability and Power Budget** — Phases 7-11 plus inserted Phases 08.1 and 09.1 (shipped 2026-06-13)
- 🚧 **v1.2 Distribution and Public Release Readiness** — Phases 12-16 (active)

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

<details>
<summary>✅ v1.1 Runtime Reliability and Power Budget (Phases 7-11 plus inserted 08.1 and 09.1) — SHIPPED 2026-06-13</summary>

- [x] Phase 7: Structured Runtime Logging and Diagnostics Foundation (5/5 plans) — completed 2026-06-09
- [x] Phase 8: Power Hot Path Sampling and Notification Deduplication (6/6 plans) — completed 2026-06-10
- [x] Phase 08.1: IINA bridge local trust model and setup-error UX (INSERTED, 6/6 plans) — completed 2026-06-10
- [x] Phase 9: Playback Coordinator Ownership and Async Safety (4/4 plans) — completed 2026-06-11
- [x] Phase 09.1: Close gap: Phase 09 verification evidence (INSERTED) — completed 2026-06-12
- [x] Phase 10: Attention Semantics, Calibration Robustness, and Settings Validation (4/4 plans) — completed 2026-06-11
- [x] Phase 11: IINA Bridge Security, Legacy Boundary, and Reliability Verification (5/5 plans) — completed 2026-06-12

</details>

### 🚧 v1.2 Distribution and Public Release Readiness (Active)

**Milestone Goal:** Prepare GlanceHold for a public/manual release with clear public documentation, repeatable DMG packaging, transparent trust status, a usable IINA plugin distribution path, and release verification from the final artifact.

- [x] **Phase 12: Public Release Contract and README** - Users can understand GlanceHold, its privacy boundary, compatibility limits, install flow, troubleshooting, and release-note truth before installing. (completed 2026-06-13)
- [x] **Phase 13: Archive Export, DMG Packaging, and Manifest** - Maintainers can produce a release app, versioned DMG, checksums, and manifest from a documented non-debug packaging flow. (completed 2026-06-13)
- [x] **Phase 14: Signing, Notarization, and Trust Evidence** - Maintainers can determine the available trust path and verify signing/notarization evidence when credentials exist. (completed 2026-06-13)
- [x] **Phase 15: IINA Plugin Distribution and Compatibility** - Users can obtain, install, and troubleshoot the matching IINA bridge plugin from public release materials. (completed 2026-06-13)
- [ ] **Phase 16: Release Verification and Publication Hygiene** - Maintainers can verify the packaged artifact, public claims, and clean publication branch before release.

## Phase Details

### Phase 12: Public Release Contract and README

**Goal**: Users can decide whether GlanceHold fits their IINA viewing workflow and can follow public documentation without reading internal project notes.
**Depends on**: Phase 11
**Requirements**: DOCS-01, DOCS-02, DOCS-03, DOCS-04, DOCS-05, TRUST-03, TRUST-04
**Success Criteria** (what must be TRUE):

  1. A new user can read the public README and understand GlanceHold's IINA-first attention-control workflow and intended audience.
  2. A new user can see the privacy boundary, local loopback IINA bridge disclosure, compatibility limits, non-eye-tracking scope, and unsupported-player limits before installing.
  3. A new user can follow public README instructions to install, launch, calibrate, choose a mode, and troubleshoot common setup states.
  4. A maintainer can prepare release notes that state artifact version, signing/notarization status, checksum availability, verified environment, and known limitations without overclaiming Apple review or network behavior.

**Plans**: 4 plans
Plans:
**Wave 1**

- [x] 12-01-PLAN.md — English public README contract
- [x] 12-03-PLAN.md — IINA plugin README trust-model alignment

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 12-02-PLAN.md — Simplified Chinese README companion

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 12-04-PLAN.md — Cross-document claim audit and validation

### Phase 13: Archive Export, DMG Packaging, and Manifest

**Goal**: Maintainers can produce a repeatable release DMG from a canonical exported app and record enough metadata for users to verify the artifact.
**Depends on**: Phase 12
**Requirements**: PKG-01, PKG-02, PKG-03, PKG-04, PKG-05
**Success Criteria** (what must be TRUE):

  1. A maintainer can produce the release `GlanceHold.app` from a documented Xcode archive/export path rather than a Debug build or ad hoc DerivedData copy.
  2. A maintainer can create a versioned DMG from the exported app with a predictable staging structure and install affordances.
  3. A maintainer can generate SHA-256 checksums and a release manifest containing git SHA, app version/build, macOS/Xcode versions, bundle ID, architectures, plugin version, and signing/notarization status.
  4. The packaging flow protects existing release outputs from silent overwrite and writes generated artifacts only under an ignored output root.
  5. A maintainer can distinguish tracked release scripts/docs from generated DMG, checksum, and manifest artifacts that must not be committed.

**Plans**: 3 plans
Plans:
**Wave 1**

- [x] 13-01-PLAN.md — Release packaging foundation and static safety gate

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 13-02-PLAN.md — Canonical archive/export and fail-closed layout

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 13-03-PLAN.md — DMG staging, checksum, manifest, and maintainer docs

### Phase 14: Signing, Notarization, and Trust Evidence

**Goal**: Maintainers can select and prove the actual release trust path instead of relying on assumptions about Developer ID availability.
**Depends on**: Phase 13
**Requirements**: TRUST-01, TRUST-02
**Success Criteria** (what must be TRUE):

  1. A maintainer can determine whether Developer ID signing/notarization credentials are available for the release.
  2. If Developer ID signing/notarization is available, a maintainer can capture and verify signing, notarization, stapling, and Gatekeeper evidence for the final artifacts.
  3. A maintainer can record the actual trust outcome so README and release-note wording can match the artifact being published.

**Plans**: 2 plans
Plans:
**Wave 1**

- [x] 14-01-PLAN.md — Unsigned/manual-install public and maintainer documentation contract

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 14-02-PLAN.md — Manifest writer and static verifier no-trust-fields contract

### Phase 15: IINA Plugin Distribution and Compatibility

**Goal**: Users can install the matching GlanceHold IINA bridge plugin through public release materials, and maintainers can prove the app/plugin pair is aligned.
**Depends on**: Phase 13
**Requirements**: PLUG-01, PLUG-02, PLUG-03, PLUG-04, PLUG-05
**Success Criteria** (what must be TRUE):

  1. A new user can obtain and install the matching GlanceHold IINA bridge plugin without reading internal source-tree instructions.
  2. A maintainer can keep app version, plugin version, bridge protocol version, DMG filename, README, release notes, and manifest aligned.
  3. A user can troubleshoot plugin missing, plugin update required, IINA restart, and local bridge availability states from public documentation.
  4. A maintainer can verify the chosen plugin distribution path on a clean or realistically fresh IINA setup.
  5. The release flow does not silently or invasively write into the user's IINA plugin directory without explicit user action.

**Plans**: 4 plans
Plans:
**Wave 1**

- [x] 16-01-PLAN.md — Release body template and final verification documentation

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 16-02-PLAN.md — Phase 16 release verifier script

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 16-03-PLAN.md — Automated release evidence and public claim audit

**Wave 4** *(blocked on Wave 3 completion)*

- [ ] 16-04-PLAN.md — Copied-app UAT and publication target hygiene

### Phase 16: Release Verification and Publication Hygiene

**Goal**: Maintainers can prove the public release candidate works from the packaged artifact and that the publication branch contains only intended public files.
**Depends on**: Phases 12-15
**Requirements**: REL-01, REL-02, REL-03, REL-04, REL-05, REL-06
**Success Criteria** (what must be TRUE):

  1. A maintainer can run the automated source verification gates required before packaging.
  2. A maintainer can verify the mounted DMG and copied app, proving the release artifact works rather than only the source checkout.
  3. Release verification covers camera permission, calibration, Speed Control, Pause/Resume, manual-pause safety, and localization sanity.
  4. A maintainer can audit public claims for privacy, supported player scope, signing/notarization status, and known limitations.
  5. A maintainer can verify publication branch hygiene and keep public release notes, checksums, and manifests separate from private planning or UAT artifacts.

**Plans**: TBD

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
| 9. Playback Coordinator Ownership and Async Safety | v1.1 | 4/4 | Complete   | 2026-06-11 |
| 09.1. Close gap: Phase 09 verification evidence | v1.1 | 1/1 | Complete    | 2026-06-12 |
| 10. Attention Semantics, Calibration Robustness, and Settings Validation | v1.1 | 4/4 | Complete    | 2026-06-11 |
| 11. IINA Bridge Security, Legacy Boundary, and Reliability Verification | v1.1 | 5/5 | Complete | 2026-06-12 |
| 12. Public Release Contract and README | v1.2 | 4/4 | Complete    | 2026-06-13 |
| 13. Archive Export, DMG Packaging, and Manifest | v1.2 | 3/3 | Complete    | 2026-06-13 |
| 14. Signing, Notarization, and Trust Evidence | v1.2 | 2/2 | Complete    | 2026-06-13 |
| 15. IINA Plugin Distribution and Compatibility | v1.2 | 4/4 | Complete   | 2026-06-13 |
| 16. Release Verification and Publication Hygiene | v1.2 | 3/4 | In Progress|  |

## Next

Run `$gsd-verify-work 15`, then continue with Phase 16 release verification planning.
