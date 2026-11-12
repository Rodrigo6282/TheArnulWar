# Construye la version Godot de The Arnul War en .\dist_godot:
#   The Arnuls <version> Instalador.exe     - instalador con asistente (Inno Setup)
#   TheArnulWar_v<version>_Portable.zip    - juego sin instalar (exe + LEEME)
#   TheArnulWar.exe + *.dll                - el juego exportado por Godot (+ complemento WebRTC)
# Uso: powershell -ExecutionPolicy Bypass -File construir_instalador_godot.ps1
# Requisitos: plantillas de exportacion de Godot 4.7.2 (en %APPDATA%\Godot\export_templates)
#             e Inno Setup 6 (ISCC.exe).
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$godot = Join-Path $root 'herramientas\godot\Godot_v4.7.2-stable_win64_console.exe'
$dist = Join-Path $root 'dist_godot'
$iss = Join-Path $root 'instalador_godot\TheArnulWar.iss'

# version: application/config/version de project.godot
$ver = (Select-String -Path (Join-Path $root 'godot\project.godot') -Pattern '^config/version="(.+)"').Matches[0].Groups[1].Value
if (-not $ver) { throw 'No se encuentra config/version en project.godot.' }

$iscc = @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe", "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe") |
	Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'No se encuentra Inno Setup 6 (ISCC.exe). Instalalo desde https://jrsoftware.org/isdl.php' }

# carpeta de salida limpia (solo lo que genera este script)
New-Item -ItemType Directory -Force $dist | Out-Null
Get-ChildItem $dist -File | Remove-Item -Force

# 1) exportar el juego
$exeOut = Join-Path $dist 'TheArnulWar.exe'
& $godot --headless --path (Join-Path $root 'godot') --export-release 'Windows Desktop' $exeOut | Out-Null
if (-not (Test-Path $exeOut)) { throw 'Godot no ha exportado el juego (¿faltan las plantillas de exportacion 4.7.2?).' }

# 2) instalador
& $iscc /Q "/DAppVersion=$ver" $iss
if ($LASTEXITCODE -ne 0) { throw "Inno Setup ha fallado (codigo $LASTEXITCODE)." }

# 3) version portatil
$zip = Join-Path $dist "TheArnulWar_v${ver}_Portable.zip"
$dlls = @(Get-ChildItem $dist -Filter *.dll | ForEach-Object FullName)
if ($dlls.Count -eq 0) { throw 'Falta la DLL de WebRTC junto al exe (addons/webrtc_native).' }
Compress-Archive -Path (@($exeOut, (Join-Path $root 'instalador_godot\LEEME.txt')) + $dlls) -DestinationPath $zip -CompressionLevel Optimal -Force

Write-Host "The Arnul War v$ver listo en $dist"
Get-ChildItem $dist -File | Select-Object Name, @{n='MB';e={[math]::Round($_.Length/1MB,1)}}
