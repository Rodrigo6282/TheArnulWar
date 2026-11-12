# Exporta la version Godot y construye su instalador en .\dist_godot
#   powershell -ExecutionPolicy Bypass -File construir_instalador_godot.ps1
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$godot = Join-Path $root 'herramientas\godot\Godot_v4.7.2-stable_win64_console.exe'
$dist = Join-Path $root 'dist_godot'
New-Item -ItemType Directory -Force $dist | Out-Null
$exeOut = Join-Path $dist 'TheArnulWar.exe'
& $godot --headless --path (Join-Path $root 'godot') --export-release 'Windows Desktop' $exeOut | Out-Null
if (-not (Test-Path $exeOut)) { throw 'Godot no ha exportado el juego.' }
# IExpress falla con espacios en las rutas: se construye en una carpeta temporal sin espacios
$tmp = $env:TEMP; if ($tmp -match ' ') { $tmp = (New-Object -ComObject Scripting.FileSystemObject).GetFolder($tmp).ShortPath }
$build = Join-Path $tmp 'TAWGbuild'
$pkg = Join-Path $build 'paquete'
if (Test-Path $build) { Remove-Item $build -Recurse -Force }
New-Item -ItemType Directory -Force $pkg | Out-Null
Copy-Item $exeOut, (Join-Path $root 'icono.ico') $pkg
Copy-Item (Join-Path $root 'instalador_godot\*') $pkg
$files = @(Get-ChildItem $pkg -File | ForEach-Object Name)
$target = Join-Path $build 'TheArnulWar_Godot_Instalador.exe'
$fileLines = ''; $srcLines = ''
for ($i = 0; $i -lt $files.Count; $i++) { $fileLines += "FILE$i=`"$($files[$i])`"`r`n"; $srcLines += "%FILE$i%=`r`n" }
$sed = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=1
HideExtractAnimation=0
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=%TargetName%
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=%PostInstallCmd%
AdminQuietInstCmd=%AdminQuietInstCmd%
UserQuietInstCmd=%UserQuietInstCmd%
SourceFiles=SourceFiles
[Strings]
InstallPrompt=¿Quieres instalar The Arnul War (versión Godot) en este equipo?
DisplayLicense=
FinishMessage=The Arnul War (Godot) se ha instalado. Tienes el acceso directo en el escritorio y en el menú Inicio.
TargetName=$target
FriendlyName=The Arnul War (Godot) - Instalador
AppLaunched=cmd /c instalar.bat
PostInstallCmd=<None>
AdminQuietInstCmd=cmd /c instalar.bat
UserQuietInstCmd=cmd /c instalar.bat
$fileLines[SourceFiles]
SourceFiles0=$pkg\
[SourceFiles0]
$srcLines
"@
$sedPath = Join-Path $build 'instalador.sed'
[System.IO.File]::WriteAllText($sedPath, $sed, [System.Text.Encoding]::GetEncoding(1252))
Start-Process -FilePath (Join-Path $env:WINDIR 'System32\iexpress.exe') -ArgumentList '/N', '/Q', $sedPath -Wait
if (-not (Test-Path $target)) { throw 'IExpress no ha generado el instalador.' }
Copy-Item $target (Join-Path $dist 'TheArnulWar_Godot_Instalador.exe') -Force
Copy-Item (Join-Path $root 'instalador_godot\LEEME.txt') $dist -Force
Remove-Item $build -Recurse -Force
Get-ChildItem $dist -File | Select-Object Name, @{n='MB';e={[math]::Round($_.Length/1MB,1)}}
