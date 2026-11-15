# Diagnóstico: arranca la app con distintas partes apagadas y dice con cuáles se cierra sola.
param([string]$Exe = "salida\Proyectapp\Proyectapp.exe")
$dir = Join-Path (Get-Location) "salida\diag"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$env:PROYECTAPP_PRUEBA = (Resolve-Path "pruebas\medios").Path
foreach ($variante in @("", "fotogramas", "miniaturas", "pistas", "sonido", "miniaturas,sonido", "fotogramas,pistas")) {
    $informe = Join-Path $dir ("informe-" + ($variante -replace ',', '_') + ".txt")
    Remove-Item $informe -ErrorAction SilentlyContinue
    $env:PROYECTAPP_INFORME = $informe
    $env:PROYECTAPP_SIN = $variante
    $p = Start-Process -FilePath $Exe -ArgumentList "--autoprueba" -PassThru
    $cerrada = $p.WaitForExit(28000)
    $n = if (Test-Path $informe) { (Get-Content $informe | Where-Object { $_ -like "OK*" }).Count } else { 0 }
    $ultima = if (Test-Path $informe) { (Get-Content $informe | Select-Object -Last 1) } else { "" }
    if ($cerrada) { Write-Host "VARIANTE sin[$variante]: SE CIERRA (código $($p.ExitCode)) tras $n OK · última: $ultima" }
    else { Write-Host "VARIANTE sin[$variante]: sigue viva a los 28 s con $n OK · última: $ultima"; Stop-Process -Id $p.Id -Force }
    Start-Sleep -Seconds 2
}
$env:PROYECTAPP_SIN = ""
