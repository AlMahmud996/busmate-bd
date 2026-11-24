#!/usr/bin/env bash
# Creates .env from .env.example and replaces every change_me with a random value.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env ]; then
  echo ".env already exists, not overwriting it."
  exit 1
fi

while IFS= read -r line; do
  if [[ "$line" == *change_me* ]]; then
    line="${line//change_me/$(openssl rand -hex 16)}"
  fi
  printf '%s\n' "$line"
done < .env.example > .env

chmod 600 .env
echo "Created .env with random passwords."
