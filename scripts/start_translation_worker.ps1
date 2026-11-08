$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$taskConfig=Join-Path $taskRoot '.tools/translation/translategemma.json'
if (!(Test-Path -LiteralPath $taskConfig)) { return }
try {
  $taskTags=Invoke-RestMethod 'http://127.0.0.1:11435/api/tags' -TimeoutSec 2
  if ($taskTags.models.name -contains 'translategemma:4b' -or $taskTags.models.name -contains 'translategemma:12b') { return }
  throw 'El puerto del traductor está ocupado por otro servicio.'
} catch {
  if (Get-NetTCPConnection -LocalPort 11435 -State Listen -ErrorAction SilentlyContinue) { Write-Warning 'El traductor configurado no está disponible en su puerto. Mesa conserva el motor básico.'; return }
}
$taskOllama=(Get-Command ollama -ErrorAction SilentlyContinue).Source
if (!$taskOllama) { Write-Warning 'Ollama no está instalado. Mesa usará el traductor básico.'; return }
$env:OLLAMA_HOST='127.0.0.1:11435'
$env:OLLAMA_MODELS=Join-Path $taskRoot '.tools/ollama-models'
$env:OLLAMA_CONTEXT_LENGTH='8192'
New-Item -ItemType Directory -Force -Path (Join-Path $taskRoot 'output') | Out-Null
$taskProcess=Start-Process -FilePath $taskOllama -ArgumentList 'serve' -WorkingDirectory $taskRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $taskRoot 'output/translation-worker-out.log') -RedirectStandardError (Join-Path $taskRoot 'output/translation-worker-error.log') -PassThru
@{pid=$taskProcess.Id;started=$taskProcess.StartTime.ToUniversalTime().ToString('o');host='127.0.0.1:11435'} | ConvertTo-Json | Set-Content (Join-Path $taskRoot 'output/translation-worker-process.json')
for($taskAttempt=0;$taskAttempt -lt 20;$taskAttempt++) {
  try { Invoke-RestMethod 'http://127.0.0.1:11435/api/tags' -TimeoutSec 1 | Out-Null; return } catch { Start-Sleep -Milliseconds 250 }
}
Write-Warning 'El traductor de calidad todavía no responde; se conserva el motor básico.'
