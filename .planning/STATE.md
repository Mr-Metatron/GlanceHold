---
gsd_state_version: 1.0
milestone: v1.2
milestone_name: Distribution and Public Release Readiness
status: executing
stopped_at: Completed 16-03-PLAN.md
last_updated: "2026-06-15T13:20:49.382Z"
last_activity: 2026-06-15
progress:
  total_phases: 5
  completed_phases: 4
  total_plans: 17
  completed_plans: 16
  percent: 80
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-13 after starting v1.2)

**Core value:** 当用户注意力离开屏幕时，GlanceHold 能可靠、克制地替用户处理视频速度或播放状态，并在用户回来时恢复到合适状态，且不误恢复用户手动暂停的视频。
**Current focus:** Phase 16 — release-verification-and-publication-hygiene

## Current Position

Phase: 16 (release-verification-and-publication-hygiene) — EXECUTING
Plan: 4 of 4
Status: Ready to execute
Last activity: 2026-06-15

Progress: [█████████░] 94%

## Performance Metrics

**Velocity:** v1.2 plans completed: 8; average duration: N/A; execution time: see phase summaries

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 12 | 4 | - | - |
| 13 | 3 | - | - |
| 14 | 2 | - | - |
| 15 | TBD | - | - |
| 16 | TBD | - | - |

**Recent Trend:** v1.1 shipped 2026-06-13; v1.2 Phases 12 through 15 are complete, and Phase 15 is ready for verification.

*Updated after each plan completion*
| Phase 12 P01 | 5 min | 3 tasks | 1 files |
| Phase 12 P03 | 5 min | 2 tasks | 1 files |
| Phase 12 P02 | 5 min | 2 tasks | 2 files |
| Phase 12 P04 | 7 min | 3 tasks | 3 files |
| Phase 13 P01 | 8 min | 3 tasks | 4 files |
| Phase 13 P02 | 13 min | 2 tasks | 2 files |
| Phase 13 P03 | 21 min | 3 tasks | 4 files |
| Phase 14 P01 | 3 min | 3 tasks | 4 files |
| Phase 14 P02 | 4 min | 2 tasks | 3 files |
| Phase 15 P01 | 5 min | 2 tasks | 1 files |
| Phase 15 P02 | 15 min | 3 tasks | 1 files |
| Phase 15 P03 | 5 min | 3 tasks | 3 files |
| Phase 15 P04 | 6 min | 2 tasks | 3 files |
| Phase 16 P01 | 3min | 2 tasks | 2 files |
| Phase 16 P02 | 8min | 2 tasks | 1 files |
| Phase 16 P03 | 5min | 3 tasks | 2 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: v1.2 continues numbering from Phase 12 after shipped v1.1 Phase 11.
- [Roadmap]: v1.2 is distribution/readiness work only; runtime attention and playback behavior changes stay out of scope.
- [Roadmap]: Coarse granularity maps 25 v1.2 requirements into 5 phases: public docs, packaging, trust evidence, plugin distribution, and release verification.
- [Release]: Generated DMG/checksum/manifest outputs are release artifacts only and must stay out of git.
- [Release]: Public copy must disclose actual signing/notarization status, local camera processing, local loopback IINA communication, and supported-player limits.
- [Phase 12]: README.md is the English public decision path before installation details. — Plan 12-01 made the root README useful before source-build steps.
- [Phase 12]: GitHub Release bodies remain the source of truth for per-release artifact, checksum, signing, and environment facts. — README links Latest Release and avoids hard-coded release-specific facts.
- [Phase 12]: Root README keeps bridge trust wording brief and links IINAPlugin/README.md for protocol details. — Detailed local loopback trust model remains in plugin-specific documentation.
- [Phase 12]: Source checkout copy commands and .iinaplugin-dev links remain documented only as source/development paths. — Public release docs should not make source-tree copy commands the only install story.
- [Phase 12]: The plugin trust model remains no-token local loopback plus the command whitelist, with the same-Mac connection caveat preserved. — This satisfies DOCS-02 and TRUST-04 without adding token setup or remote-host overclaims.
- [Phase 12]: IINAPlugin/README.md now directs public users to the matching plugin instructions or asset from the same GitHub Release as the app. — Plan 12-03 keeps release-user plugin guidance aligned with the root README release contract.
- [Phase 12]: README_zh.md mirrors README.md as the Simplified Chinese public decision path. — Plan 12-02 created a Chinese companion README with section parity to the English public release contract.
- [Phase 12]: Chinese release-user docs keep Latest Release as the source for exact app/plugin assets, checksums, and signing facts. — This preserves the Phase 12 rule that README files stay stable while GitHub Release bodies carry release-specific facts.
- [Phase 12]: Chinese bridge wording includes the 127.0.0.1:47873 local loopback caveat without no-network or privacy-review overclaims. — This satisfies DOCS-02 and TRUST-04 for Chinese readers while matching IINAPlugin/README.md trust boundaries.
- [Phase 12]: README.md keeps release-specific artifact facts in GitHub Release bodies while exposing a same-line required-field contract for automated verification. — Plan 12-04 fixed the release-body key-link pattern without hard-coding concrete app, plugin, protocol, DMG, checksum, or signing facts.
- [Phase 12]: README_zh.md uses the precise Chinese release-body field names required for parity with README.md. — Plan 12-04 aligned 应用版本/构建号 and IINA Bridge 插件版本 with the final bilingual release-body contract.
- [Phase 12]: IINAPlugin/README.md remains the detailed local loopback bridge trust-model source after final cross-doc validation. — Plan 12-04 verified the no-token wording, same-Mac caveat, command whitelist, protocol details, and update-needed guidance without needing a plugin README change.
- [Phase 13]: Generated release outputs are constrained to exact ignored roots dist/build/ and dist/releases/. — Plan 13-01 established the tracked-source versus generated-artifact boundary before archive/export and DMG creation are implemented.
- [Phase 13]: The package script accepts the final narrow flags but fails closed for default archive/export until Plan 13-02 enables those actions. — Plan 13-01 created the command surface and static preflight without pretending the full package run exists yet.
- [Phase 13]: Release id is derived from Release build settings before archive/export. — Plan 13-02 made GlanceHold-<MARKETING_VERSION>-build-<CURRENT_PROJECT_VERSION> the deterministic package identity.
- [Phase 13]: Archive derived data stays under the versioned dist/build release directory. — Plan 13-02 adds -derivedDataPath inside dist/build/<release-id>/ so archive/export intermediates remain generated artifacts.
- [Phase 13]: The skip-dmg flag is the Plan 13-02 archive/export smoke path. — DMG, checksum, and manifest generation stay fail-closed for Plan 13-03 while exported app validation is available now.
- [Phase 13]: The Phase 13 DMG contains only GlanceHold.app, an Applications symlink, and Install IINA Plugin.md; the IINA plugin body remains out of the app DMG. — Plan 13-03 finalized the minimal DMG contract and preserved Phase 15 ownership of plugin distribution.
- [Phase 13]: The release manifest records trust fields as pending-phase-14 and the plugin expected asset as pending-phase-15. — Plan 13-03 prevents signing/notarization or plugin-distribution overclaims before Phases 14 and 15.
- [Phase 13]: Generated release outputs remain under ignored dist/build/ and dist/releases/ and must not be committed. — Plan 13-03 verified real generated artifacts while keeping git status --short -- dist empty.
- [Phase 13]: Generated JSON manifests are validated with plutil-backed JSON extraction rather than plutil -lint. — This local plutil rejects non-empty JSON via lint while plutil extraction parses the manifest correctly.
- [Phase 14]: The v1.2 release trust path is documented as unsigned and not notarized. — Plan 14-01 locked the public release trust sentence in English and Chinese docs and kept manual macOS open handling explicit.
- [Phase 14]: GitHub Release body signing/notarization fields carry the same trust sentence as public install docs. — Plan 14-01 made the English and Chinese release-body contracts use concrete unsigned/manual-install wording instead of a bare status field.
- [Phase 14]: Generated manifests do not carry Apple trust fields for the selected unsigned/manual-install path. — Plan 14-01 moved trust status to README and GitHub Release body wording while leaving plugin asset alignment to Phase 15.
- [Phase 14]: Generated release manifests no longer include Apple trust fields. — Plan 14-02 made the package script emit app, artifact, source, environment, and plugin facts only.
- [Phase 14]: Static packaging verification rejects regressions to pending Phase 14 trust fields. — The verifier now checks docs, package script source, and optional generated manifests without running Developer ID tooling.
- [Phase 15]: IINA plugin packages are generated with the bundled iina-plugin pack command and published as release-named .iinaplgz assets. — Plan 15-01 implements the package-script distribution contract without custom zip logic.
- [Phase 15]: The same plugin_asset_name now drives the standalone asset, DMG asset, generated install pointer, and manifest expectedAssetName. — Plan 15-01 keeps app/plugin release pairing visually and mechanically aligned.
- [Phase 15]: [Phase 15]: User-reported PASS is accepted as Phase 15 UAT success for install plus bridge connectivity, while missing exact GUI prompt text remains recorded as absent. — Plan 15-02 checkpoint response was pass, but no exact prompt text, old-plugin path, restart method, or final row label was supplied.
- [Phase 15]: Phase 15 evidence stops before Speed Control and Pause/Resume behavior; those remain Phase 16 release verification. — Plan 15-02 only proves plugin install and bridge connectivity.
- [Phase 15]: Public release users are directed to install GlanceHoldBridge-<app-version>-build-<build>.iinaplgz from the same GitHub Release as the app DMG, or from the same DMG. — Plan 15-03 finalized the short English and Chinese release-user plugin path.
- [Phase 15]: GitHub Release bodies now carry plugin package filename, plugin version, and bridge protocol version as separate facts. — Plan 15-03 added the package filename field without adding plugin checksum or size promises.
- [Phase 15]: Public plugin docs do not quote exact IINA install prompt text. — Phase 15 UAT recorded PASS but did not supply exact GUI prompt wording, so Plan 15-03 kept wording conservative.
- [Phase 15]: Maintainer packaging docs now treat GlanceHoldBridge-<version>-build-<build>.iinaplgz as the official public plugin asset paired with the app DMG, manifest, and release id. — This keeps maintainer-facing release instructions aligned with the generated Phase 15 package script output.
- [Phase 15]: Plugin package filename, plugin.version, and plugin.bridgeProtocolVersion remain separate facts; Phase 15 does not add plugin checksum or size fields. — This preserves the Phase 15 manifest scope and avoids unsupported plugin integrity promises in release docs.
- [Phase 15]: The verifier enforces Phase 15 alignment across package script source, English/Chinese/plugin docs, docs/release-packaging.md, 15-UAT.md, and optional generated manifests. — A single static packaging gate now covers source, docs, UAT evidence, and generated manifest drift before Phase 16 release verification.
- [Phase 16]: Final release evidence order is source gates, full package verify, release gates, copied-app UAT from mounted DMG, then publication target hygiene. — Plan 16-01 documents the maintainer sequence before verifier implementation.
- [Phase 16]: GitHub Release body copy is a public reusable template under docs/ and excludes detailed UAT tables, GSD phase records, and private planning artifacts. — Plan 16-01 keeps public release notes limited to release facts and high-level verification.
- [Phase 16]: The --skip-dmg flag remains an archive/export smoke path and is not final release evidence. — Clean release evidence must come from a complete DMG, checksum, manifest, and matching plugin package set.
- [Phase 16]: Phase 16 release verification is split into source gates, generated release-set gates, and target-ref publication hygiene gates. — Plan 16-02 implemented scripts/verify_phase16_release.sh with explicit --source-gates, --release-gates, and --publication-gates modes.
- [Phase 16]: Publication hygiene checks inspect the explicit target ref tree instead of the current dev workspace. — Plan 16-02 requires --target-ref and validates it with git rev-parse plus git ls-tree.
- [Phase 16]: Plan 16-03 used new-build-number release_id=GlanceHold-1.2.0-build-1 and left old 0.1.0 dist outputs untouched. — Operator correction provided a source checkout with app/plugin version 1.2.0 and build 1; no Trash-first cleanup was needed.
- [Phase 16]: Release-candidate PASS evidence for 16-03 is source gates, full package verify without --skip-dmg, and release gates against dist/releases/GlanceHold-1.2.0-build-1. — The manifest source.gitSha matched the intended package SHA, source.gitDirty was false, and generated dist artifacts remained ignored/uncommitted.

### Pending Todos

None for v1.2 yet.

### Blockers/Concerns

- [Phase 16]: Final verification must exercise the mounted DMG and copied app, not only the source checkout.
- [Publication]: Keep `AGENTS.md`, private `.planning` subdirectories, and generated binary artifacts out of public release branches.

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| v2 players | Browser, VLC, QuickTime, and generic player support | Deferred | v1 roadmap |
| v2 convenience | Launch at login and diagnostics window | Deferred | v1 roadmap |
| v2 distribution | Sparkle auto-update, Homebrew cask, App Store/TestFlight, and CI release automation | Deferred | v1.2 scope |
| v2 model accuracy | SemiUHPE/model-based integration | Deferred | v1 roadmap |

## Session Continuity

Last session: 2026-06-15T13:20:49.139Z
Stopped at: Completed 16-03-PLAN.md
Resume file: None

## Operator Next Steps

- Start Phase 16 release verification when ready.
