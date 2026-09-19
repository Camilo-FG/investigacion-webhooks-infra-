# Investigación Webhooks — Infra (Persona 3)

Repos separados (no monorepo). Clona cada uno como carpeta hermana:

```text
INVESTIGACIONWEBHOOKS/
  servicio-a/     ← https://github.com/Keril-valle/servicio-a
  servicio-b/     ← https://github.com/Luz-Davila/servicio-b
  frontend/       ← https://github.com/Camilo-FG/investigacionwebhooksfrontend
  docker-compose.yml
  .env.example
  run.ps1 / run.sh
  README.md
```

Roles:

- `servicio-a` — dispara el webhook al crear un pedido
- `servicio-b` — recibe y verifica HMAC
- `frontend` — UI + Nginx reverse proxy

Copia `.env.example` a `.env` y ajusta `HMAC_SECRET` si hace falta (mismo valor para A y B).

## Arrancar todo

```bash
# Windows (PowerShell)
.\run.ps1

# Linux / macOS / Git Bash
chmod +x run.sh
./run.sh
```

Al terminar verás: **Abrir: http://localhost:8080**

## Variables (`.env`)

| Variable | Uso |
|---|---|
| `HMAC_SECRET` | Misma clave para A y B |
| `PORT_A` / `PORT_B` / `PORT_FRONTEND` | Puertos en el host |

La URL de suscripción (desde el frontend o curl) debe ser la **interna de Docker**:

`http://service-b:3001/webhooks/pedido`

## Probar sin frontend

```bash
# 1. Suscribir
curl -X POST http://localhost:3000/suscripciones \
  -H "Content-Type: application/json" \
  -d "{\"url\":\"http://service-b:3001/webhooks/pedido\",\"event\":\"pedido.creado\"}"

# 2. Crear pedido (trigger)
curl -X POST http://localhost:3000/pedidos \
  -H "Content-Type: application/json" \
  -d "{\"producto\":\"Café\",\"monto\":12.5}"

# 3. Ver eventos en B
curl http://localhost:3001/webhooks/recibidos
```

## Reproducibilidad

```bash
docker compose down -v
docker compose up -d --build
```
