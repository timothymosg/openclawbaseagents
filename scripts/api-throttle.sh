#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# OpenClaw API Throttle Controller
# Human-like rate limiting for all external API calls
#
# Usage:
#   api-throttle.sh <service-name> [--dry-run] -- <command...>
#   api-throttle.sh --status [service-name]
#   api-throttle.sh --reset <service-name>
#
# Examples:
#   api-throttle.sh openrouter -- curl -s https://openrouter.ai/api/v1/...
#   api-throttle.sh telegram -- curl -s https://api.telegram.org/...
#   api-throttle.sh github -- gh api /repos/...
#   api-throttle.sh --status
# ============================================================================

THROTTLE_DIR="${OPENCLAW_THROTTLE_DIR:-$HOME/.openclaw/shared-data/api-throttle}"
CONFIG_FILE="$THROTTLE_DIR/config.json"
STATE_DIR="$THROTTLE_DIR/state"
LOG_FILE="$THROTTLE_DIR/throttle.log"

# --- Ensure dirs exist ---
mkdir -p "$STATE_DIR"

# --- Helpers ---

log() {
  local timestamp
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"
  echo "$timestamp | $*" >> "$LOG_FILE"
}

die() {
  echo "ERROR: $*" >&2
  log "ERROR | $*"
  exit 1
}

# Read a JSON value using python3 (available on most systems, no jq dependency)
json_get() {
  local file="$1" path="$2" default="${3:-}"
  python3 -c "
import json, sys
try:
    with open('$file') as f:
        data = json.load(f)
    keys = '$path'.split('.')
    val = data
    for k in keys:
        if isinstance(val, dict) and k in val:
            val = val[k]
        else:
            print('$default')
            sys.exit(0)
    print(val if not isinstance(val, (dict, list)) else json.dumps(val))
except Exception:
    print('$default')
" 2>/dev/null
}

# Get service-specific config, falling back to defaults
get_config() {
  local service="$1" key="$2" default="$3"
  local val
  # Try service-specific first
  val="$(json_get "$CONFIG_FILE" "services.$service.$key" "")"
  if [ -n "$val" ] && [ "$val" != "None" ]; then
    echo "$val"
    return
  fi
  # Fall back to defaults
  val="$(json_get "$CONFIG_FILE" "defaults.$key" "$default")"
  if [ -n "$val" ] && [ "$val" != "None" ]; then
    echo "$val"
    return
  fi
  echo "$default"
}

# Generate a human-like random delay (weighted toward shorter pauses)
# Uses a rough approximation of gaussian distribution via multiple randoms
human_delay() {
  local min_ms="$1" max_ms="$2"
  python3 -c "
import random, time

min_s = $min_ms / 1000.0
max_s = $max_ms / 1000.0
mid = (min_s + max_s) / 2.0
spread = (max_s - min_s) / 4.0

# Gaussian-like distribution centered slightly below midpoint
# Mimics human behavior: mostly quick, occasionally slow
delay = random.gauss(mid * 0.7, spread)

# 5% chance of a longer 'thinking' pause (2x-3x normal)
if random.random() < 0.05:
    delay = delay * random.uniform(2.0, 3.0)

# Clamp to bounds
delay = max(min_s, min(max_s * 1.5, delay))

print(f'{delay:.3f}')
"
}

# Get milliseconds since epoch
now_ms() {
  python3 -c "import time; print(int(time.time() * 1000))"
}

# --- State management ---

state_file() {
  local service="$1"
  echo "$STATE_DIR/${service}.state"
}

read_state() {
  local service="$1"
  local sf
  sf="$(state_file "$service")"
  if [ -f "$sf" ]; then
    cat "$sf"
  else
    echo '{"last_call_ms":0,"call_count":0,"window_start_ms":0,"backoff_level":0,"total_calls":0}'
  fi
}

write_state() {
  local service="$1" state_json="$2"
  echo "$state_json" > "$(state_file "$service")"
}

# --- Burst window management ---

check_and_update_burst() {
  local service="$1"
  local max_burst window_sec
  max_burst="$(get_config "$service" "max_burst" "10")"
  window_sec="$(get_config "$service" "burst_window_sec" "60")"

  local state now count window_start
  state="$(read_state "$service")"
  now="$(now_ms)"

  python3 -c "
import json, sys

state = json.loads('$state')
now = $now
window_ms = $window_sec * 1000
max_burst = $max_burst

window_start = state.get('window_start_ms', 0)
count = state.get('call_count', 0)

# Reset window if expired
if now - window_start > window_ms:
    window_start = now
    count = 0

if count >= max_burst:
    # Burst limit reached — calculate wait time
    wait_until = window_start + window_ms
    wait_ms = wait_until - now
    print(f'WAIT:{wait_ms}')
    sys.exit(0)

# Update state
count += 1
state['call_count'] = count
state['window_start_ms'] = window_start
state['last_call_ms'] = now
state['total_calls'] = state.get('total_calls', 0) + 1

print('OK')
print(json.dumps(state))
"
}

# --- Backoff management ---

get_backoff_delay() {
  local service="$1"
  local state backoff_level backoff_base max_backoff
  state="$(read_state "$service")"
  backoff_base="$(get_config "$service" "backoff_base_ms" "5000")"
  max_backoff="$(get_config "$service" "max_backoff_ms" "300000")"

  python3 -c "
import json, random

state = json.loads('$state')
level = state.get('backoff_level', 0)
if level == 0:
    print('0')
else:
    # Exponential backoff with jitter
    base = $backoff_base
    delay = base * (2 ** (level - 1))
    delay = min(delay, $max_backoff)
    # Add 10-30% jitter
    jitter = delay * random.uniform(0.1, 0.3)
    delay = delay + jitter
    print(f'{delay / 1000:.3f}')
"
}

increment_backoff() {
  local service="$1"
  local state
  state="$(read_state "$service")"
  local new_state
  new_state="$(python3 -c "
import json
state = json.loads('$state')
state['backoff_level'] = min(state.get('backoff_level', 0) + 1, 8)
print(json.dumps(state))
")"
  write_state "$service" "$new_state"
  log "BACKOFF | $service | level=$(python3 -c "import json; print(json.loads('$new_state')['backoff_level'])")"
}

reset_backoff() {
  local service="$1"
  local state
  state="$(read_state "$service")"
  local new_state
  new_state="$(python3 -c "
import json
state = json.loads('$state')
state['backoff_level'] = 0
print(json.dumps(state))
")"
  write_state "$service" "$new_state"
}

# --- Session warmup ---

check_warmup() {
  local service="$1"
  local state last_call now warmup_threshold
  state="$(read_state "$service")"
  now="$(now_ms)"
  warmup_threshold="$(get_config "$service" "warmup_threshold_sec" "300")"

  python3 -c "
import json

state = json.loads('$state')
last = state.get('last_call_ms', 0)
now = $now
threshold = $warmup_threshold * 1000

if last == 0 or (now - last) > threshold:
    print('WARMUP')
else:
    print('HOT')
"
}

# --- Main throttle logic ---

throttle_and_execute() {
  local service="$1"
  shift
  local dry_run=false

  if [ "$1" = "--dry-run" ]; then
    dry_run=true
    shift
  fi

  # Skip the -- separator
  if [ "${1:-}" = "--" ]; then
    shift
  fi

  if [ $# -eq 0 ]; then
    die "No command provided after service name"
  fi

  # Check if throttle is enabled
  local enabled
  enabled="$(json_get "$CONFIG_FILE" "enabled" "true")"
  if [ "$enabled" = "False" ] || [ "$enabled" = "false" ]; then
    log "BYPASS | $service | throttle disabled globally"
    exec "$@"
  fi

  # Check if service is excluded
  local excluded
  excluded="$(get_config "$service" "excluded" "false")"
  if [ "$excluded" = "True" ] || [ "$excluded" = "true" ]; then
    log "BYPASS | $service | service excluded"
    exec "$@"
  fi

  local total_delay=0

  # 1. Check warmup BEFORE any state updates (needs original last_call_ms)
  local warmup
  warmup="$(check_warmup "$service")"

  # 2. Check backoff state (from previous errors)
  local backoff_delay
  backoff_delay="$(get_backoff_delay "$service")"
  if [ "$backoff_delay" != "0" ]; then
    log "BACKOFF_WAIT | $service | ${backoff_delay}s"
    total_delay="$(python3 -c "print($total_delay + $backoff_delay)")"
  fi

  # 3. Check burst limit (updates state with new last_call_ms)
  local burst_result
  burst_result="$(check_and_update_burst "$service")"
  local burst_status
  burst_status="$(echo "$burst_result" | head -1)"

  if [[ "$burst_status" == WAIT:* ]]; then
    local wait_ms="${burst_status#WAIT:}"
    local wait_sec
    wait_sec="$(python3 -c "print($wait_ms / 1000.0)")"
    log "BURST_WAIT | $service | ${wait_sec}s (burst limit reached)"
    total_delay="$(python3 -c "print($total_delay + $wait_sec)")"
  else
    # Update state from burst check
    local new_state
    new_state="$(echo "$burst_result" | tail -1)"
    write_state "$service" "$new_state"
  fi

  # 4. Human-like delay
  local min_delay max_delay
  min_delay="$(get_config "$service" "min_delay_ms" "1000")"
  max_delay="$(get_config "$service" "max_delay_ms" "5000")"
  if [ "$warmup" = "WARMUP" ]; then
    # First call gets a longer delay (simulating opening a browser)
    local warmup_min warmup_max
    warmup_min="$(get_config "$service" "warmup_min_ms" "3000")"
    warmup_max="$(get_config "$service" "warmup_max_ms" "8000")"
    local warmup_delay
    warmup_delay="$(human_delay "$warmup_min" "$warmup_max")"
    total_delay="$(python3 -c "print($total_delay + $warmup_delay)")"
    log "WARMUP | $service | ${warmup_delay}s (session start)"
  else
    local normal_delay
    normal_delay="$(human_delay "$min_delay" "$max_delay")"
    total_delay="$(python3 -c "print($total_delay + $normal_delay)")"
  fi

  # 5. Inter-agent jitter (prevent simultaneous calls from multiple agents)
  local jitter
  jitter="$(python3 -c "import random; print(f'{random.uniform(0.1, 0.8):.3f}')")"
  total_delay="$(python3 -c "print($total_delay + $jitter)")"

  # 6. Apply the delay
  if [ "$dry_run" = true ]; then
    echo "THROTTLE: $service | delay=${total_delay}s | warmup=$warmup | command=$*"
    return 0
  fi

  log "THROTTLE | $service | delay=${total_delay}s | warmup=$warmup | cmd=$(echo "$*" | head -c 100)"

  # Sleep for the calculated delay
  python3 -c "import time; time.sleep($total_delay)"

  # 7. Execute the command and capture exit code
  local exit_code=0
  "$@" || exit_code=$?

  # 8. Handle rate-limit responses (check exit code and common patterns)
  if [ $exit_code -ne 0 ]; then
    # Increment backoff on failure
    increment_backoff "$service"
    log "FAIL | $service | exit_code=$exit_code"
  else
    # Reset backoff on success
    reset_backoff "$service"
  fi

  return $exit_code
}

# --- Status display ---

show_status() {
  local filter="${1:-}"
  echo "=== OpenClaw API Throttle Status ==="
  echo "Config: $CONFIG_FILE"
  echo "State:  $STATE_DIR"
  echo ""

  local enabled
  enabled="$(json_get "$CONFIG_FILE" "enabled" "true")"
  echo "Global throttle: $enabled"
  echo ""

  if [ -n "$filter" ]; then
    # Show single service
    local sf
    sf="$(state_file "$filter")"
    if [ -f "$sf" ]; then
      echo "Service: $filter"
      python3 -c "
import json
with open('$sf') as f:
    state = json.load(f)
last = state.get('last_call_ms', 0)
if last > 0:
    import datetime
    dt = datetime.datetime.fromtimestamp(last / 1000, tz=datetime.timezone.utc)
    print(f'  Last call:     {dt.strftime(\"%Y-%m-%d %H:%M:%S UTC\")}')
else:
    print('  Last call:     never')
print(f'  Burst count:   {state.get(\"call_count\", 0)}')
print(f'  Backoff level: {state.get(\"backoff_level\", 0)}')
print(f'  Total calls:   {state.get(\"total_calls\", 0)}')
"
    else
      echo "No state for service: $filter"
    fi
  else
    # Show all services
    echo "Service states:"
    for sf in "$STATE_DIR"/*.state; do
      [ -f "$sf" ] || continue
      local svc
      svc="$(basename "$sf" .state)"
      python3 -c "
import json, datetime
with open('$sf') as f:
    state = json.load(f)
last = state.get('last_call_ms', 0)
if last > 0:
    dt = datetime.datetime.fromtimestamp(last / 1000, tz=datetime.timezone.utc)
    last_str = dt.strftime('%Y-%m-%d %H:%M:%S')
else:
    last_str = 'never'
bo = state.get('backoff_level', 0)
total = state.get('total_calls', 0)
bo_str = f' [BACKOFF:{bo}]' if bo > 0 else ''
print(f'  {\"$svc\":<20} calls={total:<6} last={last_str}{bo_str}')
"
    done

    if ! ls "$STATE_DIR"/*.state &>/dev/null; then
      echo "  (no calls recorded yet)"
    fi
  fi

  # Show recent log entries
  echo ""
  if [ -f "$LOG_FILE" ]; then
    echo "Recent activity (last 10):"
    tail -10 "$LOG_FILE" | sed 's/^/  /'
  fi
}

# --- Reset service state ---

reset_service() {
  local service="$1"
  local sf
  sf="$(state_file "$service")"
  if [ -f "$sf" ]; then
    rm "$sf"
    log "RESET | $service | state cleared"
    echo "Reset state for: $service"
  else
    echo "No state to reset for: $service"
  fi
}

# --- Main ---

if [ $# -eq 0 ]; then
  echo "Usage:"
  echo "  api-throttle.sh <service> [--dry-run] -- <command...>"
  echo "  api-throttle.sh --status [service]"
  echo "  api-throttle.sh --reset <service>"
  exit 1
fi

case "$1" in
  --status)
    show_status "${2:-}"
    ;;
  --reset)
    [ -n "${2:-}" ] || die "--reset requires a service name"
    reset_service "$2"
    ;;
  --help|-h)
    echo "OpenClaw API Throttle Controller"
    echo ""
    echo "Adds human-like delays between external API calls to prevent bot detection."
    echo ""
    echo "Usage:"
    echo "  api-throttle.sh <service> [--dry-run] -- <command...>"
    echo "  api-throttle.sh --status [service]"
    echo "  api-throttle.sh --reset <service>"
    echo ""
    echo "Services are defined in: $CONFIG_FILE"
    echo "State is stored in:      $STATE_DIR"
    echo "Logs are written to:     $LOG_FILE"
    ;;
  *)
    throttle_and_execute "$@"
    ;;
esac
