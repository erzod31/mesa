param([switch]$AnalyzeOnly)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$taskFso=New-Object -ComObject Scripting.FileSystemObject
$taskShort=$taskFso.GetFolder($taskRoot).ShortPath
if ($taskShort.Contains(' ')) { throw 'Se necesita la ruta corta del SDK.' }
$taskFlutter=Join-Path $taskShort '.tools/flutter/bin/flutter.bat'
Push-Location (Join-Path $taskRoot 'client')
try {
  & $taskFlutter analyze --no-pub
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  if (!$AnalyzeOnly) {
    & $taskFlutter test --no-pub --reporter expanded
    exit $LASTEXITCODE
  }
} finally { Pop-Location }
