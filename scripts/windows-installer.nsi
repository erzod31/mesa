; -*- coding: utf-8 -*-
Unicode true
!include MUI2.nsh
!include LogicLib.nsh
!include FileFunc.nsh
!include x64.nsh
!include WordFunc.nsh
!include StrFunc.nsh
${StrStr}

Name "Mesa"
OutFile "${INSTALLER}"
InstallDir "$LOCALAPPDATA\Programs\Mesa"
RequestExecutionLevel user
SetCompressor zlib
VIProductVersion "${VERSION_DOTS}"
VIAddVersionKey /LANG=1034 "ProductName" "Mesa"
VIAddVersionKey /LANG=1034 "FileDescription" "Instalador de Mesa para Windows x64"
VIAddVersionKey /LANG=1034 "FileVersion" "${APP_VERSION}"
VIAddVersionKey /LANG=1034 "ProductVersion" "${APP_VERSION}"
VIAddVersionKey /LANG=1034 "LegalCopyright" "Mesa · Recetario familiar"
Icon "${ICON}"
UninstallIcon "${ICON}"
!define PRODUCT_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Mesa"
!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${OCR_LICENSE}"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "Spanish"

Function .onInit
  SetShellVarContext current
  SetRegView 64
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP "Mesa necesita Windows de 64 bits."
    Abort
  ${EndIf}
  ; A previous experimental QA flag was unsafe when quoted by Windows.
  ; Fail closed even if a caller supplies the obsolete quoted spelling.
  ${StrStr} $R0 "$CMDLINE" "/ISOLATED"
  ${If} $R0 != ""
    SetErrorLevel 87
    Abort
  ${EndIf}
  ReadRegStr $R1 HKCU "${PRODUCT_KEY}" "InstallLocation"
  ${If} $R1 != ""
    StrCpy $INSTDIR $R1
    ReadRegStr $R2 HKCU "${PRODUCT_KEY}" "DisplayVersion"
    ${VersionCompare} $R2 "${APP_VERSION}" $R3
    ${If} $R3 == 1
      MessageBox MB_ICONSTOP "Ya hay una versión posterior de Mesa instalada. Se conserva."
      Abort
    ${EndIf}
  ${EndIf}
FunctionEnd

Section "Mesa" SEC_MAIN
  SetShellVarContext current
  SetRegView 64
  ; Existing unmarked folders must not become an installation accidentally.
  IfFileExists "$INSTDIR\mesa-install.ini" safe_directory
  IfFileExists "$INSTDIR\*.*" 0 safe_directory
    MessageBox MB_ICONSTOP "Elige una carpeta vacía para instalar Mesa."
    Abort
  safe_directory:
  SetOverwrite on
  !include "${INSTALL_FILES}"
  WriteINIStr "$INSTDIR\mesa-install.ini" "Mesa" "Version" "${APP_VERSION}"
  WriteUninstaller "$INSTDIR\Desinstalar-Mesa.exe"
    CreateDirectory "$SMPROGRAMS\Mesa"
    CreateShortcut "$SMPROGRAMS\Mesa\Mesa.lnk" "$INSTDIR\Mesa.exe" "" "$INSTDIR\Mesa.exe"
    CreateShortcut "$SMPROGRAMS\Mesa\Desinstalar Mesa.lnk" "$INSTDIR\Desinstalar-Mesa.exe"
    CreateShortcut "$DESKTOP\Mesa.lnk" "$INSTDIR\Mesa.exe" "" "$INSTDIR\Mesa.exe"
    WriteRegStr HKCU "${PRODUCT_KEY}" "DisplayName" "Mesa"
    WriteRegStr HKCU "${PRODUCT_KEY}" "DisplayVersion" "${APP_VERSION}"
    WriteRegStr HKCU "${PRODUCT_KEY}" "Publisher" "Mesa · Recetario familiar"
    WriteRegStr HKCU "${PRODUCT_KEY}" "InstallLocation" "$INSTDIR"
    WriteRegStr HKCU "${PRODUCT_KEY}" "DisplayIcon" "$INSTDIR\Mesa.exe"
    WriteRegStr HKCU "${PRODUCT_KEY}" "UninstallString" '$\"$INSTDIR\Desinstalar-Mesa.exe$\"'
    WriteRegStr HKCU "${PRODUCT_KEY}" "QuietUninstallString" '$\"$INSTDIR\Desinstalar-Mesa.exe$\" /S'
    WriteRegDWORD HKCU "${PRODUCT_KEY}" "NoModify" 1
    WriteRegDWORD HKCU "${PRODUCT_KEY}" "NoRepair" 1
SectionEnd

Function un.onInit
  SetShellVarContext current
  SetRegView 64
  IfFileExists "$INSTDIR\mesa-install.ini" +3
    MessageBox MB_ICONSTOP "Falta el identificador de instalación; no se han eliminado archivos."
    Abort
    ReadRegStr $R0 HKCU "${PRODUCT_KEY}" "InstallLocation"
    ${If} $R0 != $INSTDIR
      MessageBox MB_ICONSTOP "Esta carpeta no coincide con la instalación registrada."
      Abort
    ${EndIf}
FunctionEnd

Section "Uninstall"
  ; Generated explicit file list: never recurse into user-created data.
  !include "${UNINSTALL_FILES}"
  Delete "$INSTDIR\mesa-install.ini"
  Delete "$INSTDIR\Desinstalar-Mesa.exe"
    Delete "$SMPROGRAMS\Mesa\Mesa.lnk"
    Delete "$SMPROGRAMS\Mesa\Desinstalar Mesa.lnk"
    RMDir "$SMPROGRAMS\Mesa"
    Delete "$DESKTOP\Mesa.lnk"
    DeleteRegKey HKCU "${PRODUCT_KEY}"
  ; %LOCALAPPDATA%\Mesa and the Flutter application-support folder survive.
  RMDir "$INSTDIR"
SectionEnd
