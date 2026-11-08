param([ValidateSet('4b','12b')][string]$Size='4b')
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$taskOllama=(Get-Command ollama -ErrorAction Stop).Source
$taskModels=Join-Path $taskRoot '.tools/ollama-models'
New-Item -ItemType Directory -Force -Path $taskModels | Out-Null
$taskConfig=Join-Path $taskRoot '.tools/translation/translategemma.json'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $taskConfig) | Out-Null
if (!(Test-Path -LiteralPath $taskConfig)) { '{}' | Set-Content -LiteralPath $taskConfig -Encoding utf8 }
& (Join-Path $PSScriptRoot 'start_translation_worker.ps1')
$env:OLLAMA_HOST='127.0.0.1:11435'
$env:OLLAMA_MODELS=$taskModels
& $taskOllama pull "translategemma:$Size"
if ($LASTEXITCODE -ne 0) { throw 'No se pudo descargar el modelo de traducción.' }
$taskManifest=Join-Path $taskModels "manifests/registry.ollama.ai/library/translategemma/$Size"
@{model="translategemma:$Size";manifest_sha256=(Get-FileHash -LiteralPath $taskManifest -Algorithm SHA256).Hash.ToLower();source="https://ollama.com/library/translategemma:$Size";original="https://huggingface.co/google/translategemma-$Size-it";license='Gemma Terms of Use';host='127.0.0.1:11435'} | ConvertTo-Json | Set-Content -LiteralPath $taskConfig -Encoding utf8
Write-Output 'TranslateGemma local instalado. Las recetas se traducen en este ordenador.'
