param([switch]$AnalyzeOnly)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$taskFso=New-Object -ComObject Scripting.FileSystemObject
$taskShort=$taskFso.GetFolder($taskRoot).ShortPath
$taskJunction=$null
if ($taskShort.Contains(' ')) {
  $taskJunction = Join-Path ([IO.Path]::GetPathRoot($taskRoot)) 'mesa-build'
  if (!(Test-Path -LiteralPath (Join-Path $taskJunction '.tools'))) {
    if (Test-Path -LiteralPath $taskJunction) { & cmd.exe /c "rmdir `"$taskJunction`"" 2>$null }
    & cmd.exe /c "mklink /J `"$taskJunction`" `"$taskRoot`"" | Out-Null
    if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath (Join-Path $taskJunction '.tools'))) { throw 'No se pudo preparar una ruta sin espacios para compilar.' }
  }
  $taskRoot=$taskJunction
  $taskShort=$taskJunction
}
$taskFlutter=Join-Path $taskShort '.tools/flutter/bin/flutter.bat'
Push-Location (Join-Path $taskRoot 'client')
try {
  & $taskFlutter pub get 2>&1
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  & $taskFlutter analyze --no-pub 2>&1
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  if (!$AnalyzeOnly) {
    & $taskFlutter test --no-pub --reporter expanded 2>&1
    exit $LASTEXITCODE
  }
} finally { Pop-Location }
