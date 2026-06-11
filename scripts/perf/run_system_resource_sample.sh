#!/usr/bin/env bash
set -euo pipefail

DEFAULT_OUTPUT_ROOT=".planning/phases/11-iina-bridge-security-legacy-boundary-and-reliability-verific/resource-runs"
SCENARIO="phase11-abba"
DURATION_SECONDS=60
SEGMENTS="off,on,on,off"
OUTPUT_ROOT="$DEFAULT_OUTPUT_ROOT"
APP_PATH=""
GLANCEHOLD_PID=""
IINA_PID=""
RUNTIME_COUNTERS_JSON=""
FRAMES_RECEIVED=""
FRAMES_ANALYZED=""
SKIPPED_SAMPLES=""
ANALYZER_RATE_HZ=""
SEMANTIC_STATE_CHANGES=""
PLAYBACK_SNAPSHOTS=""
PLAYBACK_COMMANDS=""

usage() {
    cat <<'USAGE'
Usage:
  scripts/perf/run_system_resource_sample.sh [options]

Collect scalar-only local resource samples for Phase 11 ABBA evidence.

Final Phase 11 ABBA command shape:
  scripts/perf/run_system_resource_sample.sh --scenario phase11-abba --duration-seconds 60 --segment off,on,on,off

Required evidence outputs:
  environment.json  macOS, Xcode, git revision, power source, scenario, duration, segments, optional app path
  summary.json      scalar segment summary with median, p95, and on/off delta fields
  summary.md        readable scalar summary for UAT notes

Options:
  --scenario NAME                 Scenario label. Default: phase11-abba
  --duration-seconds SECONDS      Duration per segment. Default: 60
  --segment LIST                  Comma-separated segment order. Default: off,on,on,off
  --output-root PATH              Output root. Default: .planning/phases/11-iina-bridge-security-legacy-boundary-and-reliability-verific/resource-runs
  --app-path PATH                 Optional GlanceHold.app path metadata only; the sampler does not launch the app.
  --glancehold-pid PID            Optional GlanceHold process id for scalar ps samples.
  --iina-pid PID                  Optional IINA process id for scalar ps samples.
  --runtime-counters-json PATH    Optional manual DiagnosticRuntimeMetrics JSON path.
  --frames-received N             Manual runtime counter: framesReceived.
  --frames-analyzed N             Manual runtime counter: framesAnalyzed.
  --skipped-samples N             Manual runtime counter: skippedSamples.
  --analyzer-rate-hz N            Manual runtime counter: analyzerRateHz.
  --semantic-state-changes N      Manual runtime counter: semanticStateChanges.
  --playback-snapshots N          Manual runtime counter: playbackSnapshots.
  --playback-commands N           Manual runtime counter: playbackCommands.
  --help                          Show this help.

Evidence policy:
  The sampler records CPU, RSS, scalar connection counts, optional-tool status,
  and manually supplied DiagnosticRuntimeMetrics counters. It does not collect
  camera frames, screenshots, raw network payloads, media identity, or visual data.
  There is no fixed watt pass/fail threshold.
USAGE
}

require_value() {
    local option="$1"
    local value="${2:-}"
    if [[ -z "$value" ]]; then
        echo "error: $option requires a value" >&2
        exit 64
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scenario)
            require_value "$1" "${2:-}"
            SCENARIO="$2"
            shift 2
            ;;
        --duration-seconds)
            require_value "$1" "${2:-}"
            DURATION_SECONDS="$2"
            shift 2
            ;;
        --segment)
            require_value "$1" "${2:-}"
            SEGMENTS="$2"
            shift 2
            ;;
        --output-root)
            require_value "$1" "${2:-}"
            OUTPUT_ROOT="$2"
            shift 2
            ;;
        --app-path)
            require_value "$1" "${2:-}"
            APP_PATH="$2"
            shift 2
            ;;
        --glancehold-pid)
            require_value "$1" "${2:-}"
            GLANCEHOLD_PID="$2"
            shift 2
            ;;
        --iina-pid)
            require_value "$1" "${2:-}"
            IINA_PID="$2"
            shift 2
            ;;
        --runtime-counters-json)
            require_value "$1" "${2:-}"
            RUNTIME_COUNTERS_JSON="$2"
            shift 2
            ;;
        --frames-received)
            require_value "$1" "${2:-}"
            FRAMES_RECEIVED="$2"
            shift 2
            ;;
        --frames-analyzed)
            require_value "$1" "${2:-}"
            FRAMES_ANALYZED="$2"
            shift 2
            ;;
        --skipped-samples)
            require_value "$1" "${2:-}"
            SKIPPED_SAMPLES="$2"
            shift 2
            ;;
        --analyzer-rate-hz)
            require_value "$1" "${2:-}"
            ANALYZER_RATE_HZ="$2"
            shift 2
            ;;
        --semantic-state-changes)
            require_value "$1" "${2:-}"
            SEMANTIC_STATE_CHANGES="$2"
            shift 2
            ;;
        --playback-snapshots)
            require_value "$1" "${2:-}"
            PLAYBACK_SNAPSHOTS="$2"
            shift 2
            ;;
        --playback-commands)
            require_value "$1" "${2:-}"
            PLAYBACK_COMMANDS="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "error: unknown option: $1" >&2
            usage >&2
            exit 64
            ;;
    esac
done

case "$DURATION_SECONDS" in
    ''|*[!0-9]*)
        echo "error: --duration-seconds must be a positive integer" >&2
        exit 64
        ;;
esac

if [[ "$DURATION_SECONDS" -lt 1 ]]; then
    echo "error: --duration-seconds must be at least 1" >&2
    exit 64
fi

if [[ -z "$SEGMENTS" ]]; then
    echo "error: --segment must not be empty" >&2
    exit 64
fi

IFS=',' read -r -a SEGMENT_ARRAY <<< "$SEGMENTS"
if [[ "${#SEGMENT_ARRAY[@]}" -eq 0 ]]; then
    echo "error: --segment must include at least one segment" >&2
    exit 64
fi

RUN_STARTED_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
RUN_ID="$(date -u +"%Y%m%dT%H%M%SZ")-${SCENARIO}-$$"
RUN_DIR="${OUTPUT_ROOT%/}/$RUN_ID"

mkdir -p "$OUTPUT_ROOT"
if [[ -e "$RUN_DIR" ]]; then
    echo "error: refusing to reuse existing output directory: $RUN_DIR" >&2
    exit 73
fi
mkdir "$RUN_DIR"

json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    printf '%s' "$value"
}

json_string_or_null() {
    local value="$1"
    if [[ -z "$value" ]]; then
        printf 'null'
    else
        printf '"%s"' "$(json_escape "$value")"
    fi
}

json_number_or_null() {
    local value="$1"
    if [[ -z "$value" ]]; then
        printf 'null'
    else
        printf '%s' "$value"
    fi
}

json_array_from_csv() {
    local csv="$1"
    local first=1
    printf '['
    IFS=',' read -r -a values <<< "$csv"
    for value in "${values[@]}"; do
        if [[ "$first" -eq 0 ]]; then
            printf ','
        fi
        first=0
        printf '"%s"' "$(json_escape "$value")"
    done
    printf ']'
}

tool_path_or_null() {
    local tool="$1"
    local found
    found="$(command -v "$tool" 2>/dev/null || true)"
    json_string_or_null "$found"
}

MACOS_VERSION="$(sw_vers -productVersion 2>/dev/null || true)"
MACOS_BUILD="$(sw_vers -buildVersion 2>/dev/null || true)"
MACHINE_ARCH="$(uname -m 2>/dev/null || true)"
GIT_REVISION="$(git rev-parse --short HEAD 2>/dev/null || true)"
XCODE_VERSION="$(xcodebuild -version 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//' || true)"
POWER_SOURCE="$(pmset -g batt 2>/dev/null | awk -F"'" '/Now drawing from/ { print $2; exit }' || true)"

cat > "$RUN_DIR/environment.json" <<JSON
{
  "run_id": "$(json_escape "$RUN_ID")",
  "started_at_utc": "$(json_escape "$RUN_STARTED_UTC")",
  "scenario": "$(json_escape "$SCENARIO")",
  "duration_seconds_per_segment": $DURATION_SECONDS,
  "segments": $(json_array_from_csv "$SEGMENTS"),
  "output_root": "$(json_escape "$OUTPUT_ROOT")",
  "run_dir": "$(json_escape "$RUN_DIR")",
  "app_path": $(json_string_or_null "$APP_PATH"),
  "glancehold_pid": $(json_number_or_null "$GLANCEHOLD_PID"),
  "iina_pid": $(json_number_or_null "$IINA_PID"),
  "macos_version": $(json_string_or_null "$MACOS_VERSION"),
  "macos_build": $(json_string_or_null "$MACOS_BUILD"),
  "machine_arch": $(json_string_or_null "$MACHINE_ARCH"),
  "xcode_version": $(json_string_or_null "$XCODE_VERSION"),
  "git_revision": $(json_string_or_null "$GIT_REVISION"),
  "power_source": $(json_string_or_null "$POWER_SOURCE"),
  "tools": {
    "ps": $(tool_path_or_null ps),
    "lsof": $(tool_path_or_null lsof),
    "pmset": $(tool_path_or_null pmset),
    "xctrace": $(tool_path_or_null xctrace),
    "powermetrics": $(tool_path_or_null powermetrics)
  }
}
JSON

cat > "$RUN_DIR/samples.csv" <<'CSV'
segment_index,segment,sample_index,epoch_seconds,glancehold_pid,glancehold_cpu_percent,glancehold_rss_kb,iina_pid,iina_cpu_percent,iina_rss_kb,bridge_connection_count
CSV

cat > "$RUN_DIR/summary.json" <<JSON
{
  "scenario": "$(json_escape "$SCENARIO")",
  "run_id": "$(json_escape "$RUN_ID")",
  "segments": $(json_array_from_csv "$SEGMENTS"),
  "statistics": {
    "status": "pending-sampling-implementation",
    "median": null,
    "p95": null,
    "on_off_delta": null
  },
  "runtime_counters": {
    "framesReceived": $(json_number_or_null "$FRAMES_RECEIVED"),
    "framesAnalyzed": $(json_number_or_null "$FRAMES_ANALYZED"),
    "skippedSamples": $(json_number_or_null "$SKIPPED_SAMPLES"),
    "analyzerRateHz": $(json_number_or_null "$ANALYZER_RATE_HZ"),
    "semanticStateChanges": $(json_number_or_null "$SEMANTIC_STATE_CHANGES"),
    "playbackSnapshots": $(json_number_or_null "$PLAYBACK_SNAPSHOTS"),
    "playbackCommands": $(json_number_or_null "$PLAYBACK_COMMANDS"),
    "manual_json_path": $(json_string_or_null "$RUNTIME_COUNTERS_JSON")
  },
  "optional_tools": {
    "xctrace": { "status": "skipped", "reason": "optional supplemental trace not collected by this CLI skeleton" },
    "powermetrics": { "status": "skipped", "reason": "optional supplemental power sample not collected by this CLI skeleton" }
  },
  "privacy": {
    "status": "pending-validation",
    "policy": "scalar-only artifact contract"
  }
}
JSON

cat > "$RUN_DIR/summary.md" <<MD
# GlanceHold Phase 11 Resource Sample

- Scenario: \`$SCENARIO\`
- Run ID: \`$RUN_ID\`
- Segment order: \`$SEGMENTS\`
- Duration per segment: \`$DURATION_SECONDS\` seconds
- Output directory: \`$RUN_DIR\`

Artifacts:

- \`environment.json\`
- \`summary.json\`
- \`summary.md\`
- \`samples.csv\`

This initial artifact confirms the unique output contract. Scalar sampling,
median, p95, on/off delta, and privacy validation are completed by the next
implementation step. There is no fixed watt pass/fail threshold.
MD

echo "$RUN_DIR"
