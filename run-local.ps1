# Levanta los tres proyectos SIN Docker, en modo desarrollo (se recargan solos al guardar).
# Cada uno se abre en su propia ventana de PowerShell; al cerrarla se detiene ese servicio.
# Requiere Node.js 20+ y el archivo .env de esta carpeta (copia de .env.example), que leen A y B.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$projects = @(
  @{ Name = "Servicio A (tienda) :3000";     Dir = "servicio-a";                    Cmd = "npm run start:dev" },
  @{ Name = "Servicio B (proveedor) :3001";  Dir = "servicio-b";                    Cmd = "npm run start:dev" },
  @{ Name = "Frontend :8080";                Dir = "investigacionwebhooksfrontend"; Cmd = "npm run dev" }
)

foreach ($p in $projects) {
  if (-not (Test-Path (Join-Path $p.Dir "package.json"))) {
    Write-Host "No se encontro la carpeta '$($p.Dir)'. Clona los repos dentro de esta carpeta." -ForegroundColor Red
    exit 1
  }
}
# Basta el .env de esta carpeta (lo leen A y B); si no existe, cada servicio necesita el suyo.
$hasSharedEnv = Test-Path ".env"
$hasServiceEnvs = (Test-Path "servicio-a\.env") -and (Test-Path "servicio-b\.env")
if (-not $hasSharedEnv -and -not $hasServiceEnvs) {
  Write-Host "Falta el archivo .env: copia .env.example como .env y completa HMAC_SECRET y DATABASE_URL." -ForegroundColor Red
  exit 1
}

# Los puertos son los mismos que usa Docker; si los contenedores estan arriba, se apagan.
if (Get-Command docker -ErrorAction SilentlyContinue) {
  $running = docker compose ps -q 2>$null
  if ($running) {
    Write-Host "Apagando los contenedores de Docker para liberar los puertos..."
    docker compose down | Out-Null
  }
}

# Docker tarda unos segundos en soltar los puertos; si Vite encuentra el 8080 ocupado, se pasa a otro.
for ($i = 1; $i -le 15; $i++) {
  $busy = netstat -ano | Select-String -Pattern ':(3000|3001|8080)\s.*LISTENING'
  if (-not $busy) { break }
  Start-Sleep -Seconds 1
}

foreach ($p in $projects) {
  $dir = Join-Path $PSScriptRoot $p.Dir
  if (-not (Test-Path (Join-Path $dir "node_modules"))) {
    Write-Host "Instalando dependencias de $($p.Dir)..."
    Push-Location $dir
    npm install
    Pop-Location
  }
  $script = "`$Host.UI.RawUI.WindowTitle = '$($p.Name)'; Set-Location '$dir'; $($p.Cmd)"
  Start-Process powershell -ArgumentList "-NoExit", "-Command", $script
}

Write-Host ""
Write-Host "Esperando a que los servicios respondan..."
for ($i = 1; $i -le 60; $i++) {
  try {
    Invoke-WebRequest -Uri "http://localhost:3000/" -UseBasicParsing -TimeoutSec 2 | Out-Null
    Invoke-WebRequest -Uri "http://localhost:3001/" -UseBasicParsing -TimeoutSec 2 | Out-Null
    Invoke-WebRequest -Uri "http://localhost:8080/" -UseBasicParsing -TimeoutSec 2 | Out-Null
    Write-Host "Listo. Abrir: http://localhost:8080" -ForegroundColor Green
    exit 0
  } catch {
    Start-Sleep -Seconds 2
  }
}
Write-Host "Algun servicio no respondio; revisa las ventanas que se abrieron." -ForegroundColor Yellow
