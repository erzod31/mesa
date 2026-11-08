param([switch]$ServerOnly)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$python = Join-Path $root '.venv/Scripts/python.exe'
$data = Join-Path $root 'data'
$logs = Join-Path $root 'output'
if (!(Test-Path -LiteralPath $python)) { throw 'Falta el entorno Python. Sigue README.md para preparar el servidor.' }
& (Join-Path $PSScriptRoot 'start_translation_worker.ps1')
New-Item -ItemType Directory -Force -Path $data,$logs | Out-Null
# Restrict credentials and server files to the current Windows user and SYSTEM.
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls.exe $data '/inheritance:r' '/grant:r' "${identity}:(OI)(CI)F" 'SYSTEM:(OI)(CI)F' | Out-Null
function MesaIsUp {
  try { $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -TimeoutSec 2; return $health.protocol -eq 1 -and $health.product -eq 'mesa' } catch { return $false }
}
if (!(MesaIsUp)) {
  if (Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue) { throw 'El puerto 8765 está ocupado por otro programa.' }
  $process = Start-Process -FilePath $python -ArgumentList '-m','server.app' -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logs 'server-out.log') -RedirectStandardError (Join-Path $logs 'server-error.log') -PassThru
  @{pid=$process.Id;started=$process.StartTime.ToUniversalTime().ToString('o')} | ConvertTo-Json | Set-Content (Join-Path $data 'server-process.json') -Encoding utf8
  for ($attempt = 0; $attempt -lt 40 -and !(MesaIsUp); $attempt++) { Start-Sleep -Milliseconds 250 }
  if (!(MesaIsUp)) { throw 'El servidor no pudo iniciar. Revisa output/server-error.log.' }
}
& (Join-Path $PSScriptRoot 'start_download_server.ps1')
if (!$ServerOnly) {
  $exe = Join-Path $root 'dist/Mesa-Windows/mesa.exe'
  if (!(Test-Path -LiteralPath $exe)) { $exe = Join-Path $root 'client/build/windows/x64/runner/Release/mesa.exe' }
  if (!(Test-Path -LiteralPath $exe)) { throw 'No se encuentra el ejecutable Windows. Compila la app como indica README.md.' }
  $connection = Join-Path $data 'desktop-connection.json'
  # This is the interactive recetario window; the server above remains hidden.
  Start-Process -FilePath $exe -ArgumentList "`"--connect-json=$connection`"" -WorkingDirectory (Split-Path $exe) -WindowStyle Normal | Out-Null
}
