$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskMetadata = Join-Path $taskRoot 'client\.flutter-plugins-dependencies'
$taskLinks = Join-Path $taskRoot 'client\windows\flutter\ephemeral\.plugin_symlinks'
New-Item -ItemType Directory -Path $taskLinks -Force | Out-Null
$taskPlugins = (Get-Content -LiteralPath $taskMetadata -Raw | ConvertFrom-Json).plugins.windows
foreach ($taskPlugin in $taskPlugins) {
    $taskLink = Join-Path $taskLinks $taskPlugin.name
    if (-not (Test-Path -LiteralPath $taskLink)) {
        New-Item -ItemType Junction -Path $taskLink -Target $taskPlugin.path | Out-Null
    }
}
Write-Output 'Enlaces de compilación preparados dentro del proyecto.'
