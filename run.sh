#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

docker compose down
docker compose up -d --build

echo ""
echo "Esperando a que los servicios respondan..."
for i in $(seq 1 30); do
  if curl -sf "http://localhost:${PORT_A:-3000}/" >/dev/null \
    && curl -sf "http://localhost:${PORT_B:-3001}/" >/dev/null \
    && curl -sf "http://localhost:${PORT_FRONTEND:-8080}/" >/dev/null; then
    break
  fi
  sleep 1
done

echo ""
echo "Abrir: http://localhost:${PORT_FRONTEND:-8080}"
