# Release Packaging

This document is the maintainer guide for the current GlanceHold packaging path after the Phase 15 IINA plugin distribution alignment. It describes tracked source artifacts, ignored generated outputs, the matched app/plugin release set, and the release facts maintainers carry into the GitHub Release body before publication.

## Canonical Command

Run the packaging flow from the repository root:

```zsh
scripts/package_release.sh --verify
```

`--verify` runs the packaging source preflight and then performs the real archive/export, plugin package, DMG, checksum, and manifest flow. Use `scripts/package_release.sh --verify --skip-dmg` only when you intentionally want to stop after archive/export validation.

## Final Release Verification

Use this order for final Phase 16 release evidence:

1. Run source gates before packaging:

   ```zsh
   scripts/verify_phase16_release.sh --source-gates
   ```

2. Generate the complete release set:

   ```zsh
   scripts/package_release.sh --verify
   ```

3. Verify the generated release artifacts:

   ```zsh
   scripts/verify_phase16_release.sh --release-gates --release-dir dist/releases/<release-id>
   ```

4. Complete copied-app UAT from the mounted DMG. Mount the generated DMG, copy
   `GlanceHold.app` from the mounted volume into `/Applications`, install the
   matching `.iinaplgz` with IINA, then verify camera permission/calibration,
   Speed Control, Pause/Resume, manual-pause safety, and localization sanity
   against that copied app.

5. Verify the clean publication target tree before release:

   ```zsh
   scripts/verify_phase16_release.sh --publication-gates --target-ref <clean-publication-ref>
   ```

`--skip-dmg` is only an archive/export smoke path and is not final release evidence. Final release evidence must come from the complete `scripts/package_release.sh --verify` release set: DMG, `.dmg.sha256`, manifest, and matching `.iinaplgz`.

## Evidence Publication Boundary

Public GitHub Release notes include artifacts, checksum, environment, known limitations, and a high-level verification result. Use `docs/release-body-template.md` as the reusable public template, filled from the generated manifest/checksum facts and final verification summary.

Detailed evidence remains local/private. Keep `.planning/phases/16-release-verification-and-publication-hygiene/16-UAT.md`, `.planning/phases/16-release-verification-and-publication-hygiene/16-CLAIM-AUDIT.md`, and `.planning/phases/16-release-verification-and-publication-hygiene/16-RELEASE-EVIDENCE.md` as maintainer evidence, not public release-note content.

Generated release outputs remain artifact facts for the public release body and generated files under `dist/`. They are not source documentation and must stay out of git.

## Tracked Source Artifacts

These files are maintained in git:

- `scripts/package_release.sh` - canonical release packaging command.
- `scripts/verify_phase13_packaging.sh` - static and optional generated-artifact packaging verifier.
- `ReleasePackaging/ExportOptions.plist` - Xcode archive export configuration.
- `docs/release-packaging.md` - this maintainer packaging guide.

## Generated Output Boundary

Generated packaging output belongs only under these ignored roots:

- `dist/build/`
- `dist/releases/`

The release directory pattern is:

```text
dist/releases/GlanceHold-<version>-build-<build>/
```

For a release id such as `GlanceHold-<version>-build-<build>`, the generated release directory contains:

- `<release-id>.dmg`
- `<release-id>.dmg.sha256`
- `<release-id>.manifest.json`
- `GlanceHoldBridge-<version>-build-<build>.iinaplgz`

For example, `scripts/package_release.sh --verify` creates a matched set under `dist/releases/<release-id>/`: `GlanceHold-<version>-build-<build>.dmg`, `GlanceHold-<version>-build-<build>.dmg.sha256`, `GlanceHold-<version>-build-<build>.manifest.json`, and standalone `GlanceHoldBridge-<version>-build-<build>.iinaplgz`.

Generated archives, exports, staging directories, DMGs, checksums, manifests, plugin packages, and all `dist/` outputs must not be committed. Before committing packaging work, confirm generated release artifacts are still ignored with:

```zsh
git status --short -- dist
```

## Overwrite And Cleanup Rules

The packaging script fails closed when a build directory, release directory, staging path, DMG, checksum, manifest, or plugin package already exists. It must not overwrite, auto-suffix, or move old outputs aside during a normal packaging run.

If you need to clear generated output from this workspace, use macOS Trash:

```zsh
/usr/bin/trash "dist/build/<release-id>"
/usr/bin/trash "dist/releases/<release-id>"
```

Do not use permanent deletion commands for workspace cleanup.

The packaging script stages release assets only under `dist/`. It does not silently modify the user's IINA plugin directory. If a manual verification run needs to remove an old installed GlanceHold Bridge plugin, move that old object to macOS Trash with `/usr/bin/trash` before installing the release `.iinaplgz`.

## DMG Contents

The app DMG is intentionally minimal:

- `GlanceHold.app`
- `Applications` symlink to `/Applications`
- `Install IINA Plugin.md`
- `GlanceHoldBridge-<version>-build-<build>.iinaplgz`

The DMG does not contain `GlanceHoldBridge.iinaplugin`. Public release surfaces expose only the packed `.iinaplgz` package. `Install IINA Plugin.md` tells users to use the app and plugin package from the same DMG or from the same GitHub Release, open/install the `.iinaplgz` with IINA, restart IINA, confirm `GlanceHold Bridge` is enabled, and then return to GlanceHold.

## Manifest And Release Facts

The manifest records app, artifact, source, environment, and plugin fields. It records the final DMG SHA-256 in `artifact.sha256`, while the sibling `.dmg.sha256` file carries the same digest for user verification.

The manifest does not include Apple trust fields. Unsigned/manual-install trust status belongs in README and GitHub Release body wording as `Unsigned and not notarized; install requires macOS manual open / Open Anyway.`

Plugin release-asset alignment is part of the generated release set:

- `plugin.expectedAssetName`: the concrete `GlanceHoldBridge-<version>-build-<build>.iinaplgz` filename.
- `plugin.version`: the GlanceHold Bridge plugin version read from `IINAPlugin/GlanceHoldBridge.iinaplugin/Info.json`.
- `plugin.bridgeProtocolVersion`: the bridge protocol version read from `IINAPlugin/GlanceHoldBridge.iinaplugin/main.js`.

The plugin package filename, plugin version, and bridge protocol version are separate facts. The manifest does not add `.iinaplgz` SHA-256 or byte-count fields under `plugin`; the Phase 15 plugin contract is expected asset name plus version and protocol facts.

The generated manifest and checksum provide release facts for the GitHub Release body. The GitHub Release body remains the public source of truth for exact app asset, matching `.iinaplgz` asset, app SHA-256 checksum, signing/notarization status, verified environment, and known limitations. Do not mix app DMGs and plugin packages from different releases.
