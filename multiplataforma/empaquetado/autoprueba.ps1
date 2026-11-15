# Arranca la app publicada con los medios de prueba y comprueba su informe (Windows).
param([string]$Exe = "salida\Proyectapp\Proyectapp.exe")
$ErrorActionPreference = "Continue"
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$dir = Join-Path (Get-Location) "salida\prueba"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$informe = Join-Path $dir "informe.txt"
Remove-Item $informe -ErrorAction SilentlyContinue

function Capturar([string]$ruta) {
    try {
        $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
        $bmp.Save($ruta)
        $g.Dispose(); $bmp.Dispose()
    } catch { Write-Host "sin captura: $_" }
}

$env:PROYECTAPP_PRUEBA = (Resolve-Path "pruebas\medios").Path
$env:PROYECTAPP_INFORME = $informe
$p = Start-Process -FilePath $Exe -ArgumentList "--autoprueba" -PassThru

$hechas = @()
for ($i = 0; $i -lt 700; $i++) {
    if (Test-Path $informe) {
        $lineas = Get-Content $informe -ErrorAction SilentlyContinue
        foreach ($l in $lineas) {
            if ($l -like "CAPTURA *") {
                $n = $l.Substring(8)
                if ($hechas -notcontains $n) {
                    Start-Sleep -Milliseconds 700
                    Capturar (Join-Path $dir "captura-$n.png")
                    $hechas += $n
                }
            }
        }
        if ($lineas -match "FIN") { break }
    }
    if ($p.HasExited) { break }
    Start-Sleep -Milliseconds 300
}

$viva = -not $p.HasExited
if ($viva) { Stop-Process -Id $p.Id -Force }
Write-Host "----- informe -----"
if (Test-Path $informe) { Get-Content $informe } else { Write-Host "(sin informe)" }
if (-not $viva) {
    Write-Host "La app se cerró sola (código $($p.ExitCode))"
    Write-Host "----- registro de errores de Windows -----"
    try {
        Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = (Get-Date).AddMinutes(-10) } -ErrorAction Stop |
            Where-Object { $_.ProviderName -in 'Application Error', '.NET Runtime', 'Windows Error Reporting' } |
            Select-Object -First 4 | ForEach-Object { Write-Host "DIAG [$($_.ProviderName)]"; ($_.Message -split "`n" | Select-Object -First 30) | ForEach-Object { Write-Host "DIAG $_" } }
    } catch { Write-Host "DIAG sin registro: $_" }
    exit 1
}
$texto = if (Test-Path $informe) { Get-Content $informe -Raw } else { "" }
if ($texto -notmatch "FIN") { Write-Host "La autoprueba no terminó"; exit 1 }
if ($texto -match "(?m)^FALLO") { Write-Host "Hay comprobaciones fallidas"; exit 1 }
Write-Host "Autoprueba superada"
