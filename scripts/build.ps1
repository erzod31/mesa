param([ValidateSet('windows','android','both')][string]$Target='both', [switch]$SkipPublish)
$ErrorActionPreference = 'Stop'
function Invoke-Native {
  param([scriptblock]$Command)
  # PowerShell 5.1 convierte stderr de programas nativos en errores que con
  # Stop terminarian el script (PyInstaller, MSBuild, Flutter escriben avisos
  # a stderr). Se ejecutan con Continue y se muestran como texto; el codigo de
  # salida sigue revisandose en cada llamada.
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { & $Command 2>&1 | ForEach-Object { Write-Output "$_" } } finally { $ErrorActionPreference = $previous }
}
$root = Split-Path -Parent $PSScriptRoot
# An Android-only delivery must still have the matching Windows installer.
if ($Target -eq 'android') {
  $releaseLine = Get-Content (Join-Path $root 'client/pubspec.yaml') | Where-Object { $_ -match '^version:' } | Select-Object -First 1
  $releaseVersion = ($releaseLine -replace '^version:\s*','').Trim()
  $windowsManifest = Join-Path $root 'dist/windows-installer.json'
  if (!(Test-Path -LiteralPath $windowsManifest)) {
    throw 'Toda entrega necesita instalador Windows. Ejecuta primero build.ps1 -Target windows o -Target both.'
  }
  $windowsRelease = Get-Content -Raw -LiteralPath $windowsManifest | ConvertFrom-Json
  if ($windowsRelease.appVersion -ne $releaseVersion -or !(Test-Path -LiteralPath $windowsRelease.installer) -or (Get-FileHash -Algorithm SHA256 -LiteralPath $windowsRelease.installer).Hash.ToLowerInvariant() -ne $windowsRelease.sha256) {
    throw 'El instalador Windows no coincide con esta entrega. Ejecuta build.ps1 -Target windows o -Target both.'
  }
}
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class MesaBuildPaths {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)]
  public static extern uint GetShortPathName(string path, StringBuilder result, uint length);
}
'@
$buffer = New-Object System.Text.StringBuilder 32768
[void][MesaBuildPaths]::GetShortPathName($root,$buffer,32768)
$short = $buffer.ToString()
$buildJunction = $null
if (!$short -or $short.Contains(' ')) {
  # Sin nombres cortos 8.3 (volumen con 8dot3 desactivado): compilar a traves
  # de un junction estable sin espacios. Se conserva entre ejecuciones para que
  # los caches de Dart (.dart_tool) sigan siendo validos. Vive en la raiz del
  # volumen (no en TEMP): MSBuild rechaza compilar dentro del directorio temporal.
  $buildJunction = Join-Path ([IO.Path]::GetPathRoot($root)) 'mesa-build'
  if (!(Test-Path -LiteralPath (Join-Path $buildJunction '.tools/flutter/bin/flutter.bat'))) {
    if (Test-Path -LiteralPath $buildJunction) { & cmd.exe /c "rmdir `"$buildJunction`"" 2>$null }
    & cmd.exe /c "mklink /J `"$buildJunction`" `"$root`"" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath (Join-Path $buildJunction '.tools/flutter/bin/flutter.bat'))) {
      throw 'No se pudo preparar una ruta sin espacios para compilar. Usa un checkout sin espacios.'
    }
  }
  $root = $buildJunction
  $short = $buildJunction
}
$flutter = Join-Path $short '.tools/flutter/bin/flutter.bat'
if (!(Test-Path -LiteralPath $flutter)) { throw 'Prepara Flutter 3.47.7 en .tools/flutter siguiendo README.md.' }
$env:ANDROID_HOME = Join-Path $short '.tools/android'
$env:GRADLE_USER_HOME = Join-Path $short '.tools/gradle'
$env:ANDROID_USER_HOME = Join-Path $short '.tools/android-user'
Push-Location (Join-Path $root 'client')
try {
  $pub = & $flutter pub get 2>&1
  $pub | Write-Output
  if ($LASTEXITCODE -ne 0) {
    if ("$pub" -notmatch '(?i)symlink') { throw 'No se pudieron resolver las dependencias Flutter.' }
    & (Join-Path $root 'scripts/prepare_windows_plugins.ps1')
    # Retry after preparing junctions: a failed pub get can leave Android's
    # GeneratedPluginRegistrant empty even when Gradle builds successfully.
    & $flutter pub get 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'No se pudieron registrar los componentes nativos de Flutter.' }
  }
  & (Join-Path $root 'scripts/prepare_windows_plugins.ps1')
  Invoke-Native { & $flutter analyze --no-pub }
  if ($LASTEXITCODE -ne 0) { throw 'El análisis del cliente falló.' }
  Invoke-Native { & $flutter test --no-pub }
  if ($LASTEXITCODE -ne 0) { throw 'Las pruebas del cliente fallaron.' }
  if ($Target -in @('windows','both')) {
    Invoke-Native { & $flutter build windows --release --no-pub --target lib/main.dart }
    if ($LASTEXITCODE -ne 0) { throw 'La compilación Windows falló.' }
    New-Item -ItemType Directory -Force -Path (Join-Path $root 'dist/Mesa-Windows') | Out-Null
    Copy-Item -Path 'build/windows/x64/runner/Release/*' -Destination (Join-Path $root 'dist/Mesa-Windows') -Recurse -Force
    # Copying a release over an older installation must also retire old assets.
    foreach ($name in @('sabores-andantes.json','agro-arracacha.json','agro-caribe.json')) {
      $retired = [IO.Path]::GetFullPath((Join-Path $root "dist/Mesa-Windows/data/flutter_assets/assets/catalogs/$name"))
      if (!$retired.StartsWith([IO.Path]::GetFullPath($root) + [IO.Path]::DirectorySeparatorChar)) { throw 'Recurso fuera del proyecto.' }
      if (Test-Path -LiteralPath $retired) { Remove-Item -LiteralPath $retired }
    }
    Invoke-Native { & (Join-Path $root '.venv/Scripts/python.exe') (Join-Path $root 'scripts/build_windows_installer.py') --client-dir (Join-Path $root 'client/build/windows/x64/runner/Release') }
    if ($LASTEXITCODE -ne 0) { throw 'Falta un instalador Windows utilizable; no se continúa la entrega.' }
  }
  if ($Target -in @('android','both')) {
    Invoke-Native { & (Join-Path $root '.venv/Scripts/python.exe') (Join-Path $root 'scripts/sign_android.py') }
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo preparar la firma Android.' }
    Invoke-Native { & $flutter build apk --release --target-platform android-arm64 --no-pub --target lib/main.dart }
    if ($LASTEXITCODE -ne 0) { throw 'La compilación Android falló.' }
    Invoke-Native { & (Join-Path $root '.venv/Scripts/python.exe') (Join-Path $root 'scripts/verify_android.py') 'build/app/outputs/flutter-apk/app-release.apk' }
    if ($LASTEXITCODE -ne 0) { throw 'La APK no contiene los componentes nativos necesarios para arrancar.' }
    New-Item -ItemType Directory -Force -Path (Join-Path $root 'dist') | Out-Null
    if (!$SkipPublish) {
      Invoke-Native { & (Join-Path $root '.venv/Scripts/python.exe') (Join-Path $root 'scripts/publish_android_update.py') 'build/app/outputs/flutter-apk/app-release.apk' }
      if ($LASTEXITCODE -ne 0) { throw 'No se pudo publicar el paquete de actualización Android.' }
    }
  }
} finally {
  Pop-Location
}
