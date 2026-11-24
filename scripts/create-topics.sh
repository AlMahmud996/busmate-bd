#!/usr/bin/env bash
# Creates the Kafka topics from diagram 11, plus a dead-letter topic for each.
# Safe to run again: existing topics are left alone.
set -euo pipefail
cd "$(dirname "$0")/.."

BOOTSTRAP="localhost:19092"
PARTITIONS=3
MAIN_RETENTION_MS=604800000    # 7 days
DLT_RETENTION_MS=1209600000    # 14 days

TOPICS=(
  payment.commands.v1
  payment.events.v1
  booking.events.v1
  trip.events.v1
  tracking.events.v1
)

create() {
  local name="$1" retention="$2"
  docker compose exec -T kafka /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server "$BOOTSTRAP" --create --if-not-exists \
    --topic "$name" --partitions "$PARTITIONS" --replication-factor 1 \
    --config "retention.ms=$retention"
}

for t in "${TOPICS[@]}"; do
  create "$t" "$MAIN_RETENTION_MS"
  create "$t.DLT" "$DLT_RETENTION_MS"
done

echo "Topics now:"
docker compose exec -T kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" --list
