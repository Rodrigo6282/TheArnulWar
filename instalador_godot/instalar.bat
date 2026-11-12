@echo off
rem The Arnul War (Godot) - instalacion
setlocal
set "SRC=%~dp0"
if defined TAW_DEST (set "DEST=%TAW_DEST%") else (set "DEST=%LOCALAPPDATA%\Programs\TheArnulWarGodot")
if not exist "%DEST%" mkdir "%DEST%"
for %%F in (TheArnulWar.exe icono.ico desinstalar.bat desinstalar.ps1 LEEME.txt) do copy /y "%SRC%%%F" "%DEST%" >nul
if defined TAW_TEST goto :eof
powershell -NoProfile -ExecutionPolicy Bypass -File "%SRC%accesos.ps1" -Dest "%DEST%"
start "" "%DEST%\TheArnulWar.exe"
