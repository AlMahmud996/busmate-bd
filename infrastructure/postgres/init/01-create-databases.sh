#!/usr/bin/env bash
# Runs once, when the PostgreSQL data directory is empty.
# Creates one database and one login role per service, and keeps each
# service out of the other services' databases.
set -euo pipefail

create_db() {
  local db="$1" user="$2" password="$3"
  echo "Creating database $db with owner $user"
  psql -v ON_ERROR_STOP=1 -v db="$db" -v u="$user" -v p="$password" \
       --username "$POSTGRES_USER" --dbname postgres <<'EOSQL'
CREATE ROLE :"u" LOGIN PASSWORD :'p';
CREATE DATABASE :"db" OWNER :"u";
REVOKE ALL ON DATABASE :"db" FROM PUBLIC;
GRANT CONNECT ON DATABASE :"db" TO :"u";
EOSQL
}

create_db "$USER_DB_NAME"         "$USER_DB_USER"         "$USER_DB_PASSWORD"
create_db "$TRIP_DB_NAME"         "$TRIP_DB_USER"         "$TRIP_DB_PASSWORD"
create_db "$BOOKING_DB_NAME"      "$BOOKING_DB_USER"      "$BOOKING_DB_PASSWORD"
create_db "$PAYMENT_DB_NAME"      "$PAYMENT_DB_USER"      "$PAYMENT_DB_PASSWORD"
create_db "$TRACKING_DB_NAME"     "$TRACKING_DB_USER"     "$TRACKING_DB_PASSWORD"
create_db "$NOTIFICATION_DB_NAME" "$NOTIFICATION_DB_USER" "$NOTIFICATION_DB_PASSWORD"
