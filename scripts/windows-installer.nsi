Unicode true
!include "MUI2.nsh"
!include "x64.nsh"
Name "Peak 1.1.0"
OutFile "${OUTPUT}"
InstallDir "$LOCALAPPDATA\Programs\Peak"
InstallDirRegKey HKCU "Software\Peak" "InstallPath"
RequestExecutionLevel user
SetCompressor /SOLID lzma
VIProductVersion "1.1.0.0"
VIAddVersionKey "ProductName" "Peak"
VIAddVersionKey "FileDescription" "Peak installer"
VIAddVersionKey "FileVersion" "1.1.0"
VIAddVersionKey "LegalCopyright" "Copyright 2026 Seth Person"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\Peak.exe"
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP "Peak requires 64-bit Windows 10 or Windows 11."
    Abort
  ${EndIf}
FunctionEnd
Section "Peak"
  SetOutPath "$INSTDIR"
  File /r "${STAGE}\*"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateDirectory "$SMPROGRAMS\Peak"
  CreateShortcut "$SMPROGRAMS\Peak\Peak.lnk" "$INSTDIR\Peak.exe"
  CreateShortcut "$SMPROGRAMS\Peak\Uninstall Peak.lnk" "$INSTDIR\Uninstall.exe"
  WriteRegStr HKCU "Software\Peak" "InstallPath" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Peak" "DisplayName" "Peak"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Peak" "DisplayVersion" "1.1.0"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Peak" "Publisher" "Seth Person"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Peak" "UninstallString" '$"$INSTDIR\Uninstall.exe$"'
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Peak" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Peak" "NoRepair" 1
SectionEnd
Section "Uninstall"
  Delete "$SMPROGRAMS\Peak\Peak.lnk"
  Delete "$SMPROGRAMS\Peak\Uninstall Peak.lnk"
  RMDir "$SMPROGRAMS\Peak"
  Delete "$INSTDIR\Peak.exe"
  Delete "$INSTDIR\LICENSE"
  Delete "$INSTDIR\THIRD_PARTY.md"
  Delete "$INSTDIR\dependency-manifest.json"
  RMDir /r "$INSTDIR\Tools"
  RMDir /r "$INSTDIR\Licenses"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Peak"
  DeleteRegKey HKCU "Software\Peak"
SectionEnd
