#!/usr/bin/env bash
# Pull latest images / rebuild and restart the full production stack.
# Run on the VPS from aifa-infra/scripts/
set -euo pipefail

cd "$(dirname "$0")/../compose"
COMPOSE="docker compose -f docker-compose.prod.yml"

if [[ ! -f .env ]]; then
  echo "Missing compose/.env — copy from ../.env.example and fill secrets." >&2
  exit 1
fi

echo "Building and starting AIFA stack ..."
$COMPOSE build
$COMPOSE up -d
$COMPOSE ps

echo "Deploy complete."
echo "  Site:     curl -sI https://aifascentique.shop"
echo "  Health:   curl -s https://aifascentique.shop/health"
