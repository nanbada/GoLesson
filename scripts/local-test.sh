#!/usr/bin/env bash
# Start a disposable local GoLesson test environment.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$ROOT_DIR/.local-test"
FUNCTION_PID_FILE="$STATE_DIR/functions.pid"
FUNCTION_LOG_FILE="$STATE_DIR/functions.log"
FUNCTION_OWNERSHIP_FILE="$STATE_DIR/functions.started"
WEB_PID_FILE="$STATE_DIR/web.pid"
WEB_LOG_FILE="$STATE_DIR/web.log"
LOCAL_WEB_URL="http://127.0.0.1:3100"

RESET_DB=false
STOP_SUPABASE=false
STARTED_PIDS=()

log() {
  printf '%s\n' "$*"
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  scripts/local-test.sh start [--reset-db]
  scripts/local-test.sh stop [--stop-supabase]
  scripts/local-test.sh status

Commands:
  start               Start local Supabase, Edge Functions, and the web server.
  --reset-db          Reset only the local database, seed fixtures, and recreate
                      the two local test users. This deletes local test data.
  stop                Stop the web server and Edge Functions started by this script.
  --stop-supabase     Also run "supabase stop" without deleting local volumes.
  status              Show local service readiness without printing credentials.
EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command is unavailable: $1"
}

ensure_docker_runtime() {
  require_command docker
  if docker info >/dev/null 2>&1; then
    return
  fi

  if command -v orb >/dev/null 2>&1; then
    log "Starting OrbStack..."
    orb start >/dev/null 2>&1 || true
  fi

  for _ in {1..30}; do
    if docker info >/dev/null 2>&1; then
      return
    fi
    sleep 1
  done

  fail "No Docker-compatible runtime is available. Start OrbStack, Docker Desktop, or another Docker-compatible runtime first."
}

is_local_supabase_running() {
  supabase status -o env >/dev/null 2>&1
}

read_local_supabase_env() {
  local status_env
  status_env="$(supabase status -o env 2>/dev/null)" || fail "Local Supabase is not running."

  # Supabase CLI versions emit either KEY=value lines or a JSON object here.
  LOCAL_API_URL="$(printf '%s\n' "$status_env" | sed -n -E \
    -e 's/^API_URL="?([^"]*)"?$/\1/p' \
    -e 's/^[[:space:]]*"API_URL":[[:space:]]*"([^"]*)"[,]?$/\1/p')"
  LOCAL_SERVICE_ROLE_KEY="$(printf '%s\n' "$status_env" | sed -n -E \
    -e 's/^SERVICE_ROLE_KEY="?([^"]*)"?$/\1/p' \
    -e 's/^[[:space:]]*"SERVICE_ROLE_KEY":[[:space:]]*"([^"]*)"[,]?$/\1/p')"

  case "$LOCAL_API_URL" in
    http://127.0.0.1:*|http://localhost:*) ;;
    *) fail "Refusing to operate on a non-local Supabase URL."
  esac

  [ -n "$LOCAL_SERVICE_ROLE_KEY" ] || fail "Local Supabase did not provide a service-role key."
}

wait_for_http() {
  local url="$1"
  local label="$2"
  local attempts="${3:-30}"
  local status

  for _ in $(seq 1 "$attempts"); do
    status="$(curl --connect-timeout 1 --max-time 2 -sS -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || true)"
    if [ "$status" -ge 200 ] 2>/dev/null && [ "$status" -lt 500 ] 2>/dev/null; then
      return
    fi
    sleep 1
  done

  fail "$label did not become ready. Check the log file in $STATE_DIR."
}

functions_ready() {
  local status
  status="$(curl --connect-timeout 1 --max-time 2 -sS -X OPTIONS -o /dev/null -w '%{http_code}' "$LOCAL_API_URL/functions/v1/parse-batch" 2>/dev/null || true)"
  [ "$status" = "200" ]
}

wait_for_functions() {
  for _ in {1..30}; do
    if functions_ready; then
      return
    fi
    sleep 1
  done

  fail "Edge Functions did not become ready. Check $FUNCTION_LOG_FILE."
}

pid_is_running() {
  local pid_file="$1"
  [ -f "$pid_file" ] || return 1

  local pid
  pid="$(<"$pid_file")"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

remove_stale_pid_file() {
  local pid_file="$1"
  if [ -f "$pid_file" ] && ! pid_is_running "$pid_file"; then
    rm -f "$pid_file"
  fi
}

create_local_test_user() {
  local email="$1"
  local response_file http_status
  response_file="$(mktemp "$STATE_DIR/auth-user.XXXXXX")"

  http_status="$(curl -sS -o "$response_file" -w '%{http_code}' \
    -X POST "$LOCAL_API_URL/auth/v1/admin/users" \
    -H "apikey: $LOCAL_SERVICE_ROLE_KEY" \
    -H "Authorization: Bearer $LOCAL_SERVICE_ROLE_KEY" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$email\",\"password\":\"localtest1234\",\"email_confirm\":true}")" || {
      rm -f "$response_file"
      fail "Could not create local test user: $email"
    }

  if [[ "$http_status" =~ ^20[01]$ ]]; then
    log "Created local test user: $email"
  elif [ "$http_status" = "422" ] && rg -qi 'already.*(registered|exists)' "$response_file"; then
    log "Local test user already exists: $email"
  else
    rm -f "$response_file"
    fail "Could not create local test user: $email (HTTP $http_status)"
  fi

  rm -f "$response_file"
}

ensure_local_test_accounts() {
  create_local_test_user 'owner@example.com'
  create_local_test_user 'teacher1@example.com'
  supabase db query --local --file "$ROOT_DIR/supabase/seeds/prod_profiles_seed.sql" >/dev/null
  log "Local owner and teacher profiles are ready."
}

start_functions() {
  remove_stale_pid_file "$FUNCTION_PID_FILE"

  if functions_ready; then
    log "Edge Functions are already running."
    return
  fi

  log "Starting Edge Functions..."
  (
    cd "$ROOT_DIR"
    nohup supabase functions serve \
      >"$FUNCTION_LOG_FILE" 2>&1 < /dev/null &
    printf '%s\n' "$!" > "$FUNCTION_PID_FILE"
  )
  STARTED_PIDS+=("$(<"$FUNCTION_PID_FILE")")
  wait_for_functions
  : > "$FUNCTION_OWNERSHIP_FILE"
}

start_web() {
  remove_stale_pid_file "$WEB_PID_FILE"

  if curl --connect-timeout 1 --max-time 2 -fsS -o /dev/null "$LOCAL_WEB_URL" 2>/dev/null; then
    log "Web server is already running at $LOCAL_WEB_URL."
    return
  fi

  log "Starting web server..."
  nohup npm --prefix "$ROOT_DIR/web" run dev -- --hostname 127.0.0.1 --port 3100 \
    >"$WEB_LOG_FILE" 2>&1 < /dev/null &
  printf '%s\n' "$!" > "$WEB_PID_FILE"
  STARTED_PIDS+=("$(<"$WEB_PID_FILE")")
  wait_for_http "$LOCAL_WEB_URL" "Web server"
}

cleanup_started_processes() {
  local pid
  for pid in "${STARTED_PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
}

start() {
  mkdir -p "$STATE_DIR"
  chmod 700 "$STATE_DIR"
  ensure_docker_runtime

  if ! is_local_supabase_running; then
    log "Starting local Supabase..."
    (cd "$ROOT_DIR" && supabase start)
  else
    log "Local Supabase is already running."
  fi

  read_local_supabase_env

  if [ "$RESET_DB" = true ]; then
    log "Resetting the local database and loading test fixtures..."
    (cd "$ROOT_DIR" && supabase db reset --local)
    read_local_supabase_env
  fi

  ensure_local_test_accounts
  trap cleanup_started_processes ERR
  start_functions
  start_web
  trap - ERR

  log ""
  log "Local test environment is ready:"
  log "  Web:    $LOCAL_WEB_URL"
  log "  Studio: http://127.0.0.1:54323"
  log "  Owner:  owner@example.com / localtest1234"
  log "  Teacher: teacher1@example.com / localtest1234"
  log ""
  log "Logs: $STATE_DIR"
}

stop_managed_process() {
  local pid_file="$1"
  local label="$2"

  if ! pid_is_running "$pid_file"; then
    rm -f "$pid_file"
    return
  fi

  local pid
  pid="$(<"$pid_file")"
  kill "$pid" 2>/dev/null || true
  rm -f "$pid_file"
  log "Stopped $label."
}

stop_managed_functions() {
  stop_managed_process "$FUNCTION_PID_FILE" "Edge Functions launcher"

  if [ -f "$FUNCTION_OWNERSHIP_FILE" ]; then
    local project_id edge_container
    project_id="$(sed -n -E 's/^project_id = "([^"]+)"/\1/p' "$ROOT_DIR/supabase/config.toml")"
    edge_container="supabase_edge_runtime_${project_id}"
    docker stop --time 2 "$edge_container" >/dev/null 2>&1 || true
    rm -f "$FUNCTION_OWNERSHIP_FILE"
    log "Stopped Edge Functions."
  fi
}

stop() {
  stop_managed_process "$WEB_PID_FILE" "web server"
  stop_managed_functions

  if [ "$STOP_SUPABASE" = true ]; then
    (cd "$ROOT_DIR" && supabase stop)
    log "Stopped local Supabase without deleting local volumes."
  fi
}

status() {
  mkdir -p "$STATE_DIR"
  if is_local_supabase_running; then
    log "Local Supabase: ready"
    read_local_supabase_env
  else
    log "Local Supabase: stopped"
    return 1
  fi

  if functions_ready; then
    log "Edge Functions: ready"
  else
    log "Edge Functions: stopped"
  fi

  if curl --connect-timeout 1 --max-time 2 -fsS -o /dev/null "$LOCAL_WEB_URL" 2>/dev/null; then
    log "Web server: ready ($LOCAL_WEB_URL)"
  else
    log "Web server: stopped"
  fi
}

main() {
  [ "$#" -ge 1 ] || {
    usage
    exit 1
  }

  local command="$1"
  shift

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --reset-db) RESET_DB=true ;;
      --stop-supabase) STOP_SUPABASE=true ;;
      -h|--help)
        usage
        exit 0
        ;;
      *) fail "Unknown option: $1" ;;
    esac
    shift
  done

  case "$command" in
    start) start ;;
    stop) stop ;;
    status) status ;;
    -h|--help|help) usage ;;
    *)
      usage
      fail "Unknown command: $command"
      ;;
  esac
}

main "$@"
