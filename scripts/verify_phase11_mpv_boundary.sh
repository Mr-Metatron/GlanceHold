#!/usr/bin/env bash
set -u

PROJECT_FILE="GlanceHold.xcodeproj/project.pbxproj"
APP_FILE="GlanceHold/GlanceHoldApp.swift"
TYPES_FILE="GlanceHold/IINAPlaybackTypes.swift"
PLUGIN_ADAPTER_FILE="GlanceHold/IINAPluginBridgeAdapter.swift"
MPV_ADAPTER_FILE="GlanceHold/IINAPlaybackAdapter.swift"
MPV_CLIENT_FILE="GlanceHold/MPVJSONIPCClient.swift"
MPV_ADAPTER_TEST_FILE="GlanceHoldTests/IINAPlaybackAdapterTests.swift"
MPV_CLIENT_TEST_FILE="GlanceHoldTests/MPVJSONIPCClientTests.swift"

failures=0

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

source_phase_id_for_target() {
  local target="$1"
  awk -v target="$target" '
    $0 ~ "/\\* " target " \\*/ = \\{" {
      inTarget = 1
      isNativeTarget = 0
      next
    }
    inTarget && /isa = PBXNativeTarget;/ {
      isNativeTarget = 1
    }
    inTarget && isNativeTarget && /\/\* Sources \*\// {
      print $1
      exit
    }
    inTarget && /^[[:space:]]*};/ {
      inTarget = 0
      isNativeTarget = 0
    }
  ' "$PROJECT_FILE"
}

source_phase_block() {
  local phase_id="$1"
  awk -v phase_id="$phase_id" '
    $1 == phase_id && /\/\* Sources \*\// && /= \{/ {
      inPhase = 1
    }
    inPhase {
      print
    }
    inPhase && /^[[:space:]]*};/ {
      exit
    }
  ' "$PROJECT_FILE"
}

expect_block_contains() {
  local block="$1"
  local pattern="$2"
  local description="$3"
  if grep -Fq "$pattern" <<<"$block"; then
    pass "$description"
  else
    fail "$description"
  fi
}

expect_block_absent() {
  local block="$1"
  local pattern="$2"
  local description="$3"
  if grep -Fq "$pattern" <<<"$block"; then
    fail "$description"
  else
    pass "$description"
  fi
}

require_rg_match() {
  local pattern="$1"
  local path="$2"
  local description="$3"
  if rg -n "$pattern" "$path" >/dev/null; then
    pass "$description"
  else
    fail "$description"
  fi
}

require_rg_absent() {
  local pattern="$1"
  local path="$2"
  local description="$3"
  if rg -n "$pattern" "$path" >/dev/null; then
    fail "$description"
  else
    pass "$description"
  fi
}

require_file "$PROJECT_FILE"
require_file "$APP_FILE"
require_file "$TYPES_FILE"
require_file "$PLUGIN_ADAPTER_FILE"
require_file "$MPV_ADAPTER_FILE"
require_file "$MPV_CLIENT_FILE"
require_file "$MPV_ADAPTER_TEST_FILE"
require_file "$MPV_CLIENT_TEST_FILE"

app_sources_id="$(source_phase_id_for_target "GlanceHold")"
test_sources_id="$(source_phase_id_for_target "GlanceHoldTests")"

if [ -z "$app_sources_id" ]; then
  fail "GlanceHold app target Sources build phase was not found"
  app_sources=""
else
  app_sources="$(source_phase_block "$app_sources_id")"
fi

if [ -z "$test_sources_id" ]; then
  fail "GlanceHoldTests target Sources build phase was not found"
  test_sources=""
else
  test_sources="$(source_phase_block "$test_sources_id")"
fi

expect_block_contains "$app_sources" "IINAPlaybackTypes.swift in Sources" "app Sources includes IINAPlaybackTypes.swift"
expect_block_contains "$app_sources" "IINAPluginBridgeClient.swift in Sources" "app Sources includes IINAPluginBridgeClient.swift"
expect_block_contains "$app_sources" "IINAPluginBridgeAdapter.swift in Sources" "app Sources includes IINAPluginBridgeAdapter.swift"
expect_block_absent "$app_sources" "IINAPlaybackAdapter.swift in Sources" "app Sources excludes IINAPlaybackAdapter.swift"
expect_block_absent "$app_sources" "MPVJSONIPCClient.swift in Sources" "app Sources excludes MPVJSONIPCClient.swift"

expect_block_absent "$test_sources" "IINAPlaybackAdapterTests.swift in Sources" "normal test Sources excludes IINAPlaybackAdapterTests.swift"
expect_block_absent "$test_sources" "MPVJSONIPCClientTests.swift in Sources" "normal test Sources excludes MPVJSONIPCClientTests.swift"

require_rg_match "IINAPluginBridgeAdapter\\(client: bridgeClient\\)" "$APP_FILE" "GlanceHoldApp wires PlaybackCoordinator through IINAPluginBridgeAdapter"
require_rg_absent "IINAPlaybackAdapter\\(" "$APP_FILE" "GlanceHoldApp has no IINAPlaybackAdapter fallback construction"

require_rg_match "var playerSnapshot" "$TYPES_FILE" "IINAPlaybackTypes.swift declares the shared var playerSnapshot mapping"
require_rg_match "status\\.playerSnapshot" "$PLUGIN_ADAPTER_FILE" "IINAPluginBridgeAdapter uses status.playerSnapshot"
require_rg_absent "private.*playerSnapshot|var playerSnapshot|func playerSnapshot" "$MPV_ADAPTER_FILE" "IINAPlaybackAdapter declares no private duplicate playerSnapshot mapping"
require_rg_absent "private.*playerSnapshot|var playerSnapshot|func playerSnapshot" "$PLUGIN_ADAPTER_FILE" "IINAPluginBridgeAdapter declares no private duplicate playerSnapshot mapping"
require_rg_match "Reference-only MPV JSON IPC client" "$MPV_CLIENT_FILE" "MPVJSONIPCClient.swift is marked reference-only"
require_rg_match "Reference coverage only; MPV IPC is not normal Phase 11 production hard-gate evidence" "$MPV_ADAPTER_TEST_FILE" "IINAPlaybackAdapterTests.swift is marked reference coverage only"
require_rg_match "Reference coverage only; MPV IPC is not normal Phase 11 production hard-gate evidence" "$MPV_CLIENT_TEST_FILE" "MPVJSONIPCClientTests.swift is marked reference coverage only"

if [ "$failures" -eq 0 ]; then
  printf 'PASS: Phase 11 MPV production boundary verified\n'
  exit 0
fi

printf 'FAIL: Phase 11 MPV production boundary has %d violation(s)\n' "$failures" >&2
exit 1
