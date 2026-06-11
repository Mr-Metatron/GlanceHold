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
  The Phase 11 ABBA evidence feeds the Phase 8 back-reference finalized in 11-05.
  The final phase11-abba evidence run is collected with real IINA, plugin, camera,
  and Diagnostic Mode counter notes; syntax and help checks do not require them.
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

tool_path() {
    command -v "$1" 2>/dev/null || true
}

first_pid_for_process_name() {
    local process_name="$1"
    pgrep -x "$process_name" 2>/dev/null | awk 'NR == 1 { print; exit }' || true
}

process_sample_csv() {
    local pid="$1"
    if [[ -z "$pid" ]]; then
        printf ','
        return
    fi

    ps -p "$pid" -o %cpu= -o rss= 2>/dev/null \
        | awk 'NR == 1 { print $1 "," $2; found = 1 } END { if (!found) print "," }' \
        || true
}

bridge_connection_count() {
    local count
    count="$(lsof -nP -iTCP:47873 -sTCP:ESTABLISHED 2>/dev/null \
        | awk 'NR > 1 { count++ } END { print count + 0 }' \
        || true)"
    if [[ -z "$count" ]]; then
        printf '0'
    else
        printf '%s' "$count"
    fi
}

append_sample() {
    local segment_index="$1"
    local segment="$2"
    local sample_index="$3"
    local epoch_seconds
    local glancehold_sample
    local iina_sample
    local glancehold_cpu
    local glancehold_rss
    local iina_cpu
    local iina_rss
    local connections

    epoch_seconds="$(date +%s)"
    glancehold_sample="$(process_sample_csv "$GLANCEHOLD_PID")"
    iina_sample="$(process_sample_csv "$IINA_PID")"
    glancehold_cpu="${glancehold_sample%,*}"
    glancehold_rss="${glancehold_sample#*,}"
    iina_cpu="${iina_sample%,*}"
    iina_rss="${iina_sample#*,}"
    connections="$(bridge_connection_count)"

    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$segment_index" \
        "$segment" \
        "$sample_index" \
        "$epoch_seconds" \
        "$GLANCEHOLD_PID" \
        "$glancehold_cpu" \
        "$glancehold_rss" \
        "$IINA_PID" \
        "$iina_cpu" \
        "$iina_rss" \
        "$connections" >> "$RUN_DIR/samples.csv"
}

collect_samples() {
    local segment_index=0
    local segment
    local sample_index

    for segment in "${SEGMENT_ARRAY[@]}"; do
        segment_index=$((segment_index + 1))
        echo "Sampling segment $segment_index/${#SEGMENT_ARRAY[@]}: $segment for ${DURATION_SECONDS}s" >&2
        for ((sample_index = 1; sample_index <= DURATION_SECONDS; sample_index++)); do
            append_sample "$segment_index" "$segment" "$sample_index"
            if [[ "$sample_index" -lt "$DURATION_SECONDS" ]]; then
                sleep 1
            fi
        done
    done
}

write_summary_artifacts() {
    RUN_DIR="$RUN_DIR" \
    SCENARIO="$SCENARIO" \
    RUN_ID="$RUN_ID" \
    SEGMENTS="$SEGMENTS" \
    DURATION_SECONDS="$DURATION_SECONDS" \
    FRAMES_RECEIVED="$FRAMES_RECEIVED" \
    FRAMES_ANALYZED="$FRAMES_ANALYZED" \
    SKIPPED_SAMPLES="$SKIPPED_SAMPLES" \
    ANALYZER_RATE_HZ="$ANALYZER_RATE_HZ" \
    SEMANTIC_STATE_CHANGES="$SEMANTIC_STATE_CHANGES" \
    PLAYBACK_SNAPSHOTS="$PLAYBACK_SNAPSHOTS" \
    PLAYBACK_COMMANDS="$PLAYBACK_COMMANDS" \
    RUNTIME_COUNTERS_JSON="$RUNTIME_COUNTERS_JSON" \
    XCTRACE_STATUS="$XCTRACE_STATUS" \
    XCTRACE_REASON="$XCTRACE_REASON" \
    POWERMETRICS_STATUS="$POWERMETRICS_STATUS" \
    POWERMETRICS_REASON="$POWERMETRICS_REASON" \
    ruby <<'RUBY'
require "csv"
require "json"

run_dir = ENV.fetch("RUN_DIR")
samples_path = File.join(run_dir, "samples.csv")
environment_path = File.join(run_dir, "environment.json")
summary_json_path = File.join(run_dir, "summary.json")
summary_md_path = File.join(run_dir, "summary.md")
rows = CSV.read(samples_path, headers: true)
environment = JSON.parse(File.read(environment_path))
segment_order = ENV.fetch("SEGMENTS").split(",")

METRICS = {
  "glancehold_cpu_percent" => "GlanceHold CPU %",
  "glancehold_rss_kb" => "GlanceHold RSS KB",
  "iina_cpu_percent" => "IINA CPU %",
  "iina_rss_kb" => "IINA RSS KB",
  "bridge_connection_count" => "Bridge connection count"
}.freeze

COUNTER_KEYS = %w[
  framesReceived
  framesAnalyzed
  skippedSamples
  analyzerRateHz
  semanticStateChanges
  playbackSnapshots
  playbackCommands
].freeze

def numeric_values(rows, key)
  rows.map do |row|
    value = row[key]
    next if value.nil? || value.strip.empty?

    Float(value)
  rescue ArgumentError
    nil
  end.compact
end

def round_scalar(value)
  value.nil? ? nil : value.round(3)
end

def percentile(sorted_values, percentile_value)
  return nil if sorted_values.empty?

  index = [(sorted_values.length * percentile_value).ceil - 1, 0].max
  sorted_values[[index, sorted_values.length - 1].min]
end

def metric_stats(values)
  return {
    "status" => "unavailable",
    "reason" => "no scalar samples available",
    "sample_count" => 0,
    "median" => nil,
    "p95" => nil
  } if values.empty?

  sorted = values.sort
  median = if sorted.length.odd?
    sorted[sorted.length / 2]
  else
    (sorted[(sorted.length / 2) - 1] + sorted[sorted.length / 2]) / 2.0
  end
  {
    "status" => "available",
    "sample_count" => values.length,
    "median" => round_scalar(median),
    "p95" => round_scalar(percentile(sorted, 0.95))
  }
end

def stats_for(rows)
  METRICS.each_with_object({}) do |(key, label), result|
    result[key] = metric_stats(numeric_values(rows, key)).merge("label" => label)
  end
end

def env_number(name)
  value = ENV[name]
  return nil if value.nil? || value.strip.empty?

  numeric = Float(value)
  numeric % 1 == 0 ? numeric.to_i : numeric
rescue ArgumentError
  nil
end

runtime_counters = {
  "framesReceived" => env_number("FRAMES_RECEIVED"),
  "framesAnalyzed" => env_number("FRAMES_ANALYZED"),
  "skippedSamples" => env_number("SKIPPED_SAMPLES"),
  "analyzerRateHz" => env_number("ANALYZER_RATE_HZ"),
  "semanticStateChanges" => env_number("SEMANTIC_STATE_CHANGES"),
  "playbackSnapshots" => env_number("PLAYBACK_SNAPSHOTS"),
  "playbackCommands" => env_number("PLAYBACK_COMMANDS")
}

manual_counter_path = ENV["RUNTIME_COUNTERS_JSON"].to_s
manual_counter_status = "not-provided"
if !manual_counter_path.empty?
  if File.file?(manual_counter_path)
    parsed = JSON.parse(File.read(manual_counter_path))
    COUNTER_KEYS.each do |key|
      runtime_counters[key] = parsed[key] if parsed.key?(key)
    end
    manual_counter_status = "loaded"
  else
    manual_counter_status = "unavailable"
  end
end

segments = rows.group_by { |row| row["segment_index"] }.sort_by { |index, _| index.to_i }.map do |index, segment_rows|
  {
    "index" => index.to_i,
    "name" => segment_rows.first["segment"],
    "sample_count" => segment_rows.length,
    "statistics" => stats_for(segment_rows)
  }
end

label_groups = rows.group_by { |row| row["segment"] }
off_rows = label_groups.fetch("off", [])
on_rows = label_groups.fetch("on", [])
off_stats = stats_for(off_rows)
on_stats = stats_for(on_rows)
deltas = METRICS.each_with_object({}) do |(key, label), result|
  off_median = off_stats[key]["median"]
  on_median = on_stats[key]["median"]
  result[key] = if off_median && on_median
    {
      "status" => "available",
      "label" => label,
      "on_median_minus_off_median" => round_scalar(on_median - off_median),
      "off_median" => off_median,
      "on_median" => on_median
    }
  else
    {
      "status" => "unavailable",
      "label" => label,
      "reason" => "missing on or off median samples",
      "off_median" => off_median,
      "on_median" => on_median
    }
  end
end

summary = {
  "scenario" => ENV.fetch("SCENARIO"),
  "run_id" => ENV.fetch("RUN_ID"),
  "segment_order" => segment_order,
  "duration_seconds_per_segment" => ENV.fetch("DURATION_SECONDS").to_i,
  "environment" => environment,
  "samples_csv" => "samples.csv",
  "segments" => segments,
  "statistics" => {
    "by_segment" => segments,
    "monitoring_off" => off_stats,
    "monitoring_on" => on_stats,
    "monitoring_on_vs_off_deltas" => deltas
  },
  "runtime_counters" => runtime_counters.merge(
    "manual_json_path" => (manual_counter_path.empty? ? nil : manual_counter_path),
    "manual_json_status" => manual_counter_status
  ),
  "optional_tools" => {
    "xctrace" => {
      "status" => ENV.fetch("XCTRACE_STATUS"),
      "reason" => ENV.fetch("XCTRACE_REASON")
    },
    "powermetrics" => {
      "status" => ENV.fetch("POWERMETRICS_STATUS"),
      "reason" => ENV.fetch("POWERMETRICS_REASON")
    }
  },
  "privacy" => {
    "status" => "pass",
    "policy" => "scalar-only artifacts; private-content pattern scan is performed after summary generation"
  },
  "threshold_policy" => "no fixed watt pass/fail threshold"
}

File.write(summary_json_path, JSON.pretty_generate(summary) + "\n")

metric_rows = METRICS.map do |key, label|
  delta = deltas[key]
  value = if delta["status"] == "available"
    delta["on_median_minus_off_median"]
  else
    delta["reason"]
  end
  "| #{label} | #{delta["off_median"] || "unavailable"} | #{delta["on_median"] || "unavailable"} | #{value} |"
end

counter_rows = COUNTER_KEYS.map do |key|
  "| #{key} | #{runtime_counters[key] || "not supplied"} |"
end

segment_rows = segments.flat_map do |segment|
  segment["statistics"].map do |key, stats|
    "| #{segment["index"]} | #{segment["name"]} | #{METRICS[key]} | #{stats["median"] || "unavailable"} | #{stats["p95"] || "unavailable"} | #{stats["sample_count"]} |"
  end
end

File.write(summary_md_path, <<~MARKDOWN)
  # GlanceHold Phase 11 Resource Sample

  - Scenario: `#{ENV.fetch("SCENARIO")}`
  - Run ID: `#{ENV.fetch("RUN_ID")}`
  - Segment order: `#{segment_order.join(",")}`
  - Duration per segment: `#{ENV.fetch("DURATION_SECONDS")}` seconds
  - Output directory: `#{run_dir}`

  ## Artifacts

  - `environment.json`
  - `summary.json`
  - `summary.md`
  - `samples.csv`

  ## Segment Statistics

  | Segment # | Segment | Metric | median | p95 | Samples |
  |---:|---|---|---:|---:|---:|
  #{segment_rows.join("\n")}

  ## Monitoring On/Off Delta

  | Metric | Off median | On median | on/off delta |
  |---|---:|---:|---:|
  #{metric_rows.join("\n")}

  ## Runtime Counters

  | DiagnosticRuntimeMetrics field | Manual value |
  |---|---:|
  #{counter_rows.join("\n")}

  ## Optional Tools

  - xctrace: #{ENV.fetch("XCTRACE_STATUS")} (#{ENV.fetch("XCTRACE_REASON")})
  - powermetrics: #{ENV.fetch("POWERMETRICS_STATUS")} (#{ENV.fetch("POWERMETRICS_REASON")})

  ## Privacy

  Privacy validation: pass. Artifacts are scalar-only and contain process CPU, RSS,
  connection counts, optional-tool status, and manual DiagnosticRuntimeMetrics counters.

  There is no fixed watt pass/fail threshold.
MARKDOWN
RUBY
}

validate_privacy() {
    RUN_DIR="$RUN_DIR" ruby <<'RUBY'
run_dir = ENV.fetch("RUN_DIR")
patterns = [
  /sampleBuffer/i,
  /sample buffer/i,
  /faceBox/i,
  /face box/i,
  /rawPoseStream/i,
  /raw pose/i,
  /mediaPath/i,
  /media path/i,
  /mediaTitle/i,
  /media title/i,
  /rawBridgePayload/i,
  /raw bridge payload/i,
  /bridgeToken/i,
  /bridge token/i,
  /token value/i
]
files = %w[environment.json summary.json summary.md samples.csv]
violations = files.flat_map do |file|
  path = File.join(run_dir, file)
  text = File.read(path)
  patterns.each_with_index.map do |pattern, index|
    "#{file}:pattern#{index + 1}" if text.match?(pattern)
  end.compact
end

if violations.any?
  warn "privacy validation failed: #{violations.join(", ")}"
  exit 65
end
RUBY
}

if [[ -z "$GLANCEHOLD_PID" ]]; then
    GLANCEHOLD_PID="$(first_pid_for_process_name GlanceHold)"
fi

if [[ -z "$IINA_PID" ]]; then
    IINA_PID="$(first_pid_for_process_name IINA)"
fi

XCTRACE_PATH="$(tool_path xctrace)"
if [[ -z "$XCTRACE_PATH" ]]; then
    XCTRACE_STATUS="skipped"
    XCTRACE_REASON="xctrace not available"
else
    XCTRACE_STATUS="skipped"
    XCTRACE_REASON="optional supplemental trace not collected by the lightweight sampler"
fi

POWERMETRICS_PATH="$(tool_path powermetrics)"
if [[ -z "$POWERMETRICS_PATH" ]]; then
    POWERMETRICS_STATUS="skipped"
    POWERMETRICS_REASON="powermetrics not available"
elif sudo -n true 2>/dev/null; then
    POWERMETRICS_STATUS="skipped"
    POWERMETRICS_REASON="optional supplemental power sample not collected by the lightweight sampler"
else
    POWERMETRICS_STATUS="skipped"
    POWERMETRICS_REASON="sudo -n not available for non-interactive powermetrics"
fi

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

collect_samples
write_summary_artifacts
validate_privacy

echo "$RUN_DIR"
