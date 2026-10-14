#!/usr/bin/env bash
# Levanta la solución completa con las imágenes publicadas en Docker Hub (no compila nada).
set -euo pipefail

cd "$(dirname "$0")"

docker compose pull
docker compose up -d

echo ""
echo "Esperando a que los servicios respondan..."
for i in $(seq 1 60); do
  if curl -sf "http://localhost:${PORT_A:-3000}/payments" >/dev/null \
    && curl -sf "http://localhost:${PORT_B:-3001}/" >/dev/null \
    && curl -sf "http://localhost:${PORT_FRONTEND:-8080}/" >/dev/null; then
    echo ""
    echo "Listo. Abrir: http://localhost:${PORT_FRONTEND:-8080}"
    exit 0
  fi
  sleep 2
done

echo ""
echo "Los servicios no respondieron a tiempo. Revisa: docker compose logs"
exit 1
