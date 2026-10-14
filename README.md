# Webhooks: confirmación automática de pagos

Proyecto de **Paradigmas de Programación** · Investigación sobre webhooks.

Una tienda (Servicio A, Store / Merchant API) envía pagos a un proveedor de pagos simulado (Servicio B, Fake Payment Provider). El proveedor procesa el pago con una demora y **avisa el resultado a la tienda con un webhook firmado con HMAC-SHA256**. Los dos servicios son NestJS, los pedidos y pagos se guardan en PostgreSQL y todo corre con Docker Compose. Una segunda demo usa **ONVO**, un proveedor de pagos real en modo prueba, con el mismo modelo de webhook.

**Problema asignado:** confirmación automática de pagos. **Técnica:** webhooks (notificación *push* por HTTP, firmada con HMAC).

| Lo que pide la entrega | Dónde está |
|---|---|
| Problema asignado y técnica | [1. Tema seleccionado](#1-tema-seleccionado) |
| Arquitectura o diagrama | [2. Diagrama](#2-diagrama) |
| URL del ambiente desplegado | [3. Ambiente desplegado](#3-ambiente-desplegado) |
| Imágenes publicadas en Docker Hub | [4. Imágenes en Docker Hub](#4-imágenes-en-docker-hub) |
| Cómo ejecutar localmente | [5. Ejecución local](#5-ejecución-local) |
| Cómo ejecutar o simular el escenario y comprobar que funciona | [6. Cómo probar el escenario](#6-cómo-probar-el-escenario) |

## Contenido

1. [Tema seleccionado](#1-tema-seleccionado)
2. [Diagrama](#2-diagrama)
3. [Ambiente desplegado](#3-ambiente-desplegado)
4. [Imágenes en Docker Hub](#4-imágenes-en-docker-hub)
5. [Ejecución local](#5-ejecución-local)
6. [Cómo probar el escenario](#6-cómo-probar-el-escenario)
7. [Explicación del flujo de comunicación](#7-explicación-del-flujo-de-comunicación)
8. [Repositorios y estructura](#8-repositorios-y-estructura)

---

## 1. Tema seleccionado

**Webhooks.** Un webhook es una petición HTTP (normalmente un `POST`) que un sistema envía por su cuenta a una URL que otro sistema registró de antemano, en el momento en que ocurre un evento. Es un modelo *push*: quien tiene la información avisa, en vez de esperar a que le pregunten.

Se contrasta con el *polling* (modelo *pull*), en el que el interesado consulta cada cierto tiempo si hay novedades. Sin webhook, la tienda tendría que preguntarle al proveedor cada pocos segundos "¿ya se aprobó el pago?".

**Escenario implementado.** Un cliente compra un producto. La tienda crea el pedido y su pago en estado `PENDING` y se lo envía al proveedor. El proveedor responde de inmediato "recibido" (`PROCESSING`), procesa el pago durante unos segundos y, cuando decide el resultado, envía un webhook a la tienda. La tienda verifica la firma y actualiza el pago y el pedido. Es el mismo modelo que usan Stripe u Onvo.

## 2. Diagrama

**Vista mínima del recorrido:**

```mermaid
flowchart LR
    C["Cliente<br/>compra"] --> A1["Servicio A (tienda)<br/>pedido + pago PENDING"]
    A1 -->|POST /payments| B1["Servicio B (proveedor)<br/>responde PROCESSING"]
    B1 --> P["Procesa unos segundos<br/>decide el resultado"]
    P -->|"Webhook POST /webhooks/payments<br/>header X-Signature"| A2["Servicio A<br/>verifica la firma HMAC"]
    A2 -->|coincide| OK["Actualiza pago y pedido<br/>responde 200"]
    A2 -->|no coincide| NO["Rechaza (401)<br/>no cambia nada"]
```

**Secuencia completa:**

```mermaid
sequenceDiagram
    autonumber
    actor U as Cliente
    participant A as Servicio A - Tienda (:3000)
    participant DB as PostgreSQL
    participant B as Servicio B - Proveedor (:3001)

    Note over B: Al arrancar registra la URL de la tienda<br/>(suscripción a payment.updated)
    U->>A: POST /payments { product, amount, provider }
    A->>DB: pedido PENDING_PAYMENT + pago PENDING
    A->>B: POST /payments { paymentId, amount }
    B-->>A: PROCESSING (respuesta inmediata)
    A-->>U: 201 con el pago en PENDING
    Note over B: Procesa con demora simulada
    opt Monto >= DEFERRED_THRESHOLD
        B->>A: Webhook payment.updated DEFERRED
        A->>DB: pago DEFERRED (el pedido sigue pendiente)
        Note over B: Procesa otra vez
    end
    Note over B: Decide APPROVED o REJECTED<br/>firma HMAC-SHA256(body, HMAC_SECRET)
    B->>A: Webhook POST /webhooks/payments + X-Signature
    Note over A: Recalcula el HMAC y compara con timingSafeEqual
    alt La firma coincide
        A->>DB: pago APPROVED / REJECTED<br/>pedido PAID / PAYMENT_REJECTED
        A-->>B: 200 (también si el webhook es repetido)
    else Firma inválida o ausente
        A-->>B: 401 Unauthorized
    end
```

## 3. Ambiente desplegado

| Componente | URL | Dónde corre |
|---|---|---|
| **Aplicación (abrir esta)** | https://stellular-speculoos-35e0b8.netlify.app | Netlify (frontend estático + proxy `/api/a` y `/api/b`) |
| Servicio A (tienda) | https://servicio-a-production.up.railway.app | Railway (contenedor) |
| Servicio B (proveedor) | https://servicio-b-production.up.railway.app | Railway (contenedor) |
| Base de datos | PostgreSQL administrado | Supabase |

```mermaid
flowchart LR
    U["Navegador"] --> N["Netlify<br/>frontend + proxy"]
    N -->|/api/a| A["Railway<br/>Servicio A"]
    N -->|/api/b| B["Railway<br/>Servicio B"]
    A --> DB[("Supabase<br/>PostgreSQL")]
    A -->|POST /payments| B
    B -->|"webhook firmado<br/>/webhooks/payments"| A
    O["ONVO (modo prueba)"] -->|"webhook<br/>/webhooks/onvo"| A
```

En el ambiente desplegado el proveedor B avisa a la URL pública de la tienda (`https://servicio-a-production.up.railway.app/webhooks/payments`, configurada con `DEFAULT_WEBHOOK_URL` en Railway), y ONVO avisa a `https://servicio-a-production.up.railway.app/webhooks/onvo`, registrada en su Dashboard.

## 4. Imágenes en Docker Hub

| Servicio | Imagen |
|---|---|
| Servicio A (tienda) | [`camilitofge/webhooks-servicio-a:latest`](https://hub.docker.com/r/camilitofge/webhooks-servicio-a) |
| Servicio B (proveedor) | [`camilitofge/webhooks-servicio-b:latest`](https://hub.docker.com/r/camilitofge/webhooks-servicio-b) |
| Frontend (React + Nginx) | [`camilitofge/webhooks-frontend:latest`](https://hub.docker.com/r/camilitofge/webhooks-frontend) |

`docker-compose.yml` usa estas imágenes directamente, más `postgres:16-alpine` para la base de datos local. Las imágenes no contienen secretos: todas las claves llegan por variables de entorno.

Para publicar una versión nueva hacen falta los tres repos de los servicios clonados dentro de esta carpeta y `docker login` con la cuenta `camilitofge`:

```bash
docker compose -f docker-compose.yml -f docker-compose.build.yml build
docker compose -f docker-compose.yml -f docker-compose.build.yml push service-a service-b frontend
```

## 5. Ejecución local

**Requisitos:** Git y Docker con Compose v2 (Docker Desktop lo incluye). No hace falta Node, ni clonar los repos de los servicios, ni crear un `.env`.

```bash
git clone https://github.com/Camilo-FG/investigacion-webhooks-infra-.git investigacion-webhooks
cd investigacion-webhooks

./run.sh          # macOS / Linux
# .\run.ps1       # Windows (PowerShell)
```

El script ejecuta `docker compose pull` y `docker compose up -d`, espera a que los servicios respondan e imprime **`Listo. Abrir: http://localhost:8080`**. También se puede hacer a mano con esos dos comandos.

Se levantan cuatro contenedores: la base de datos (`webhooks-db`), la tienda (`service-a`), el proveedor (`service-b`) y el frontend. La base de datos es un PostgreSQL local que crea sus tablas al arrancar por primera vez con las migraciones de `db/init/` (copiadas de `servicio-a/supabase/migrations/`). La primera ejecución puede tardar unos minutos mientras se descargan las imágenes e inicializa la base.

**`.env` opcional.** Sin `.env` se usan valores de demostración: `HMAC_SECRET` local y la base de datos del contenedor. Para cambiarlos, copiar `.env.example` como `.env`. Si `DATABASE_URL` apunta a Supabase, se usa esa base en lugar de la local; las claves de ONVO solo hacen falta para su demo.

### Puertos y variables

| Recurso | Valor | Para qué |
|---|---|---|
| `http://localhost:8080` | Frontend (Nginx) | Interfaz de la demo |
| `http://localhost:3000` | Servicio A (tienda) | Expuesto para probar con `curl` |
| `http://localhost:3001` | Servicio B (proveedor) | Expuesto para probar con `curl` |
| `HMAC_SECRET` | Clave compartida (por defecto, una de demostración) | **Debe ser idéntica** en A y B, o la firma nunca verifica |
| `DATABASE_URL` | Por defecto, el PostgreSQL local (`db`) | Pedidos y pagos de la tienda |
| `PROCESSING_DELAY_MS` | `3000` | Demora simulada del proveedor |
| `DEFERRED_THRESHOLD` | `50000` | Desde este monto el pago pasa primero por `DEFERRED` |
| `PORT_A`, `PORT_B`, `PORT_FRONTEND` | Puertos del host | Opcionales |

Dentro de la red de Docker los servicios se ven por su nombre (`http://service-a:3000`, `http://service-b:3001`), **no** por `localhost`. Por eso la URL de webhook que el proveedor registra para la tienda es `http://service-a:3000/webhooks/payments` (Compose la configura con `DEFAULT_WEBHOOK_URL`).

### Detener y reproducir desde cero

```bash
docker compose down        # detiene los contenedores
docker compose down -v     # además borra la base de datos local (se vuelve a crear al levantar)
```

### Desarrollo con el código fuente

Para modificar los servicios se clonan sus repos **dentro** de esta carpeta (están en `.gitignore`):

```bash
git clone https://github.com/Keril-valle/servicio-a.git
git clone https://github.com/Luz-Davila/servicio-b.git
git clone https://github.com/Camilo-FG/investigacionwebhooksfrontend.git
```

Con Docker, `docker compose -f docker-compose.yml -f docker-compose.build.yml up -d --build` compila las imágenes desde ese código en lugar de descargarlas.

Sin Docker, con Node 20 o superior y sin reconstruir contenedores (cada servicio se recarga solo al guardar):

```powershell
powershell -ExecutionPolicy Bypass -File .\run-local.ps1
```

El script apaga los contenedores si están arriba (usan los mismos puertos), instala dependencias si faltan y abre una ventana por servicio: A en `:3000`, B en `:3001` y el frontend en `:8080`.

Usa **el `.env` de la carpeta raíz** (copia de `.env.example`): A y B lo leen al arrancar. Ya trae `SERVICE_B_URL` y `DEFAULT_WEBHOOK_URL` apuntando a `localhost`; Docker las ignora porque `docker-compose.yml` define las suyas con los nombres `service-a` y `service-b`. En este modo hay que completar `HMAC_SECRET` y `DATABASE_URL` (por ejemplo, la de Supabase), porque la base local solo es accesible dentro de Docker.

Para hacerlo a mano (por ejemplo en Mac o Linux): `npm install` y `npm run start:dev` en `servicio-a` y `servicio-b`, y `npm install` y `npm run dev` en `investigacionwebhooksfrontend`.

Si se corre un servicio solo, sin la carpeta de infraestructura, cada uno tiene su propio `.env.example` para copiar como `.env`. Si existen los dos archivos, manda el de la raíz, y una variable definida en el sistema (como las de Docker) siempre gana sobre cualquier archivo.

## 6. Cómo probar el escenario

Todo lo de esta sección funciona igual en local (`http://localhost:8080`, o `localhost:3000` y `:3001` con `curl`) y en el [ambiente desplegado](#3-ambiente-desplegado) (la URL de Netlify, o las de Railway con `curl`).

### Reglas del proveedor simulado

| Monto | Webhooks que envía B | Estado final del pago | Estado final del pedido |
|---|---|---|---|
| Parte entera par (ej. `15000`) | `APPROVED` | `APPROVED` | `PAID` |
| Parte entera impar (ej. `15001`) | `REJECTED` | `REJECTED` | `PAYMENT_REJECTED` |
| `>= 50000` (ej. `60000`) | `DEFERRED` y luego el resultado final | `APPROVED` o `REJECTED` | `PAID` o `PAYMENT_REJECTED` |

### Opción A: desde la interfaz

Abre `http://localhost:8080`, ingresa un monto y procesa el pago con el proveedor `FAKE`. El pago aparece en `PENDING` y, unos segundos después, cambia solo a `APPROVED` o `REJECTED`: ese cambio lo provoca el webhook.

La interfaz muestra la evidencia de cada lado:

| Dónde | Qué muestra | Responde a |
|---|---|---|
| Clic en un pedido | Línea de tiempo del pago: creado, recibido por el proveedor, cada webhook enviado y qué hizo la tienda con él, con hora y milisegundos | Flujo asíncrono completo |
| Clic en un webhook enviado | Petición exacta: URL, cabeceras (`X-Signature`), cuerpo firmado, respuesta de la tienda e intentos | Qué se transmite |
| Webhooks recibidos por la tienda | Todo lo que llegó a A: aplicado, repetido, firma inválida o tienda caída | Quién procesa |
| Botón Reenviar | Manda otra vez los mismos bytes con la misma firma; la tienda responde `200` con `applied: false` | Idempotencia |
| Simular tienda caída | El endpoint de webhooks de A responde `503`; B reintenta 3 veces y marca la entrega como fallida | Reintentos y recuperación |

**Guion para mostrar fallos y recuperación:** enciende *Simular tienda caída*, compra con `15000` y espera: la entrega aparece como *Falló* tras 3 intentos y el pedido sigue esperando. Apaga la simulación, abre esa entrega y pulsa *Reenviar*: la tienda la aplica y el pedido queda pagado. Pulsa *Reenviar* otra vez: `200`, sin cambios.

### Opción B: con `curl`

En PowerShell usa `curl.exe` en lugar de `curl`.

**1. Ver la URL de webhook registrada en el proveedor:**

```bash
curl http://localhost:3001/suscripciones
```

**2. Comprar (crea el pedido y el pago en `PENDING`):**

```bash
curl -X POST http://localhost:3000/payments \
  -H "Content-Type: application/json" \
  -d '{"product":"Producto A","amount":15000,"provider":"FAKE"}'
```

**3. Ver el resultado unos segundos después** (la evidencia de que el webhook llegó):

```bash
curl http://localhost:3000/payments        # status: APPROVED
curl http://localhost:3000/pedidos         # status: PAID
curl http://localhost:3001/webhooks/entregas   # cada webhook enviado: petición exacta, respuesta e intentos
curl http://localhost:3000/webhooks/recibidos  # cada webhook que llegó a la tienda y qué hizo con él
curl http://localhost:3001/payments            # lo que sabe el proveedor de cada cobro
docker compose logs service-b              # "Webhook payment.updated (APPROVED) entregado a ..."
```

**4. Probar la verificación de la firma:**

```bash
# a) Firma inventada -> 401
curl -i -X POST http://localhost:3000/webhooks/payments \
  -H "Content-Type: application/json" -H "X-Signature: firma-falsa" \
  -d '{"event":"payment.updated","paymentId":"d81f874c-c790-4e4b-bf48-e0d839fa6f4a","status":"APPROVED"}'

# b) Misma petición firmada con la clave compartida (usa un paymentId real del paso 2) -> 200
#    Sin .env (o con HMAC_SECRET vacía) es la de demostración: secreto-local-de-la-demo
SECRET=$(grep '^HMAC_SECRET=' .env 2>/dev/null | cut -d= -f2)
SECRET=${SECRET:-secreto-local-de-la-demo}
BODY='{"event":"payment.updated","paymentId":"<paymentId>","status":"APPROVED"}'
SIG=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $NF}')
curl -i -X POST http://localhost:3000/webhooks/payments \
  -H "Content-Type: application/json" -H "X-Signature: $SIG" -d "$BODY"
```

Si se repite (b), la tienda responde `200` con `applied: false`: el webhook ya estaba procesado y no se vuelve a aplicar (**idempotencia**).

**5. Ver qué pasa si la tienda está caída** (la principal desventaja de los webhooks):

```bash
curl -X PUT http://localhost:3000/webhooks/simulacion -H "Content-Type: application/json" \
  -d '{"storeDown":true}'                      # el endpoint de webhooks responde 503
curl -X POST http://localhost:3000/payments -H "Content-Type: application/json" \
  -d '{"amount":15000,"provider":"FAKE"}'
curl http://localhost:3001/webhooks/entregas   # result: FAILED, attempts: 3
curl http://localhost:3000/payments            # el pago se quedó en PENDING

curl -X PUT http://localhost:3000/webhooks/simulacion -H "Content-Type: application/json" \
  -d '{"storeDown":false}'
curl -X POST http://localhost:3001/webhooks/entregas/<id-de-la-entrega>/reenviar   # applied: true
curl -X POST http://localhost:3001/webhooks/entregas/<id-de-la-entrega>/reenviar   # applied: false
```

B hace tres intentos (esperando 0,5 s y 1 s entre ellos) y se rinde. El webhook perdido no se reenvía solo: hay que reenviarlo a mano, y como la tienda es idempotente, reenviarlo de más no hace daño.

### Demo 2: ONVO, un proveedor real (ambiente desplegado)

En la URL de Netlify, elegir **ONVO** como proveedor al pagar. La tienda crea un Payment Intent en ONVO y abre su formulario de tarjeta (modo prueba, no se cobra dinero):

- Tarjeta aprobada: `4242 4242 4242 4242`, fecha futura y cualquier CVV.
- Tarjeta rechazada: `4000 0000 0000 0002`.

El navegador **no** le dice a la tienda que el pago se aprobó: ONVO envía el webhook `payment-intent.succeeded` (o `failed`) a `/webhooks/onvo`, la tienda valida el header `X-Webhook-Secret`, confirma el estado consultando el Payment Intent a ONVO y actualiza el pago. La llegada del webhook se ve en "Webhooks recibidos por la tienda".

Esta demo necesita una URL pública, así que solo funciona en el ambiente desplegado: desde `localhost` ONVO no tiene cómo avisar.

## 7. Explicación del flujo de comunicación

Todo empieza con una **suscripción**: el proveedor (Servicio B) guarda a qué URL debe avisar y para qué evento (`payment.updated`). En la demo, Compose registra la URL de la tienda al arrancar, igual que en Stripe u Onvo se registra la URL de webhook en su panel. También se puede registrar con `POST /suscripciones`.

Cuando el cliente compra, la tienda (Servicio A) crea en una sola transacción el **pedido** (`PENDING_PAYMENT`) y su **pago** (`PENDING`) en PostgreSQL, y le envía al proveedor `POST /payments` con el `paymentId` y el monto. El proveedor responde de inmediato `PROCESSING`: esa respuesta **no** aprueba nada, solo confirma que recibió la solicitud.

Luego el proveedor procesa el pago con una demora simulada y decide el resultado. Arma el payload (`event`, `paymentId`, `externalPaymentId`, `status`), calcula su firma HMAC-SHA256 con la clave compartida y lo envía por `POST` a cada URL suscrita, con la firma en el header `X-Signature`. Si el envío falla, lo intenta hasta tres veces (con esperas de 500 ms y 1 s) y deja registrada cada entrega en `GET /webhooks/entregas`, con los bytes exactos, las cabeceras, la respuesta de la tienda y cada intento. Una entrega se puede reenviar con `POST /webhooks/entregas/:id/reenviar`.

La tienda recibe el webhook en `/webhooks/payments`. Como ese endpoint es público, su seguridad depende de la firma: recalcula el HMAC sobre los bytes exactos que recibió y lo compara con `crypto.timingSafeEqual`. Si no coincide responde `401`. Si coincide, actualiza el pago **solo si está en un estado anterior permitido** (`PENDING` o `DEFERRED`) y, en la misma transacción, cierra el pedido (`PAID` o `PAYMENT_REJECTED`). Un webhook repetido o atrasado se responde con `200` sin cambiar nada, para que el proveedor no siga reintentando. Cada petición que llega, aceptada o rechazada, queda en `GET /webhooks/recibidos`.

## 8. Repositorios y estructura

| Repositorio | Contenido |
|---|---|
| [servicio-a](https://github.com/Keril-valle/servicio-a) | Tienda: pedidos, pagos en PostgreSQL y receptor del webhook (verificación HMAC, idempotencia) |
| [servicio-b](https://github.com/Luz-Davila/servicio-b) | Proveedor simulado: procesa pagos, suscripciones y envío del webhook firmado con reintentos |
| [investigacion-webhooks-infra-](https://github.com/Camilo-FG/investigacion-webhooks-infra-) | Ejecución local con las imágenes de Docker Hub: `docker-compose.yml`, scripts, migraciones de la base local |
| [investigacionwebhooksfrontend](https://github.com/Camilo-FG/investigacionwebhooksfrontend) | Interfaz React + Nginx con proxy hacia A y B; `netlify.toml` para el despliegue |

```text
investigacion-webhooks/            <- repo de infraestructura (el único que hace falta para ejecutar)
├── docker-compose.yml             <- imágenes de Docker Hub + PostgreSQL local
├── docker-compose.build.yml       <- solo para compilar y publicar imágenes
├── db/init/                       <- migraciones que crean las tablas de la base local
├── .env.example  ->  .env         <- opcional
├── run.sh / run.ps1               <- docker compose pull + up -d
├── run-local.ps1                  <- desarrollo sin Docker
├── servicio-a/                    <- solo para desarrollo: clonado dentro (ignorado por el repo de infra)
├── servicio-b/
└── investigacionwebhooksfrontend/
```

**Tecnologías:** NestJS 11 (A y B), PostgreSQL (local en Docker o Supabase en el despliegue), React 18 + Vite (frontend), Nginx (servidor estático y proxy), Docker Compose, Docker Hub, Railway y Netlify, módulo `crypto` de Node para HMAC-SHA256, ONVO (proveedor real en modo prueba).

**Limitaciones conocidas.** Por ser un ejemplo académico, el proveedor guarda suscripciones, cobros y entregas en memoria (igual que la tienda su registro de webhooks recibidos), sus reintentos duran pocos segundos, el reenvío de un webhook fallido es manual y la firma no incluye un timestamp, así que no protege contra ataques de repetición. La segunda demo con Onvo reemplaza al proveedor simulado por uno real.
