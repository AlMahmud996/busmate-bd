#!/usr/bin/env bash
# Helper for the local BusMate infrastructure: PostgreSQL, Redis and Kafka.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  cat <<'USAGE'
Usage: scripts/infra.sh <command>

  up       start PostgreSQL, Redis and Kafka, wait until healthy, create the Kafka topics
  down     stop everything and keep the data
  status   show container health and memory use
  check    run the infrastructure checks (password, boundary, seat hold, topics, round trip)
  psql     open psql in a service database, for example: scripts/infra.sh psql user
  redis    open redis-cli with the password
  reset    delete ALL local data (asks first)
USAGE
}

load_env() {
  if [ ! -f .env ]; then
    echo "No .env file. Run scripts/make-env.sh first." >&2
    exit 1
  fi
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
}

failures=0
ok()  { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }

# expect "name" "regex" command...   passes when a line of the output matches the regex
expect() {
  local name="$1" pattern="$2" out
  shift 2
  out="$("$@" 2>&1 || true)"
  if printf '%s\n' "$out" | grep -Eq "$pattern"; then ok "$name"; else bad "$name"; fi
}

run_checks() {
  load_env
  local kt=/opt/kafka/bin/kafka-topics.sh kb=localhost:19092 topic_count tmp_topic

  echo "PostgreSQL"
  if command -v psql >/dev/null 2>&1; then
    expect "user_svc can open user_db" '^user_svc$' \
      env PGPASSWORD="$USER_DB_PASSWORD" psql -h 127.0.0.1 -p "$POSTGRES_HOST_PORT" \
      -U "$USER_DB_USER" -d "$USER_DB_NAME" -tA -c 'select current_user'
    expect "user_svc cannot open trip_db" 'permission denied for database' \
      env PGPASSWORD="$USER_DB_PASSWORD" psql -h 127.0.0.1 -p "$POSTGRES_HOST_PORT" \
      -U "$USER_DB_USER" -d "$TRIP_DB_NAME" -tA -c 'select 1'
  else
    echo "  skip  psql is not installed on this machine"
  fi

  echo "Redis"
  rc() { docker compose exec -T -e REDISCLI_AUTH="$REDIS_PASSWORD" redis redis-cli "$@"; }
  rc DEL hold:check:s1 >/dev/null 2>&1 || true
  expect "refuses commands without a password" 'NOAUTH' docker compose exec -T redis redis-cli ping
  expect "answers with the password" '^PONG$' rc ping
  expect "first hold on a seat succeeds" '^OK$' rc SET hold:check:s1 booking-A NX EX 15
  rc SET hold:check:s1 booking-B NX EX 15 >/dev/null 2>&1 || true
  expect "second hold does not take the seat" '^booking-A$' rc GET hold:check:s1
  rc DEL hold:check:s1 >/dev/null 2>&1 || true

  echo "Kafka"
  topic_count="$(docker compose exec -T kafka "$kt" --bootstrap-server "$kb" --list 2>/dev/null \
    | grep -Ec '^(payment|booking|trip|tracking)\.' || true)"
  if [ "$topic_count" = "10" ]; then ok "the 10 topics from diagram 11 exist"; else bad "expected 10 topics, found $topic_count"; fi
  tmp_topic="infra.check.$(date +%s)"
  docker compose exec -T kafka "$kt" --bootstrap-server "$kb" --create --topic "$tmp_topic" \
    --partitions 1 --replication-factor 1 >/dev/null 2>&1 || true
  printf 'k:hello-%s\n' "$$" | docker compose exec -T kafka /opt/kafka/bin/kafka-console-producer.sh \
    --bootstrap-server "$kb" --topic "$tmp_topic" \
    --property parse.key=true --property key.separator=: >/dev/null 2>&1 || true
  expect "a message sent to Kafka can be read back" "hello-$$" \
    docker compose exec -T kafka /opt/kafka/bin/kafka-console-consumer.sh \
    --bootstrap-server "$kb" --topic "$tmp_topic" --from-beginning --max-messages 1 --timeout-ms 15000
  docker compose exec -T kafka "$kt" --bootstrap-server "$kb" --delete --topic "$tmp_topic" >/dev/null 2>&1 || true

  echo
  if [ "$failures" -eq 0 ]; then
    echo "All checks passed."
  else
    echo "$failures check(s) failed."
    exit 1
  fi
}

cmd="${1:-}"
case "$cmd" in
  up)
    load_env
    docker compose up -d --wait --wait-timeout 240
    ./scripts/create-topics.sh
    ;;
  down)
    docker compose down
    ;;
  status)
    docker compose ps
    docker stats --no-stream busmate-postgres busmate-redis busmate-kafka || true
    ;;
  check)
    run_checks
    ;;
  psql)
    load_env
    case "${2:-}" in
      user|trip|booking|payment|tracking|notification)
        docker compose exec postgres psql -U "$POSTGRES_ADMIN_USER" -d "${2}_db"
        ;;
      *)
        echo "Name one of: user trip booking payment tracking notification" >&2
        exit 1
        ;;
    esac
    ;;
  redis)
    load_env
    docker compose exec -e REDISCLI_AUTH="$REDIS_PASSWORD" redis redis-cli
    ;;
  reset)
    read -r -p "This deletes ALL local data (databases, Kafka topics). Type RESET to continue: " answer
    if [ "$answer" = "RESET" ]; then
      docker compose down -v
    else
      echo "Cancelled."
    fi
    ;;
  *)
    usage
    exit 1
    ;;
esac
