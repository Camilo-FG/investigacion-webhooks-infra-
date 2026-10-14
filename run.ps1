# Levanta la solucion completa con las imagenes publicadas en Docker Hub (no compila nada).
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

docker compose pull
if ($LASTEXITCODE -ne 0) { throw "docker compose pull fallo" }
docker compose up -d
if ($LASTEXITCODE -ne 0) { throw "docker compose up fallo" }

$portA = if ($env:PORT_A) { $env:PORT_A } else { "3000" }
$portB = if ($env:PORT_B) { $env:PORT_B } else { "3001" }
$portFront = if ($env:PORT_FRONTEND) { $env:PORT_FRONTEND } else { "8080" }

Write-Host ""
Write-Host "Esperando a que los servicios respondan..."
for ($i = 1; $i -le 60; $i++) {
  try {
    Invoke-WebRequest -Uri "http://localhost:$portA/payments" -UseBasicParsing -TimeoutSec 3 | Out-Null
    Invoke-WebRequest -Uri "http://localhost:$portB/" -UseBasicParsing -TimeoutSec 3 | Out-Null
    Invoke-WebRequest -Uri "http://localhost:$portFront/" -UseBasicParsing -TimeoutSec 3 | Out-Null
    Write-Host ""
    Write-Host "Listo. Abrir: http://localhost:$portFront"
    exit 0
  } catch {
    Start-Sleep -Seconds 2
  }
}

Write-Host ""
Write-Host "Los servicios no respondieron a tiempo. Revisa: docker compose logs"
exit 1
