param([switch]$AnalyzeOnly)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$taskFso=New-Object -ComObject Scripting.FileSystemObject
$taskShort=$taskFso.GetFolder($taskRoot).ShortPath
$taskJunction=$null
if ($taskShort.Contains(' ')) {
  $tempBase = [IO.Path]::GetTempPath().TrimEnd('\')
  if ($tempBase.Contains(' ')) { $tempBase = $taskFso.GetFolder($tempBase).ShortPath }
  if ($tempBase.Contains(' ')) { throw 'No hay una ruta temporal sin espacios para compilar.' }
  $taskJunction = Join-Path $tempBase ("mesa-build-" + $PID)
  if (Test-Path -LiteralPath $taskJunction) { & cmd.exe /c "rmdir `"$taskJunction`"" 2>$null }
  & cmd.exe /c "mklink /J `"$taskJunction`" `"$taskRoot`"" | Out-Null
  if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath (Join-Path $taskJunction '.tools'))) { throw 'No se pudo preparar una ruta sin espacios para compilar.' }
  $taskRoot=$taskJunction
  $taskShort=$taskJunction
}
$taskFlutter=Join-Path $taskShort '.tools/flutter/bin/flutter.bat'
Push-Location (Join-Path $taskRoot 'client')
try {
  & $taskFlutter analyze --no-pub
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  if (!$AnalyzeOnly) {
    & $taskFlutter test --no-pub --reporter expanded
    exit $LASTEXITCODE
  }
} finally {
  Pop-Location
  if ($taskJunction) { & cmd.exe /c "rmdir `"$taskJunction`"" 2>$null }
}
