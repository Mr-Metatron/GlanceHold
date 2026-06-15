#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PACKAGE_SCRIPT="scripts/package_release.sh"
EXPORT_OPTIONS_PLIST="ReleasePackaging/ExportOptions.plist"
GITIGNORE_FILE=".gitignore"
DOCS_FILE="docs/release-packaging.md"
README_FILE="README.md"
README_ZH_FILE="README_zh.md"
PLUGIN_README_FILE="IINAPlugin/README.md"
PHASE15_UAT_FILE=".planning/phases/15-iina-plugin-distribution-and-compatibility/15-UAT.md"

failures=0
REQUIRE_GENERATED=false

usage() {
  cat <<'USAGE'
Usage:
  scripts/verify_phase13_packaging.sh [--require-generated]

Options:
  --require-generated  Fail when no generated release manifest is present.
  --help, -h           Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --require-generated)
      REQUIRE_GENERATED=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'error: unknown option: %s\n' "$1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

pass() {
  printf 'PASS: %s\n' "$1"
}

require_file() {
  local path="$1"
  if [ -f "$path" ]; then
    pass "$path exists"
  else
    fail "$path is missing"
  fi
}

require_executable() {
  local path="$1"
  if [ -x "$path" ]; then
    pass "$path is executable"
  else
    fail "$path is not executable"
  fi
}

require_fixed_match() {
  local needle="$1"
  local path="$2"
  local description="$3"
  if grep -Fq -- "$needle" "$path"; then
    pass "$description"
  else
    fail "$description"
  fi
}

require_exact_line() {
  local needle="$1"
  local path="$2"
  local description="$3"
  if grep -Fxq -- "$needle" "$path"; then
    pass "$description"
  else
    fail "$description"
  fi
}

require_regex_match() {
  local pattern="$1"
  local path="$2"
  local description="$3"
  if grep -Eq -- "$pattern" "$path"; then
    pass "$description"
  else
    fail "$description"
  fi
}

require_regex_absent() {
  local pattern="$1"
  local path="$2"
  local description="$3"
  local matches
  matches="$(grep -En -- "$pattern" "$path" || true)"
  if [ -n "$matches" ]; then
    printf 'Forbidden %s in %s:\n%s\n' "$description" "$path" "$matches" >&2
    fail "$description"
  else
    pass "$description"
  fi
}

require_manifest_key_absent() {
  local manifest_path="$1"
  local key="$2"
  local description="$3"
  if plutil -extract "$key" raw "$manifest_path" >/dev/null 2>&1; then
    fail "$description"
  else
    pass "$description"
  fi
}

require_manifest_sha_match() {
  local manifest_path="$1"
  local release_dir
  local sha_file_name
  local dmg_file_name
  local manifest_sha
  local checksum_sha
  local actual_sha
  local plugin_expected_asset
  local plugin_asset_path
  local plugin_version
  local plugin_bridge_protocol_version
  local app_version
  local app_build
  local expected_release_id
  local expected_plugin_asset
  release_dir="$(dirname "$manifest_path")"

  if ! plutil -extract schemaVersion raw "$manifest_path" >/dev/null; then
    fail "$manifest_path passes plutil JSON parse"
    return
  fi
  pass "$manifest_path passes plutil JSON parse"

  if plutil -extract trust raw "$manifest_path" >/dev/null 2>&1; then
    fail "$manifest_path omits top-level trust object"
  else
    pass "$manifest_path omits top-level trust object"
  fi

  if grep -Fq -- "pending-phase-14" "$manifest_path"; then
    fail "$manifest_path omits pending Phase 14 trust placeholder"
  else
    pass "$manifest_path omits pending Phase 14 trust placeholder"
  fi

  if grep -Eq -- "pending-phase-15|phase15AlignmentNote" "$manifest_path"; then
    fail "$manifest_path omits pending Phase 15 plugin placeholder fields"
  else
    pass "$manifest_path omits pending Phase 15 plugin placeholder fields"
  fi

  plugin_expected_asset="$(plutil -extract plugin.expectedAssetName raw "$manifest_path" 2>/dev/null || true)"
  if [[ "$plugin_expected_asset" =~ ^GlanceHoldBridge-.+-build-.+\.iinaplgz$ ]]; then
    pass "$manifest_path uses concrete plugin.expectedAssetName .iinaplgz"
  else
    fail "$manifest_path uses concrete plugin.expectedAssetName .iinaplgz"
  fi

  app_version="$(plutil -extract app.version raw "$manifest_path" 2>/dev/null || true)"
  app_build="$(plutil -extract app.build raw "$manifest_path" 2>/dev/null || true)"
  if [ -n "$app_version" ] && [ -n "$app_build" ]; then
    pass "$manifest_path exposes app version/build for plugin asset matching"
    expected_release_id="GlanceHold-${app_version}-build-${app_build}"
    expected_plugin_asset="GlanceHoldBridge-${app_version}-build-${app_build}.iinaplgz"

    if [ "$(basename "$release_dir")" = "$expected_release_id" ]; then
      pass "$manifest_path release directory matches app version/build"
    else
      fail "$manifest_path release directory matches app version/build"
    fi

    if [ "$plugin_expected_asset" = "$expected_plugin_asset" ]; then
      pass "$manifest_path plugin.expectedAssetName matches app version/build"
    else
      fail "$manifest_path plugin.expectedAssetName matches app version/build"
    fi
  else
    fail "$manifest_path exposes app version/build for plugin asset matching"
  fi

  plugin_asset_path="$release_dir/$plugin_expected_asset"
  if [ -f "$plugin_asset_path" ]; then
    pass "$plugin_asset_path exists beside generated manifest"
  else
    fail "$plugin_asset_path exists beside generated manifest"
  fi

  plugin_version="$(plutil -extract plugin.version raw "$manifest_path" 2>/dev/null || true)"
  if [ -n "$plugin_version" ]; then
    pass "$manifest_path exposes plugin.version"
  else
    fail "$manifest_path exposes plugin.version"
  fi

  plugin_bridge_protocol_version="$(plutil -extract plugin.bridgeProtocolVersion raw "$manifest_path" 2>/dev/null || true)"
  if [[ "$plugin_bridge_protocol_version" =~ ^[0-9]+$ ]]; then
    pass "$manifest_path exposes numeric plugin.bridgeProtocolVersion"
  else
    fail "$manifest_path exposes numeric plugin.bridgeProtocolVersion"
  fi

  require_manifest_key_absent "$manifest_path" "plugin.sha256" "$manifest_path omits plugin.sha256"
  require_manifest_key_absent "$manifest_path" "plugin.sha256FileName" "$manifest_path omits plugin.sha256FileName"
  require_manifest_key_absent "$manifest_path" "plugin.checksum" "$manifest_path omits plugin.checksum"
  require_manifest_key_absent "$manifest_path" "plugin.sizeBytes" "$manifest_path omits plugin.sizeBytes"
  require_manifest_key_absent "$manifest_path" "plugin.byteCount" "$manifest_path omits plugin.byteCount"

  dmg_file_name="$(plutil -extract artifact.dmgFileName raw "$manifest_path" 2>/dev/null || true)"
  sha_file_name="$(plutil -extract artifact.sha256FileName raw "$manifest_path" 2>/dev/null || true)"
  manifest_sha="$(plutil -extract artifact.sha256 raw "$manifest_path" 2>/dev/null || true)"
  if [ -z "$dmg_file_name" ] || [ -z "$sha_file_name" ] || [ -z "$manifest_sha" ]; then
    fail "$manifest_path exposes artifact sha256 fields"
    return
  fi

  if [ ! -f "$release_dir/$dmg_file_name" ]; then
    fail "$release_dir/$dmg_file_name exists for $manifest_path"
    return
  fi

  if [ ! -f "$release_dir/$sha_file_name" ]; then
    fail "$release_dir/$sha_file_name exists for $manifest_path"
    return
  fi

  checksum_sha="$(awk '{ print $1; exit }' "$release_dir/$sha_file_name")"
  actual_sha="$(shasum -a 256 "$release_dir/$dmg_file_name" | awk '{ print $1; exit }')"
  if [ "$manifest_sha" = "$checksum_sha" ] && [ "$manifest_sha" = "$actual_sha" ]; then
    pass "$manifest_path artifact.sha256 matches $sha_file_name and $dmg_file_name"
  else
    fail "$manifest_path artifact.sha256 matches $sha_file_name and $dmg_file_name"
  fi
}

check_generated_manifest_artifacts() {
  local found_manifest=false
  local manifest_path
  for manifest_path in dist/releases/GlanceHold-*-build-*/*.manifest.json; do
    [ -e "$manifest_path" ] || continue
    found_manifest=true
    require_manifest_sha_match "$manifest_path"
  done

  if [ "$REQUIRE_GENERATED" = true ] && [ "$found_manifest" = false ]; then
    fail "generated release manifest is required"
  fi
}

require_command_pass() {
  local description="$1"
  shift
  if "$@" >/dev/null; then
    pass "$description"
  else
    fail "$description"
  fi
}

require_file "$PACKAGE_SCRIPT"
require_file "$EXPORT_OPTIONS_PLIST"
require_file "$GITIGNORE_FILE"
require_file "$DOCS_FILE"
require_file "$README_FILE"
require_file "$README_ZH_FILE"
require_file "$PLUGIN_README_FILE"
if [ -f "$PHASE15_UAT_FILE" ]; then
  pass "$PHASE15_UAT_FILE exists"
else
  pass "$PHASE15_UAT_FILE absent in clean publication tree; skipping private UAT evidence checks"
fi
require_executable "$PACKAGE_SCRIPT"

require_command_pass "ExportOptions.plist passes plutil lint" plutil -lint "$EXPORT_OPTIONS_PLIST"
require_command_pass "package_release.sh help exits successfully" bash "$PACKAGE_SCRIPT" --help

require_fixed_match "mac-application" "$EXPORT_OPTIONS_PLIST" "export options use mac-application method"
require_fixed_match "<key>destination</key>" "$EXPORT_OPTIONS_PLIST" "export options declare destination"
require_fixed_match "<string>export</string>" "$EXPORT_OPTIONS_PLIST" "export options set export destination"
require_fixed_match "stripSwiftSymbols" "$EXPORT_OPTIONS_PLIST" "export options strip Swift symbols"

require_exact_line "dist/build/" "$GITIGNORE_FILE" ".gitignore contains dist/build/"
require_exact_line "dist/releases/" "$GITIGNORE_FILE" ".gitignore contains dist/releases/"

require_fixed_match "scripts/package_release.sh" "$DOCS_FILE" "docs name tracked package script"
require_fixed_match "scripts/verify_phase13_packaging.sh" "$DOCS_FILE" "docs name tracked packaging verifier"
require_fixed_match "ReleasePackaging/ExportOptions.plist" "$DOCS_FILE" "docs name tracked export options"
require_fixed_match "docs/release-packaging.md" "$DOCS_FILE" "docs name tracked packaging guide"
require_fixed_match "scripts/package_release.sh --verify" "$DOCS_FILE" "docs name canonical package verify command"
require_fixed_match "dist/build/" "$DOCS_FILE" "docs name generated build root"
require_fixed_match "dist/releases/" "$DOCS_FILE" "docs name generated release root"
require_fixed_match "GlanceHold-<version>-build-<build>" "$DOCS_FILE" "docs name release directory pattern"
require_fixed_match ".dmg" "$DOCS_FILE" "docs name DMG artifact"
require_fixed_match ".dmg.sha256" "$DOCS_FILE" "docs name checksum artifact"
require_fixed_match ".manifest.json" "$DOCS_FILE" "docs name manifest artifact"
require_fixed_match "GlanceHoldBridge-<version>-build-<build>.iinaplgz" "$DOCS_FILE" "docs name official .iinaplgz plugin asset"
require_fixed_match "/usr/bin/trash" "$DOCS_FILE" "docs require Trash-first cleanup"
require_fixed_match "The manifest records app, artifact, source, environment, and plugin fields." "$DOCS_FILE" "docs state no-trust-fields manifest contract"
require_fixed_match "Unsigned and not notarized; install requires macOS manual open / Open Anyway." "$DOCS_FILE" "docs state unsigned manual-install trust path"
require_fixed_match 'Generated archives, exports, staging directories, DMGs, checksums, manifests, plugin packages, and all `dist/` outputs must not be committed.' "$DOCS_FILE" "docs prohibit committing generated release outputs"
require_fixed_match "The DMG does not contain \`GlanceHoldBridge.iinaplugin\`" "$DOCS_FILE" "docs state source plugin folder is not in the DMG"
require_fixed_match "same DMG or from the same GitHub Release" "$DOCS_FILE" "docs require same-DMG or same-release plugin guidance"
require_fixed_match "plugin.expectedAssetName" "$DOCS_FILE" "docs describe manifest plugin.expectedAssetName"
require_fixed_match "plugin.version" "$DOCS_FILE" "docs describe plugin.version separately"
require_fixed_match "plugin.bridgeProtocolVersion" "$DOCS_FILE" "docs describe plugin.bridgeProtocolVersion separately"
require_fixed_match "does not add \`.iinaplgz\` SHA-256 or byte-count fields under \`plugin\`" "$DOCS_FILE" "docs reject plugin checksum and size manifest fields"
require_fixed_match "does not silently modify the user's IINA plugin directory" "$DOCS_FILE" "docs forbid silent user plugin directory modification"
require_fixed_match "GitHub Release body" "$DOCS_FILE" "docs connect generated facts to release body"
require_regex_absent 'pending-phase-14' "$DOCS_FILE" "pending Phase 14 trust placeholder is absent from docs"
require_regex_absent 'pending-phase-15|phase15AlignmentNote' "$DOCS_FILE" "pending Phase 15 plugin placeholder is absent from docs"
require_regex_absent 'trust\.signingStatus' "$DOCS_FILE" "trust.signingStatus doc key is absent"
require_regex_absent 'trust\.notarizationStatus' "$DOCS_FILE" "trust.notarizationStatus doc key is absent"
require_regex_absent 'trust\.staplingStatus' "$DOCS_FILE" "trust.staplingStatus doc key is absent"

require_fixed_match "GlanceHoldBridge-<app-version>-build-<build>.iinaplgz" "$README_FILE" "English README names release plugin package filename"
require_fixed_match "IINA Bridge plugin package filename" "$README_FILE" "English README release body requires plugin package filename"
require_fixed_match "same GitHub Release as the app, or from the same DMG" "$README_FILE" "English README requires same-release or same-DMG pairing"
require_fixed_match "open/install it with IINA, restart IINA, confirm \`GlanceHold Bridge\` is enabled" "$README_FILE" "English README gives restart and enabled guidance"
require_fixed_match "Detailed plugin instructions live in [IINAPlugin/README.md](IINAPlugin/README.md)" "$README_FILE" "English README points to detailed plugin docs"
require_fixed_match "source-tree plugin and development-link path are for development and local testing, not the default release-user path" "$README_FILE" "English README keeps .iinaplugin source path development-only"
require_fixed_match "IINA bridge plugin version" "$README_FILE" "English README keeps plugin version separate"
require_fixed_match "Bridge protocol version" "$README_FILE" "English README keeps bridge protocol version separate"
require_regex_absent 'plugin checksum|plugin SHA-256|IINA Bridge plugin checksum|IINA Bridge plugin SHA-256' "$README_FILE" "English README release body avoids plugin checksum requirement"

require_fixed_match "GlanceHoldBridge-<app-version>-build-<build>.iinaplgz" "$README_ZH_FILE" "Chinese README names release plugin package filename"
require_fixed_match "IINA Bridge 插件包文件名" "$README_ZH_FILE" "Chinese README release body requires plugin package filename"
require_fixed_match "同一个 GitHub Release" "$README_ZH_FILE" "Chinese README requires same-release pairing"
require_fixed_match "同一个 DMG" "$README_ZH_FILE" "Chinese README requires same-DMG pairing"
require_fixed_match "用 IINA 打开/安装它，重启 IINA，在 IINA 中确认 \`GlanceHold Bridge\` 已启用" "$README_ZH_FILE" "Chinese README gives restart and enabled guidance"
require_fixed_match "详细插件说明见 [IINAPlugin/README.md](IINAPlugin/README.md)" "$README_ZH_FILE" "Chinese README points to detailed plugin docs"
require_fixed_match "源码树中的插件文件和开发链接路径只用于开发和本地测试，不是默认的 release 用户路径" "$README_ZH_FILE" "Chinese README keeps .iinaplugin source path development-only"
require_fixed_match "IINA Bridge 插件版本" "$README_ZH_FILE" "Chinese README keeps plugin version separate"
require_fixed_match "桥接协议版本" "$README_ZH_FILE" "Chinese README keeps bridge protocol version separate"
require_regex_absent '插件包校验和|插件包 SHA-256|IINA Bridge 插件.*校验和|IINA Bridge 插件.*SHA-256' "$README_ZH_FILE" "Chinese README release body avoids plugin checksum requirement"

require_fixed_match "Public Release Package" "$PLUGIN_README_FILE" "plugin README has public release package section"
require_fixed_match "Source/Development Install" "$PLUGIN_README_FILE" "plugin README keeps source install separate"
require_fixed_match "GlanceHoldBridge-<app-version>-build-<build>.iinaplgz" "$PLUGIN_README_FILE" "plugin README names release plugin package filename"
require_fixed_match "same GitHub Release as \`GlanceHold-<app-version>-build-<build>.dmg\`, or use the \`.iinaplgz\` included in the same DMG" "$PLUGIN_README_FILE" "plugin README requires same-release or same-DMG pairing"
require_fixed_match "Restart IINA" "$PLUGIN_README_FILE" "plugin README gives restart guidance"
require_fixed_match "Confirm \`GlanceHold Bridge\` is enabled" "$PLUGIN_README_FILE" "plugin README gives enabled guidance"
require_fixed_match "Do not mix app and plugin files from different releases" "$PLUGIN_README_FILE" "plugin README rejects cross-release mixing"
require_fixed_match "Speed Control and Pause/Resume playback behavior are verified by the release verification workflow" "$PLUGIN_README_FILE" "plugin README keeps playback behavior in release verification scope"
require_regex_absent 'plugin checksum|plugin SHA-256|plugin package checksum|plugin package SHA-256' "$PLUGIN_README_FILE" "plugin README avoids plugin checksum requirement"

if [ -f "$PHASE15_UAT_FILE" ]; then
  require_fixed_match "real or realistically fresh IINA smoke" "$PHASE15_UAT_FILE" "UAT records fresh IINA smoke scope"
  require_fixed_match "Observed IINA GUI Behavior" "$PHASE15_UAT_FILE" "UAT records GUI behavior evidence"
  require_fixed_match "Old Plugin Trash Precondition" "$PHASE15_UAT_FILE" "UAT records old-plugin precondition"
  require_fixed_match "/usr/bin/trash" "$PHASE15_UAT_FILE" "UAT requires Trash-first old-plugin cleanup"
  require_fixed_match "Generated Asset Under Test" "$PHASE15_UAT_FILE" "UAT records asset source"
  require_fixed_match "Install Steps" "$PHASE15_UAT_FILE" "UAT records install steps"
  require_fixed_match "IINA Restart" "$PHASE15_UAT_FILE" "UAT records IINA restart"
  require_fixed_match "Plugin Enabled Status" "$PHASE15_UAT_FILE" "UAT records plugin enabled status"
  require_fixed_match "GlanceHold Bridge Connectivity" "$PHASE15_UAT_FILE" "UAT records bridge connectivity"
  require_fixed_match "Connectivity pass criteria met | PASS" "$PHASE15_UAT_FILE" "UAT records install plus bridge connectivity pass"
  require_fixed_match "Speed Control playback behavior is Phase 16 release verification" "$PHASE15_UAT_FILE" "UAT keeps Speed Control in Phase 16"
  require_fixed_match "Pause/Resume playback behavior is Phase 16 release verification" "$PHASE15_UAT_FILE" "UAT keeps Pause/Resume in Phase 16"
  require_fixed_match "Result: PASS" "$PHASE15_UAT_FILE" "UAT records pass/fail result"
else
  pass "UAT private evidence checks skipped in clean publication tree"
fi

require_fixed_match 'PROJECT_FILE="GlanceHold.xcodeproj"' "$PACKAGE_SCRIPT" "package script fixes project file"
require_fixed_match 'SCHEME="GlanceHold"' "$PACKAGE_SCRIPT" "package script fixes scheme"
require_fixed_match 'CONFIGURATION="Release"' "$PACKAGE_SCRIPT" "package script fixes Release configuration"
require_fixed_match 'BUILD_ROOT="dist/build"' "$PACKAGE_SCRIPT" "package script fixes build root"
require_fixed_match 'RELEASE_ROOT="dist/releases"' "$PACKAGE_SCRIPT" "package script fixes release root"
require_fixed_match 'EXPORT_OPTIONS_PLIST="ReleasePackaging/ExportOptions.plist"' "$PACKAGE_SCRIPT" "package script fixes export options path"
require_fixed_match "xcodebuild archive" "$PACKAGE_SCRIPT" "package script names xcodebuild archive"
require_fixed_match "xcodebuild -exportArchive" "$PACKAGE_SCRIPT" "package script names xcodebuild -exportArchive"
require_fixed_match "xcodebuild -showBuildSettings" "$PACKAGE_SCRIPT" "package script reads Release build settings"
require_fixed_match "MARKETING_VERSION" "$PACKAGE_SCRIPT" "package script reads MARKETING_VERSION"
require_fixed_match "CURRENT_PROJECT_VERSION" "$PACKAGE_SCRIPT" "package script reads CURRENT_PROJECT_VERSION"
require_regex_match 'GlanceHold-\$\{app_version\}-build-\$\{build_version\}' "$PACKAGE_SCRIPT" "package script derives versioned release id"
require_fixed_match '-archivePath "$archive_path"' "$PACKAGE_SCRIPT" "archive command uses explicit archive path"
require_fixed_match '-exportPath "$export_path"' "$PACKAGE_SCRIPT" "export command uses explicit export path"
require_fixed_match '-exportOptionsPlist "$EXPORT_OPTIONS_PLIST"' "$PACKAGE_SCRIPT" "export command uses tracked export options"
require_fixed_match "--verify" "$PACKAGE_SCRIPT" "package script exposes --verify"
require_fixed_match "--skip-dmg" "$PACKAGE_SCRIPT" "package script exposes --skip-dmg"
require_fixed_match "require_absent" "$PACKAGE_SCRIPT" "package script includes require_absent"
require_fixed_match 'require_absent "$build_dir"' "$PACKAGE_SCRIPT" "package script refuses existing build directory"
require_fixed_match 'require_absent "$release_dir"' "$PACKAGE_SCRIPT" "package script refuses existing release directory"
require_fixed_match 'require_absent "$exported_app_path"' "$PACKAGE_SCRIPT" "package script refuses existing exported app path"
require_fixed_match "require_generated_root_path" "$PACKAGE_SCRIPT" "package script includes generated-root guard"
require_fixed_match "sanitize_release_component" "$PACKAGE_SCRIPT" "package script includes release component sanitizer"
require_fixed_match "ReleasePackaging/ExportOptions.plist" "$PACKAGE_SCRIPT" "package script references export options plist"
require_fixed_match "GlanceHold/Info.plist" "$PACKAGE_SCRIPT" "package script validates source app Info.plist"
require_fixed_match "IINAPlugin/GlanceHoldBridge.iinaplugin/Info.json" "$PACKAGE_SCRIPT" "package script validates plugin Info.json"
require_fixed_match 'IINA_PLUGIN_CLI="/Applications/IINA.app/Contents/MacOS/iina-plugin"' "$PACKAGE_SCRIPT" "package script uses bundled IINA_PLUGIN_CLI"
require_fixed_match 'PLUGIN_SOURCE_DIR="IINAPlugin/GlanceHoldBridge.iinaplugin"' "$PACKAGE_SCRIPT" "package script names source plugin directory"
require_fixed_match "iina-plugin" "$PACKAGE_SCRIPT" "package script names iina-plugin pack tool"
require_fixed_match 'exported_app_info_plist="$exported_app_path/Contents/Info.plist"' "$PACKAGE_SCRIPT" "package script reads exported app Info.plist"
require_fixed_match "CFBundleShortVersionString" "$PACKAGE_SCRIPT" "package script reads exported app version"
require_fixed_match "CFBundleVersion" "$PACKAGE_SCRIPT" "package script reads exported app build"
require_fixed_match "CFBundleIdentifier" "$PACKAGE_SCRIPT" "package script reads exported app bundle identifier"
require_fixed_match "dist/build" "$PACKAGE_SCRIPT" "package script references dist/build"
require_fixed_match "dist/releases" "$PACKAGE_SCRIPT" "package script references dist/releases"
require_fixed_match "dmg-staging" "$PACKAGE_SCRIPT" "package script references DMG staging directory"
require_fixed_match "Install IINA Plugin.md" "$PACKAGE_SCRIPT" "package script writes plugin pointer file"
require_fixed_match 'plugin_asset_name="GlanceHoldBridge-${app_version}-build-${build_version}.iinaplgz"' "$PACKAGE_SCRIPT" "package script derives release-id .iinaplgz asset name"
require_fixed_match 'plugin_work_dir="$build_dir/plugin-package"' "$PACKAGE_SCRIPT" "package script stages plugin packaging under generated build root"
require_fixed_match 'plugin_release_asset_path="$release_dir/$plugin_asset_name"' "$PACKAGE_SCRIPT" "package script exposes standalone release .iinaplgz"
require_fixed_match 'plugin_dmg_asset_path="$dmg_staging_dir/$plugin_asset_name"' "$PACKAGE_SCRIPT" "package script stages matching DMG .iinaplgz"
require_fixed_match "require_iina_plugin_cli" "$PACKAGE_SCRIPT" "package script fails closed when IINA plugin CLI is missing"
require_fixed_match "package_plugin_asset" "$PACKAGE_SCRIPT" "package script packages plugin asset"
require_fixed_match '"$IINA_PLUGIN_CLI" pack "GlanceHoldBridge.iinaplugin"' "$PACKAGE_SCRIPT" "package script uses iina-plugin pack command"
require_fixed_match 'ditto "$plugin_default_output" "$plugin_release_asset_path"' "$PACKAGE_SCRIPT" "package script writes standalone release .iinaplgz"
require_fixed_match 'ditto "$plugin_release_asset_path" "$plugin_dmg_asset_path"' "$PACKAGE_SCRIPT" "package script copies matching .iinaplgz into DMG staging"
require_fixed_match "Applications" "$PACKAGE_SCRIPT" "package script stages Applications symlink"
require_fixed_match "/Applications" "$PACKAGE_SCRIPT" "package script points Applications symlink to /Applications"
require_fixed_match "hdiutil create" "$PACKAGE_SCRIPT" "package script creates a DMG"
require_fixed_match '-srcfolder "$dmg_staging_dir"' "$PACKAGE_SCRIPT" "hdiutil create uses explicit source folder"
require_fixed_match '-volname "$release_id"' "$PACKAGE_SCRIPT" "hdiutil create uses release id volume name"
require_fixed_match "-format UDZO" "$PACKAGE_SCRIPT" "hdiutil create uses compressed read-only format"
require_fixed_match "shasum -a 256" "$PACKAGE_SCRIPT" "package script computes SHA-256 checksum"
require_fixed_match ".dmg.sha256" "$PACKAGE_SCRIPT" "package script writes separate sha256 file"
require_fixed_match ".manifest.json" "$PACKAGE_SCRIPT" "package script writes manifest JSON"
require_fixed_match "git rev-parse HEAD" "$PACKAGE_SCRIPT" "package script records git SHA"
require_fixed_match "git status --porcelain" "$PACKAGE_SCRIPT" "package script records git dirty state"
require_fixed_match "sw_vers" "$PACKAGE_SCRIPT" "package script records macOS environment"
require_fixed_match "xcodebuild -version" "$PACKAGE_SCRIPT" "package script records Xcode environment"
require_fixed_match "lipo -archs" "$PACKAGE_SCRIPT" "package script records app architectures"
require_fixed_match "protocolVersion" "$PACKAGE_SCRIPT" "package script reads bridge protocol version"
require_fixed_match "PHASE13_VERIFIER" "$PACKAGE_SCRIPT" "package script names static verifier"
require_fixed_match 'bash "$PHASE13_VERIFIER"' "$PACKAGE_SCRIPT" "package verify runs static verifier"
require_fixed_match "--require-generated" "$PACKAGE_SCRIPT" "package verify runs generated artifact verifier"
require_fixed_match "require_no_symlink_component" "$PACKAGE_SCRIPT" "package script rejects symlinked generated path components"
require_fixed_match '[[ ! -e "$path" && ! -L "$path" ]]' "$PACKAGE_SCRIPT" "package script refuses broken symlink overwrite targets"
require_fixed_match "schemaVersion" "$PACKAGE_SCRIPT" "manifest includes schemaVersion"
require_fixed_match "releaseId" "$PACKAGE_SCRIPT" "manifest includes releaseId"
require_fixed_match "generatedAtUTC" "$PACKAGE_SCRIPT" "manifest includes generatedAtUTC"
require_fixed_match "gitSha" "$PACKAGE_SCRIPT" "manifest includes source.gitSha"
require_fixed_match "gitDirty" "$PACKAGE_SCRIPT" "manifest includes source.gitDirty"
require_fixed_match "bundleIdentifier" "$PACKAGE_SCRIPT" "manifest includes app.bundleIdentifier"
require_fixed_match '"version":' "$PACKAGE_SCRIPT" "manifest includes app/plugin version keys"
require_fixed_match '"build":' "$PACKAGE_SCRIPT" "manifest includes app.build"
require_fixed_match "minimumMacOS" "$PACKAGE_SCRIPT" "manifest includes app.minimumMacOS"
require_fixed_match "architectures" "$PACKAGE_SCRIPT" "manifest includes app.architectures"
require_fixed_match "dmgFileName" "$PACKAGE_SCRIPT" "manifest includes artifact.dmgFileName"
require_fixed_match "sha256FileName" "$PACKAGE_SCRIPT" "manifest includes artifact.sha256FileName"
require_fixed_match "manifestFileName" "$PACKAGE_SCRIPT" "manifest includes artifact.manifestFileName"
require_fixed_match "sizeBytes" "$PACKAGE_SCRIPT" "manifest includes artifact.sizeBytes"
require_fixed_match "macosProductVersion" "$PACKAGE_SCRIPT" "manifest includes environment.macosProductVersion"
require_fixed_match "macosBuildVersion" "$PACKAGE_SCRIPT" "manifest includes environment.macosBuildVersion"
require_fixed_match "xcodeVersion" "$PACKAGE_SCRIPT" "manifest includes environment.xcodeVersion"
require_fixed_match '"name":' "$PACKAGE_SCRIPT" "manifest includes plugin.name"
require_fixed_match '"identifier":' "$PACKAGE_SCRIPT" "manifest includes plugin.identifier"
require_fixed_match "bridgeProtocolVersion" "$PACKAGE_SCRIPT" "manifest includes plugin.bridgeProtocolVersion"
require_fixed_match "expectedAssetName" "$PACKAGE_SCRIPT" "manifest includes plugin.expectedAssetName"
require_fixed_match '"expectedAssetName": $(json_string "$plugin_asset_name")' "$PACKAGE_SCRIPT" "manifest plugin.expectedAssetName uses concrete plugin_asset_name"
require_regex_absent 'PENDING_TRUST_STATUS' "$PACKAGE_SCRIPT" "pending trust status constant is absent"
require_regex_absent 'pending-phase-14' "$PACKAGE_SCRIPT" "pending Phase 14 trust placeholder is absent from package script"
require_regex_absent 'pending-phase-15' "$PACKAGE_SCRIPT" "pending-phase-15 placeholder is absent from package script"
require_regex_absent 'phase15AlignmentNote' "$PACKAGE_SCRIPT" "phase15AlignmentNote placeholder is absent from package script"
require_regex_absent 'signingStatus' "$PACKAGE_SCRIPT" "manifest trust.signingStatus key is absent"
require_regex_absent 'notarizationStatus' "$PACKAGE_SCRIPT" "manifest trust.notarizationStatus key is absent"
require_regex_absent 'staplingStatus' "$PACKAGE_SCRIPT" "manifest trust.staplingStatus key is absent"
require_regex_absent '--sign|--notarize|--staple|codesign|notarytool|stapler|spctl|security[[:space:]]+find-identity' "$PACKAGE_SCRIPT" "Developer ID signing and notarization command surface is absent"
require_regex_absent 'IINAPlugin/GlanceHoldBridge\.iinaplugin.*dmg|dmg.*IINAPlugin/GlanceHoldBridge\.iinaplugin|ditto.*GlanceHoldBridge\.iinaplugin|cp[[:space:]].*GlanceHoldBridge\.iinaplugin' "$PACKAGE_SCRIPT" "plugin body copy into DMG staging is absent"
require_regex_absent 'com\.colliderli\.iina/plugins|Application Support/com\.colliderli\.iina/plugins|~/Library/Application Support/com\.colliderli\.iina/plugins' "$PACKAGE_SCRIPT" "user IINA plugin directory writes are absent"
require_regex_absent 'plugin(_|-)?(checksum|sha256|size|byte)' "$PACKAGE_SCRIPT" "plugin checksum and size fields are absent from package script"
require_regex_absent '\.background|\.DS_Store|osascript|Finder[[:space:]]+window|set[[:space:]]+background|set[[:space:]]+icon[[:space:]]+size|set[[:space:]]+bounds' "$PACKAGE_SCRIPT" "custom DMG Finder styling is absent"
require_regex_absent 'DerivedData|Build/Products|Debug/GlanceHold\.app|Debug.*GlanceHold\.app' "$PACKAGE_SCRIPT" "DerivedData and Debug canonical app source patterns are absent"

require_regex_absent 'rm[[:space:]]' "$PACKAGE_SCRIPT" "rm command token is absent"
require_regex_absent 'rm[[:space:]]-' "$PACKAGE_SCRIPT" "rm flag token is absent"
require_regex_absent 'unlink' "$PACKAGE_SCRIPT" "unlink token is absent"
require_regex_absent 'rmdir' "$PACKAGE_SCRIPT" "rmdir token is absent"
require_regex_absent 'find[[:space:]].*-delete' "$PACKAGE_SCRIPT" "find delete token is absent"
require_regex_absent 'cp[[:space:]]-f' "$PACKAGE_SCRIPT" "cp force token is absent"
require_regex_absent 'mv[[:space:]]-f' "$PACKAGE_SCRIPT" "mv force token is absent"
require_regex_absent 'hdiutil[[:space:]]+create[[:space:]].*-ov' "$PACKAGE_SCRIPT" "hdiutil overwrite token is absent"
require_regex_absent 'unzip[[:space:]]-o' "$PACKAGE_SCRIPT" "unzip overwrite token is absent"
require_regex_absent 'rsync[[:space:]].*--delete' "$PACKAGE_SCRIPT" "rsync delete token is absent"
require_regex_absent 'rsync[[:space:]].*--remove-source-files' "$PACKAGE_SCRIPT" "rsync remove-source-files token is absent"

check_generated_manifest_artifacts

if [ "$failures" -eq 0 ]; then
  printf 'PASS: Phase 13 packaging source boundaries verified\n'
  exit 0
fi

printf 'FAIL: Phase 13 packaging source boundaries have %d violation(s)\n' "$failures" >&2
exit 1
