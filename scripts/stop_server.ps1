$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$file = Join-Path $root 'data/server-process.json'
if (!(Test-Path -LiteralPath $file)) { throw 'No hay un servidor iniciado por Mesa en este proyecto.' }
$record = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
$process = Get-Process -Id $record.pid -ErrorAction SilentlyContinue
if ($process) {
  $expected = [IO.Path]::GetFullPath((Join-Path $root '.venv/Scripts/python.exe'))
  # PowerShell 7.5 may deserialize ISO timestamps as DateTime; PS 5 keeps strings.
  # Compare the exact UTC instant rather than locale-dependent string coercion.
  $recordedStart = ([datetime]$record.started).ToUniversalTime()
  if ($process.Path -ne $expected -or $process.StartTime.ToUniversalTime().Ticks -ne $recordedStart.Ticks) { throw 'El identificador pertenece a otro proceso. No se ha detenido.' }
  Stop-Process -Id $process.Id
  $process.WaitForExit()
}
Remove-Item -LiteralPath $file
Write-Output 'Servidor de Mesa detenido. Las recetas siguen guardadas.'
