; The Arnul War - instalador (Inno Setup 6)
; Lo compila construir_instalador_godot.ps1 despues de exportar el juego con Godot:
;   ISCC.exe instalador_godot\TheArnulWar.iss
; Rutas relativas a esta carpeta.

#define AppName "The Arnul War"
; la version la pasa el script de construccion (/DAppVersion=..., leida de project.godot)
#ifndef AppVersion
  #define AppVersion "1.2"
#endif
#define AppExe "TheArnulWar.exe"
#define OldKey "Software\Microsoft\Windows\CurrentVersion\Uninstall\TheArnulWarGodot"

[Setup]
AppId={{8F4C2A31-6B7E-4C1D-9A2E-3D5B7C9E1F42}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} v{#AppVersion}
AppPublisher=TheArnul
AppCopyright=TheArnul 2026
VersionInfoVersion={#AppVersion}.0.0
VersionInfoDescription=Instalador de {#AppName}
; sin permisos de administrador por defecto (se instala para el usuario actual);
; el asistente permite elegir "para todos los usuarios" si se quiere
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}
SetupIconFile=..\icono.ico
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
Compression=lzma2/ultra64
SolidCompression=yes
CloseApplications=yes
OutputDir=..\dist_godot
OutputBaseFilename=TheArnulWar_v{#AppVersion}_Instalador

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\dist_godot\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion
Source: "LEEME.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Comment: "Shooter en primera persona"
Name: "{autoprograms}\{#AppName} - Leeme"; Filename: "{app}\LEEME.txt"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[Code]
// Quita la instalacion antigua (instalador IExpress de versiones anteriores), conservando
// el progreso guardado: accesos directos "The Arnul War (Godot)", su carpeta y su entrada.
procedure RemoveOldInstall();
var
  OldDir: String;
begin
  if not RegKeyExists(HKCU, '{#OldKey}') then
    Exit;
  DeleteFile(ExpandConstant('{userdesktop}\The Arnul War (Godot).lnk'));
  DeleteFile(ExpandConstant('{userprograms}\The Arnul War (Godot).lnk'));
  OldDir := ExpandConstant('{localappdata}\Programs\TheArnulWarGodot');
  if DirExists(OldDir) then
    DelTree(OldDir, True, True, True);
  RegDeleteKeyIncludingSubkeys(HKCU, '{#OldKey}');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
    RemoveOldInstall();
end;

// Al desinstalar: preguntar si tambien se borra el progreso (ajustes, records, medallas)
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  SaveDir: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    SaveDir := ExpandConstant('{userappdata}\Godot\app_userdata\{#AppName}');
    if DirExists(SaveDir) and not UninstallSilent() then
      if MsgBox('¿Quieres borrar también tu progreso guardado (ajustes, récords y medallas)?',
                mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
        DelTree(SaveDir, True, True, True);
  end;
end;
