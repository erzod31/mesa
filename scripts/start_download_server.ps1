param([switch]$Restart)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$python = [IO.Path]::GetFullPath((Join-Path $root '.venv/Scripts/python.exe'))
$data = Join-Path $root 'data'
$logs = Join-Path $root 'output'
New-Item -ItemType Directory -Force -Path $data,$logs | Out-Null
if (!(Test-Path -LiteralPath $python)) { throw 'Falta el entorno Python de Mesa.' }
$basePython = & $python -c 'import sys; print(sys._base_executable)'
$absoluteScript = Join-Path $root 'scripts\serve_apk.py'
function DownloadsAreUp {
  try { $health = Invoke-RestMethod 'http://127.0.0.1:8768/health' -TimeoutSec 2; return $health.product -eq 'mesa-downloads' -and $health.version -eq 1 } catch { return $false }
}
$listeners = @(Get-NetTCPConnection -LocalPort 8768 -State Listen -ErrorAction SilentlyContinue)
if ($listeners.Count -gt 0) {
  $owners = @($listeners.OwningProcess | Select-Object -Unique)
  if ($owners.Count -ne 1) { throw 'El puerto de actualizaciones está ocupado por otro programa.' }
  $process = Get-Process -Id $owners[0] -ErrorAction Stop
  $details = Get-CimInstance Win32_Process -Filter "ProcessId = $($process.Id)"
  # A Windows venv can delegate to its base Python; require this project's absolute script too.
  $isHelper = $details.CommandLine -and $details.CommandLine.Contains($absoluteScript)
  if ($process.Path -notin @($python, $basePython) -or !$isHelper) { throw 'El puerto 8768 pertenece a otro programa. No se ha detenido.' }
  if ($Restart -or !(DownloadsAreUp)) {
    # Recheck process identity before stopping it to guard against PID reuse.
    $started = $process.StartTime.ToUniversalTime().Ticks
    $fresh = Get-Process -Id $process.Id -ErrorAction Stop
    if ($fresh.Path -ne $process.Path -or $fresh.StartTime.ToUniversalTime().Ticks -ne $started) { throw 'Ha cambiado el proceso de descargas. No se ha detenido.' }
    Stop-Process -Id $fresh.Id
    $fresh.WaitForExit()
  } else { return }
}
$process = Start-Process -FilePath $python -ArgumentList "`"$absoluteScript`"" -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logs 'download-server-out.log') -RedirectStandardError (Join-Path $logs 'download-server-error.log') -PassThru
@{pid=$process.Id;started=$process.StartTime.ToUniversalTime().ToString('o')} | ConvertTo-Json | Set-Content (Join-Path $data 'download-process.json') -Encoding utf8
for ($attempt = 0; $attempt -lt 40 -and !(DownloadsAreUp); $attempt++) { Start-Sleep -Milliseconds 250 }
if (!(DownloadsAreUp)) { throw 'No se pudo iniciar el servicio de actualizaciones. Revisa output/download-server-error.log.' }
Write-Output 'Servicio privado de actualizaciones de Mesa disponible.'
