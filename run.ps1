$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

docker compose down
docker compose up -d --build

$portA = if ($env:PORT_A) { $env:PORT_A } else { "3000" }
$portB = if ($env:PORT_B) { $env:PORT_B } else { "3001" }
$portFront = if ($env:PORT_FRONTEND) { $env:PORT_FRONTEND } else { "8080" }

Write-Host ""
Write-Host "Esperando a que los servicios respondan..."
for ($i = 1; $i -le 45; $i++) {
  try {
    Invoke-WebRequest -Uri "http://localhost:$portA/" -UseBasicParsing -TimeoutSec 2 | Out-Null
    Invoke-WebRequest -Uri "http://localhost:$portB/" -UseBasicParsing -TimeoutSec 2 | Out-Null
    Invoke-WebRequest -Uri "http://localhost:$portFront/" -UseBasicParsing -TimeoutSec 2 | Out-Null
    break
  } catch {
    Start-Sleep -Seconds 2
  }
}

Write-Host ""
Write-Host "Abrir: http://localhost:$portFront"
