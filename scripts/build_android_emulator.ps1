param([string]$Serial='emulator-5582')
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$taskFso=New-Object -ComObject Scripting.FileSystemObject
$taskShort=$taskFso.GetFolder($taskRoot).ShortPath
$taskJunction=$null
if ($taskShort.Contains(' ')) {
  $taskJunction=Join-Path ([IO.Path]::GetTempPath()) 'mesa-build'
  if (Test-Path -LiteralPath $taskJunction) { & cmd.exe /c "rmdir `"$taskJunction`"" 2>$null }
  & cmd.exe /c "mklink /J `"$taskJunction`" `"$taskRoot`"" | Out-Null
  if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath (Join-Path $taskJunction '.tools'))) { throw 'No se pudo preparar una ruta sin espacios para compilar.' }
  $taskRoot=$taskJunction
  $taskShort=$taskJunction
}
$taskAdb=Join-Path $taskRoot '.tools/android/platform-tools/adb.exe'
if ((& $taskAdb -s $Serial shell getprop ro.kernel.qemu).Trim() -ne '1') { throw 'Solo se permite un emulador de pruebas.' }
$taskAvd=(& $taskAdb -s $Serial shell getprop ro.boot.qemu.avd_name).Trim()
if ($taskAvd -ne 'MesaTest') { throw 'Solo se permite el laboratorio MesaTest.' }
$env:ANDROID_HOME=Join-Path $taskShort '.tools/android'
$env:ANDROID_USER_HOME=Join-Path $taskShort '.tools/android-user'
$env:GRADLE_USER_HOME=Join-Path $taskShort '.tools/gradle'
$env:ORG_GRADLE_PROJECT_mesaAbis='x86_64'
$taskPubspec=Get-Content (Join-Path $taskRoot 'client/pubspec.yaml') -Raw
if ($taskPubspec -notmatch '(?m)^version: (\d+\.\d+\.\d+)\+(\d+)') { throw 'Versión incorrecta.' }
$taskVersion=$Matches[1]
$taskCode=$Matches[2]
$taskTarget=Join-Path $taskRoot "output/auditoria-mesa-2026-10-12/08_reconstruccion/Mesa-Android-$taskVersion-$taskCode-x64-emulator.apk"
Push-Location (Join-Path $taskRoot 'client')
try {
  & (Join-Path $taskShort '.tools/flutter/bin/flutter.bat') build apk --release --target-platform android-x64 --android-project-arg=mesaAbis=x86_64 --no-pub --target lib/main.dart
  if ($LASTEXITCODE -ne 0) { throw 'Falló la compilación de laboratorio.' }
  & (Join-Path $taskRoot '.venv/Scripts/python.exe') (Join-Path $taskRoot 'scripts/verify_android.py') 'build/app/outputs/flutter-apk/app-release.apk'
  if ($LASTEXITCODE -ne 0) { throw 'La compilación no tiene los componentes nativos necesarios.' }
  Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-release.apk' -Destination $taskTarget -Force
  & $taskAdb -s $Serial install -r $taskTarget
  if ($LASTEXITCODE -ne 0) { throw 'No se pudo actualizar el emulador.' }
} finally {
  Pop-Location
  if ($taskJunction) { & cmd.exe /c "rmdir `"$taskJunction`"" 2>$null }
}
