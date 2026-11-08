param([ValidateRange(1,65535)][int]$Port = 9443)
$ErrorActionPreference = 'Stop'
$tailscale = Join-Path $env:ProgramFiles 'Tailscale/tailscale.exe'
if (!(Test-Path -LiteralPath $tailscale)) { throw 'Instala Tailscale desde https://tailscale.com/download/windows y conecta tu cuenta.' }
$statusText = & $tailscale status --json
if ($LASTEXITCODE -ne 0) { throw 'Abre Tailscale y conecta este ordenador antes de continuar.' }
$status = $statusText | ConvertFrom-Json
if ($status.BackendState -ne 'Running') { throw 'Tailscale todavía no está conectado.' }
$current = & $tailscale serve status --json
if ($LASTEXITCODE -ne 0) { throw 'No se pudo consultar Tailscale Serve.' }
$configuration = $current | ConvertFrom-Json
$dns = $status.Self.DNSName.TrimEnd('.')
$endpoint = "${dns}:$Port"
$existing = $null
if ($configuration.Web) { $existing = $configuration.Web.PSObject.Properties[$endpoint] }
if ($existing -and $existing.Value.Handlers.'/'.Proxy -ne 'http://127.0.0.1:8765') { throw "El puerto HTTPS $Port ya está asignado a otro servicio. Se conserva su configuración." }
if ($configuration.AllowFunnel -and $configuration.AllowFunnel.PSObject.Properties[$endpoint].Value -eq $true) { throw 'Este puerto tiene Funnel público activado. Elige otro puerto privado.' }
if (!$existing -and $configuration.TCP -and $configuration.TCP.PSObject.Properties["$Port"]) { throw "El puerto $Port ya está ocupado en Tailscale." }
if (!$existing) { & $tailscale serve --bg "--https=$Port" http://127.0.0.1:8765 }
if ($LASTEXITCODE -ne 0) { throw 'Tailscale Serve no pudo activarse. Revisa la configuración HTTPS de tu red.' }
# Publish only Mesa's read-only APK/feed helper on the same private endpoint.
$downloads = if ($existing) { $existing.Value.Handlers.PSObject.Properties['/descargar'] } else { $null }
if ($downloads -and $downloads.Value.Proxy -ne 'http://127.0.0.1:8768') { throw 'La ruta /descargar pertenece a otro servicio. Se conserva su configuración.' }
if (!$downloads) { & $tailscale serve --bg "--https=$Port" --set-path=/descargar http://127.0.0.1:8768 }
if ($LASTEXITCODE -ne 0) { throw 'No se pudo publicar la ruta privada de actualizaciones.' }
$root = Split-Path -Parent $PSScriptRoot
$publicUrl = "https://${dns}:$Port"
Set-Content -LiteralPath (Join-Path $root 'data/public-url.txt') -Value $publicUrl -Encoding utf8
$connectionFile = Join-Path $root 'data/desktop-connection.json'
if (Test-Path -LiteralPath $connectionFile) {
  $connection = Get-Content -LiteralPath $connectionFile -Raw | ConvertFrom-Json
  $connection | Add-Member -NotePropertyName public_url -NotePropertyValue $publicUrl -Force
  $connection | ConvertTo-Json | Set-Content -LiteralPath $connectionFile -Encoding utf8
}
Write-Output "Dirección privada de Mesa: $publicUrl"
Write-Output 'Usa la dirección HTTPS mostrada por Tailscale en Mi espacio > Invitar familiar. Serve es privado; no actives Funnel.'
