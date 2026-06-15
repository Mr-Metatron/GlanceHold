#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT_FILE="GlanceHold.xcodeproj"
SCHEME="GlanceHold"
CONFIGURATION="Release"
BUILD_ROOT="dist/build"
RELEASE_ROOT="dist/releases"
EXPORT_OPTIONS_PLIST="ReleasePackaging/ExportOptions.plist"
APP_INFO_PLIST="GlanceHold/Info.plist"
PLUGIN_INFO_JSON="IINAPlugin/GlanceHoldBridge.iinaplugin/Info.json"
PLUGIN_MAIN_JS="IINAPlugin/GlanceHoldBridge.iinaplugin/main.js"
IINA_PLUGIN_CLI="/Applications/IINA.app/Contents/MacOS/iina-plugin"
PLUGIN_SOURCE_DIR="IINAPlugin/GlanceHoldBridge.iinaplugin"
PHASE13_VERIFIER="scripts/verify_phase13_packaging.sh"
PLUGIN_POINTER_NAME="Install IINA Plugin.md"

RUN_VERIFY=false
SKIP_DMG=false

usage() {
    cat <<'USAGE'
Usage:
  scripts/package_release.sh [--verify] [--skip-dmg]

GlanceHold release packaging entrypoint.

Purpose:
  Build the release app through the canonical archive/export path, then prepare
  generated release assets under the ignored output roots.

Canonical build path:
  xcodebuild archive
  xcodebuild -exportArchive

Fixed defaults:
  PROJECT_FILE=GlanceHold.xcodeproj
  SCHEME=GlanceHold
  CONFIGURATION=Release
  BUILD_ROOT=dist/build
  RELEASE_ROOT=dist/releases
  EXPORT_OPTIONS_PLIST=ReleasePackaging/ExportOptions.plist

Options:
  --verify      Run packaging source preflight before packaging and generated
                artifact checks after packaging.
  --skip-dmg    Accept the release flow flag used by archive/export smoke runs.
  --help, -h    Show this help.

Safety:
  Generated archives, exports, DMG staging, checksums, and manifests belong
  under dist/build or dist/releases. Existing output paths must be absent before
  later packaging writes.
USAGE
}

fail() {
    printf 'error: %s\n' "$1" >&2
    exit "${2:-1}"
}

require_value() {
    local option="$1"
    local value="${2:-}"
    if [[ -z "$value" ]]; then
        fail "$option requires a value" 64
    fi
}

require_file() {
    local path="$1"
    [[ -f "$path" ]] || fail "required file is missing: $path"
}

require_directory() {
    local path="$1"
    [[ -d "$path" ]] || fail "required directory is missing: $path"
}

require_tool() {
    local tool="$1"
    command -v "$tool" >/dev/null 2>&1 || fail "required tool is missing: $tool"
}

require_absent() {
    local path="$1"
    [[ ! -e "$path" && ! -L "$path" ]] || fail "refusing to overwrite existing path: $path" 73
}

require_generated_root_path() {
    local path="${1#./}"
    case "$path" in
        "$BUILD_ROOT"|"$BUILD_ROOT"/*|"$RELEASE_ROOT"|"$RELEASE_ROOT"/*)
            ;;
        *)
            fail "path must stay under $BUILD_ROOT or $RELEASE_ROOT: $1" 64
            ;;
    esac
}

require_no_symlink_component() {
    local path="${1#./}"
    local current=""
    local part
    IFS='/' read -r -a parts <<< "$path"
    for part in "${parts[@]}"; do
        [[ -n "$part" ]] || continue
        current="${current:+$current/}$part"
        [[ ! -L "$current" ]] || fail "refusing symlinked generated path component: $current" 73
    done
}

sanitize_release_component() {
    local value="$1"
    [[ -n "$value" ]] || fail "release component must not be empty" 64
    [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]] || fail "release component contains unsupported characters: $value" 64
    printf '%s' "$value"
}

require_release_sources() {
    require_directory "$PROJECT_FILE"
    require_file "$EXPORT_OPTIONS_PLIST"
    require_file "$APP_INFO_PLIST"
    require_directory "$PLUGIN_SOURCE_DIR"
    require_file "$PLUGIN_INFO_JSON"
    require_file "$PLUGIN_MAIN_JS"
}

require_iina_plugin_cli() {
    if [[ ! -f "$IINA_PLUGIN_CLI" || ! -x "$IINA_PLUGIN_CLI" ]]; then
        fail "IINA plugin packaging requires IINA 1.4 or later with bundled CLI at $IINA_PLUGIN_CLI"
    fi
}

require_release_tools() {
    require_tool xcodebuild
    require_tool plutil
    require_tool git
    require_tool sw_vers
    require_tool hdiutil
    require_tool shasum
    require_tool lipo
    require_tool ditto
}

read_build_setting() {
    local settings="$1"
    local key="$2"
    printf '%s\n' "$settings" | awk -F ' = ' -v key="$key" '
        {
            field = $1
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", field)
            if (field == key) {
                print $2
                exit
            }
        }
    '
}

load_release_context() {
    local build_settings
    local raw_app_version
    local raw_build_version
    local raw_plugin_version
    build_settings="$(xcodebuild -showBuildSettings -project "$PROJECT_FILE" -scheme "$SCHEME" -configuration "$CONFIGURATION" 2>/dev/null)" \
        || fail "failed to read Xcode build settings for $SCHEME $CONFIGURATION"
    raw_app_version="$(read_build_setting "$build_settings" "MARKETING_VERSION")"
    raw_build_version="$(read_build_setting "$build_settings" "CURRENT_PROJECT_VERSION")"
    raw_plugin_version="$(read_json_value "version" "$PLUGIN_INFO_JSON")"

    app_version="$(sanitize_release_component "$raw_app_version")"
    build_version="$(sanitize_release_component "$raw_build_version")"
    plugin_version="$(sanitize_release_component "$raw_plugin_version")"
    release_id="GlanceHold-${app_version}-build-${build_version}"
    build_dir="$BUILD_ROOT/$release_id"
    derived_data_path="$build_dir/derived-data"
    archive_path="$build_dir/GlanceHold.xcarchive"
    export_path="$build_dir/export"
    exported_app_path="$export_path/GlanceHold.app"
    dmg_staging_dir="$build_dir/dmg-staging"
    staged_app_path="$dmg_staging_dir/GlanceHold.app"
    applications_link_path="$dmg_staging_dir/Applications"
    plugin_pointer_path="$dmg_staging_dir/$PLUGIN_POINTER_NAME"
    release_dir="$RELEASE_ROOT/$release_id"
    plugin_asset_name="GlanceHoldBridge-${app_version}-build-${build_version}.iinaplgz"
    plugin_work_dir="$build_dir/plugin-package"
    plugin_work_source="$plugin_work_dir/GlanceHoldBridge.iinaplugin"
    plugin_default_output="$plugin_work_dir/GlanceHoldBridge.iinaplugin-${plugin_version}.iinaplgz"
    plugin_release_asset_path="$release_dir/$plugin_asset_name"
    plugin_dmg_asset_path="$dmg_staging_dir/$plugin_asset_name"
    dmg_file_name="$release_id.dmg"
    dmg_path="$release_dir/$dmg_file_name"
    sha256_file_name="$release_id.dmg.sha256"
    sha256_path="$release_dir/$sha256_file_name"
    manifest_file_name="$release_id.manifest.json"
    manifest_path="$release_dir/$manifest_file_name"
}

require_release_paths() {
    require_generated_root_path "$BUILD_ROOT"
    require_generated_root_path "$RELEASE_ROOT"
    require_generated_root_path "$build_dir"
    require_generated_root_path "$derived_data_path"
    require_generated_root_path "$archive_path"
    require_generated_root_path "$export_path"
    require_generated_root_path "$exported_app_path"
    require_generated_root_path "$dmg_staging_dir"
    require_generated_root_path "$staged_app_path"
    require_generated_root_path "$applications_link_path"
    require_generated_root_path "$plugin_pointer_path"
    require_generated_root_path "$release_dir"
    require_generated_root_path "$plugin_work_dir"
    require_generated_root_path "$plugin_work_source"
    require_generated_root_path "$plugin_default_output"
    require_generated_root_path "$plugin_release_asset_path"
    require_generated_root_path "$plugin_dmg_asset_path"
    require_generated_root_path "$dmg_path"
    require_generated_root_path "$sha256_path"
    require_generated_root_path "$manifest_path"
    require_no_symlink_component "$BUILD_ROOT"
    require_no_symlink_component "$RELEASE_ROOT"
    require_no_symlink_component "$build_dir"
    require_no_symlink_component "$release_dir"
    require_absent "$build_dir"
    require_absent "$release_dir"
    require_absent "$archive_path"
    require_absent "$export_path"
    require_absent "$exported_app_path"
    require_absent "$dmg_staging_dir"
    require_absent "$staged_app_path"
    require_absent "$applications_link_path"
    require_absent "$plugin_pointer_path"
    require_absent "$plugin_work_dir"
    require_absent "$plugin_work_source"
    require_absent "$plugin_default_output"
    require_absent "$plugin_release_asset_path"
    require_absent "$plugin_dmg_asset_path"
    require_absent "$dmg_path"
    require_absent "$sha256_path"
    require_absent "$manifest_path"
}

prepare_release() {
    require_release_sources
    require_release_tools
    load_release_context
    require_release_paths
    plutil -lint "$EXPORT_OPTIONS_PLIST" >/dev/null
}

run_verify_preflight() {
    require_file "$PHASE13_VERIFIER"
    bash "$PHASE13_VERIFIER"
    prepare_release
    printf 'PASS: Phase 13 release packaging source preflight (%s)\n' "$release_id"
}

run_verify_generated_artifacts() {
    require_file "$PHASE13_VERIFIER"
    bash "$PHASE13_VERIFIER" --require-generated
}

ensure_directory() {
    local path="$1"
    require_generated_root_path "$path"
    require_no_symlink_component "$path"
    [[ ! -e "$path" || -d "$path" ]] || fail "expected directory path is not a directory: $path"
    if [[ ! -e "$path" ]]; then
        mkdir -p "$path"
    fi
}

read_plist_value() {
    local key="$1"
    local plist="$2"
    local value
    value="$(plutil -extract "$key" raw "$plist" 2>/dev/null)" \
        || fail "failed to read $key from $plist"
    [[ -n "$value" ]] || fail "plist value is empty: $key in $plist"
    printf '%s' "$value"
}

read_json_value() {
    local key="$1"
    local json="$2"
    local value
    value="$(plutil -extract "$key" raw "$json" 2>/dev/null)" \
        || fail "failed to read $key from $json"
    [[ -n "$value" ]] || fail "JSON value is empty: $key in $json"
    printf '%s' "$value"
}

read_bridge_protocol_version() {
    local value
    value="$(awk '
        $1 == "const" && $2 == "protocolVersion" && $3 == "=" {
            gsub(/;/, "", $4)
            print $4
            exit
        }
    ' "$PLUGIN_MAIN_JS")"
    [[ "$value" =~ ^[0-9]+$ ]] || fail "failed to read protocolVersion from $PLUGIN_MAIN_JS"
    printf '%s' "$value"
}

json_string() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\t'/\\t}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\n'/\\n}"
    printf '"%s"' "$value"
}

json_array_from_words() {
    local words="$1"
    local word
    local separator=""
    printf '['
    for word in $words; do
        printf '%s%s' "$separator" "$(json_string "$word")"
        separator=", "
    done
    printf ']'
}

run_archive_export() {
    ensure_directory "$BUILD_ROOT"
    mkdir "$build_dir"

    xcodebuild archive \
        -project "$PROJECT_FILE" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -derivedDataPath "$derived_data_path" \
        -archivePath "$archive_path"

    xcodebuild -exportArchive \
        -archivePath "$archive_path" \
        -exportPath "$export_path" \
        -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"
}

validate_exported_app() {
    require_directory "$exported_app_path"
    exported_app_info_plist="$exported_app_path/Contents/Info.plist"
    require_file "$exported_app_info_plist"

    exported_app_version="$(read_plist_value "CFBundleShortVersionString" "$exported_app_info_plist")"
    exported_build_version="$(read_plist_value "CFBundleVersion" "$exported_app_info_plist")"
    exported_bundle_identifier="$(read_plist_value "CFBundleIdentifier" "$exported_app_info_plist")"
    exported_minimum_macos="$(read_plist_value "LSMinimumSystemVersion" "$exported_app_info_plist")"
    exported_executable_name="$(read_plist_value "CFBundleExecutable" "$exported_app_info_plist")"

    [[ "$exported_app_version" == "$app_version" ]] \
        || fail "exported app version mismatch: expected $app_version, got $exported_app_version"
    [[ "$exported_build_version" == "$build_version" ]] \
        || fail "exported app build mismatch: expected $build_version, got $exported_build_version"

    printf 'PASS: Exported %s %s (%s) at %s\n' \
        "$exported_bundle_identifier" \
        "$exported_app_version" \
        "$exported_build_version" \
        "$exported_app_path"
}

load_manifest_facts() {
    local xcode_version_output
    local dirty_output
    local exported_executable_path

    generated_at_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    source_git_sha="$(git rev-parse HEAD)"
    dirty_output="$(git status --porcelain)"
    if [[ -n "$dirty_output" ]]; then
        source_git_dirty=true
    else
        source_git_dirty=false
    fi

    exported_executable_path="$exported_app_path/Contents/MacOS/$exported_executable_name"
    require_file "$exported_executable_path"
    exported_architectures="$(lipo -archs "$exported_executable_path")" \
        || fail "failed to read architectures from $exported_executable_path"
    [[ -n "$exported_architectures" ]] || fail "exported app architectures are empty"

    artifact_size_bytes="$(stat -f '%z' "$dmg_path")" \
        || fail "failed to read DMG size: $dmg_path"

    macos_product_version="$(sw_vers -productVersion)"
    macos_build_version="$(sw_vers -buildVersion)"
    xcode_version_output="$(xcodebuild -version)"
    xcode_version="$(printf '%s\n' "$xcode_version_output" | awk '
        NR == 1 { value = $0 }
        NR == 2 { value = value " (" $0 ")" }
        END { print value }
    ')"

    plugin_name="$(read_json_value "name" "$PLUGIN_INFO_JSON")"
    plugin_identifier="$(read_json_value "identifier" "$PLUGIN_INFO_JSON")"
    plugin_version="$(read_json_value "version" "$PLUGIN_INFO_JSON")"
    bridge_protocol_version="$(read_bridge_protocol_version)"
}

write_checksum() {
    require_absent "$sha256_path"
    (
        cd "$release_dir"
        shasum -a 256 "$dmg_file_name" > "$sha256_file_name"
    )
    checksum_value="$(awk '{ print $1; exit }' "$sha256_path")"
    [[ "$checksum_value" =~ ^[0-9A-Fa-f]{64}$ ]] || fail "invalid SHA-256 value in $sha256_path"
    printf 'PASS: Wrote SHA-256 checksum at %s\n' "$sha256_path"
}

create_release_directory() {
    ensure_directory "$RELEASE_ROOT"
    require_absent "$release_dir"
    mkdir "$release_dir"
}

package_plugin_asset() {
    require_iina_plugin_cli
    require_directory "$PLUGIN_SOURCE_DIR"
    require_absent "$plugin_work_dir"
    mkdir "$plugin_work_dir"

    require_absent "$plugin_work_source"
    ditto "$PLUGIN_SOURCE_DIR" "$plugin_work_source"

    require_absent "$plugin_default_output"
    (
        cd "$plugin_work_dir"
        "$IINA_PLUGIN_CLI" pack "GlanceHoldBridge.iinaplugin"
    )
    require_file "$plugin_default_output"

    require_absent "$plugin_release_asset_path"
    ditto "$plugin_default_output" "$plugin_release_asset_path"
    printf 'PASS: Wrote IINA plugin package at %s\n' "$plugin_release_asset_path"
}

write_manifest() {
    local architectures_json
    require_absent "$manifest_path"
    load_manifest_facts
    architectures_json="$(json_array_from_words "$exported_architectures")"

    cat > "$manifest_path" <<MANIFEST
{
  "schemaVersion": 1,
  "releaseId": $(json_string "$release_id"),
  "generatedAtUTC": $(json_string "$generated_at_utc"),
  "source": {
    "gitSha": $(json_string "$source_git_sha"),
    "gitDirty": $source_git_dirty
  },
  "app": {
    "bundleIdentifier": $(json_string "$exported_bundle_identifier"),
    "version": $(json_string "$exported_app_version"),
    "build": $(json_string "$exported_build_version"),
    "minimumMacOS": $(json_string "$exported_minimum_macos"),
    "architectures": $architectures_json
  },
  "artifact": {
    "dmgFileName": $(json_string "$dmg_file_name"),
    "sha256FileName": $(json_string "$sha256_file_name"),
    "manifestFileName": $(json_string "$manifest_file_name"),
    "sha256": $(json_string "$checksum_value"),
    "sizeBytes": $artifact_size_bytes
  },
  "environment": {
    "macosProductVersion": $(json_string "$macos_product_version"),
    "macosBuildVersion": $(json_string "$macos_build_version"),
    "xcodeVersion": $(json_string "$xcode_version")
  },
  "plugin": {
    "name": $(json_string "$plugin_name"),
    "identifier": $(json_string "$plugin_identifier"),
    "version": $(json_string "$plugin_version"),
    "bridgeProtocolVersion": $bridge_protocol_version,
    "expectedAssetName": $(json_string "$plugin_asset_name")
  }
}
MANIFEST

    plutil -extract schemaVersion raw "$manifest_path" >/dev/null
    printf 'PASS: Wrote release manifest at %s\n' "$manifest_path"
}

write_plugin_pointer() {
    require_absent "$plugin_pointer_path"
    cat > "$plugin_pointer_path" <<POINTER
# Install IINA Plugin

This DMG includes the matching GlanceHold Bridge IINA plugin package:

\`$plugin_asset_name\`

Use the app and plugin package from this same DMG or from the same GitHub Release. Do not mix app and plugin files from different releases.

1. Open \`$plugin_asset_name\` with IINA to install it.
2. restart IINA after installation.
3. Check that \`GlanceHold Bridge\` is enabled in IINA.
4. Return to GlanceHold and verify the IINA row leaves setup, update-needed, or unavailable states.

See \`IINAPlugin/README.md\` for detailed plugin setup, local bridge trust, and troubleshooting notes.
POINTER
}

stage_dmg_contents() {
    require_directory "$exported_app_path"
    require_absent "$dmg_staging_dir"
    mkdir "$dmg_staging_dir"

    require_absent "$staged_app_path"
    ditto "$exported_app_path" "$staged_app_path"

    require_absent "$applications_link_path"
    ln -s /Applications "$applications_link_path"

    require_file "$plugin_release_asset_path"
    require_absent "$plugin_dmg_asset_path"
    ditto "$plugin_release_asset_path" "$plugin_dmg_asset_path"

    write_plugin_pointer
}

create_dmg() {
    require_directory "$release_dir"

    require_absent "$dmg_path"
    hdiutil create \
        -srcfolder "$dmg_staging_dir" \
        -volname "$release_id" \
        -format UDZO \
        "$dmg_path"

    printf 'PASS: Created DMG at %s\n' "$dmg_path"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --verify)
            RUN_VERIFY=true
            shift
            ;;
        --skip-dmg)
            SKIP_DMG=true
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

if [[ "$RUN_VERIFY" == true ]]; then
    run_verify_preflight
else
    prepare_release
fi

run_archive_export
validate_exported_app

if [[ "$SKIP_DMG" == true ]]; then
    printf 'PASS: --skip-dmg stopped after archive/export validation: %s\n' "$exported_app_path"
    exit 0
fi

create_release_directory
package_plugin_asset
stage_dmg_contents
create_dmg
write_checksum
write_manifest

if [[ "$RUN_VERIFY" == true ]]; then
    run_verify_generated_artifacts
fi

printf 'PASS: Release artifacts ready in %s\n' "$release_dir"
