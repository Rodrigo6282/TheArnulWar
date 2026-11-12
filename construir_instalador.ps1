# Construye el instalador y la version portatil de The Arnul War en .\dist
#   powershell -ExecutionPolicy Bypass -File construir_instalador.ps1
# Usa IExpress (incluido en Windows), no necesita instalar nada.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$dist = Join-Path $root 'dist'
# IExpress falla con espacios en las rutas: se construye en una carpeta temporal sin espacios
$tmp = $env:TEMP; if ($tmp -match ' ') { $tmp = (New-Object -ComObject Scripting.FileSystemObject).GetFolder($tmp).ShortPath }
$build = Join-Path $tmp 'TAWbuild'
$pkg  = Join-Path $build 'paquete'
$port = Join-Path $dist 'TheArnulWar_Portable'
if (Test-Path $build) { Remove-Item $build -Recurse -Force }
foreach ($d in @($pkg, $port)) { if (Test-Path $d) { Remove-Item $d -Recurse -Force } ; New-Item -ItemType Directory -Force $d | Out-Null }

# --- paquete plano para IExpress (no admite subcarpetas; instalar.bat recoloca las texturas)
Copy-Item (Join-Path $root 'index.html'), (Join-Path $root 'three.min.js'), (Join-Path $root 'texturas\pbr1.js'), (Join-Path $root 'icono.ico') $pkg
Copy-Item (Join-Path $root 'instalador\*') $pkg
$files = @(Get-ChildItem $pkg -File | ForEach-Object Name)
$target = Join-Path $build 'TheArnulWar_Instalador.exe'
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
InstallPrompt=¿Quieres instalar The Arnul War en este equipo?
DisplayLicense=
FinishMessage=The Arnul War se ha instalado. Tienes el acceso directo en el escritorio y en el menú Inicio.
TargetName=$target
FriendlyName=The Arnul War - Instalador
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
if (Test-Path $target) { Remove-Item $target -Force }
Start-Process -FilePath (Join-Path $env:WINDIR 'System32\iexpress.exe') -ArgumentList '/N', '/Q', $sedPath -Wait
if (-not (Test-Path $target)) { throw 'IExpress no ha generado el instalador.' }
Copy-Item $target (Join-Path $dist 'TheArnulWar_Instalador.exe') -Force

# --- version portatil
Copy-Item (Join-Path $root 'index.html'), (Join-Path $root 'three.min.js'), (Join-Path $root 'icono.ico') $port
New-Item -ItemType Directory -Force (Join-Path $port 'texturas') | Out-Null
Copy-Item (Join-Path $root 'texturas\pbr1.js') (Join-Path $port 'texturas')
Copy-Item (Join-Path $root 'instalador\TheArnulWar.vbs') (Join-Path $port 'Jugar.vbs')
Copy-Item (Join-Path $root 'instalador\LEEME.txt') $port
$zip = Join-Path $dist 'TheArnulWar_Portable.zip'
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $port -DestinationPath $zip
Copy-Item (Join-Path $root 'instalador\LEEME.txt') $dist
Remove-Item $build -Recurse -Force
Get-ChildItem $dist -File | Select-Object Name, @{n='MB';e={[math]::Round($_.Length/1MB,1)}}
