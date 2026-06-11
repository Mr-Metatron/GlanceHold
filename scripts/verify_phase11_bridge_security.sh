#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RUNTIME_AND_DOC_FILES=(
  "GlanceHold/IINAPluginBridgeClient.swift"
  "IINAPlugin/GlanceHoldBridge.iinaplugin/main.js"
  "IINAPlugin/GlanceHoldBridge.iinaplugin/Info.json"
  "IINAPlugin/README.md"
  "README.md"
)

PLUGIN_README="IINAPlugin/README.md"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_file() {
  local file="$1"
  [[ -f "$file" ]] || fail "required file is missing: $file"
}

require_contains() {
  local file="$1"
  local needle="$2"
  local description="$3"
  grep -Fq -- "$needle" "$file" || fail "$description not found in $file"
}

reject_fixed() {
  local needle="$1"
  local description="$2"
  local found=0

  for file in "${RUNTIME_AND_DOC_FILES[@]}"; do
    local matches
    matches="$(grep -nF -- "$needle" "$file" || true)"
    if [[ -n "$matches" ]]; then
      printf 'Forbidden %s in %s:\n%s\n' "$description" "$file" "$matches" >&2
      found=1
    fi
  done

  [[ "$found" -eq 0 ]] || fail "forbidden bridge token/auth remnant found: $description"
}

reject_regex() {
  local pattern="$1"
  local description="$2"
  local found=0

  for file in "${RUNTIME_AND_DOC_FILES[@]}"; do
    local matches
    matches="$(grep -nEi -- "$pattern" "$file" || true)"
    if [[ -n "$matches" ]]; then
      printf 'Forbidden %s in %s:\n%s\n' "$description" "$file" "$matches" >&2
      found=1
    fi
  done

  [[ "$found" -eq 0 ]] || fail "forbidden bridge token/auth remnant found: $description"
}

for file in "${RUNTIME_AND_DOC_FILES[@]}"; do
  require_file "$file"
done

# Test fixtures intentionally live outside RUNTIME_AND_DOC_FILES. Negative
# strings in XCTest or the Node VM harness must not fail this runtime/docs gate.
reject_fixed "request.token" "request token field"
reject_fixed "bridgeTokenPreferenceKey" "Swift bridge token preference key"
reject_fixed "iinaPluginBridgeToken" "app bridge token defaults key"
reject_fixed "Bridge Token" "user-facing bridge token label"
reject_fixed "preferences.get(\"bridgeToken\")" "plugin bridge token preference read"
reject_fixed "data-pref-key=\"bridgeToken\"" "plugin bridge token preference UI field"
reject_fixed "bridgeToken" "camelCase bridge token setting"

reject_regex 'preferencesPage' "plugin preferences page"
reject_regex 'preferenceDefaults[^[:alnum:]_]+bridgeToken' "plugin bridge token default"
reject_regex '(plugin|bridge)[[:space:]_-]+token[[:space:]_-]+preference' "plugin token preference guidance"
reject_regex 'token[[:space:]_-]+preference' "token preference guidance"
reject_regex 'preference[[:space:]_-]+token' "preference token guidance"
reject_regex '(pairing|pair[[:space:]_-]+code|client[[:space:]_-]*id|client[[:space:]_-]+identifier)' "pairing or client-id ceremony"
reject_regex '(remoteHost|remote[[:space:]_-]+host[[:space:]_-]+(setup|setting|settings|preference|field|url|address)|configure[^[:space:]]*[[:space:]]+remote[[:space:]_-]+host)' "remote host setup guidance"
reject_regex '(copy|paste).*(bridge[[:space:]_-]+)?token.*(preference|setting|field|setup|into|iina)' "token copy/paste setup guidance"

require_contains "$PLUGIN_README" "127.0.0.1" "loopback address"
require_contains "$PLUGIN_README" "No request token is required." "no-token trust statement"
require_contains "$PLUGIN_README" "There is no remote host configuration." "no-remote-host trust statement"

for command in snapshot setSpeed pause resume; do
  require_contains "$PLUGIN_README" "$command" "whitelist command $command"
done

printf 'PASS: Phase 11 bridge security static gate\n'
