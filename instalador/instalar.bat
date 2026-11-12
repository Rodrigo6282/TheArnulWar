@echo off
rem The Arnul War - instalacion (la ejecuta el instalador .exe tras extraer los archivos)
setlocal
set "SRC=%~dp0"
if defined TAW_DEST (set "DEST=%TAW_DEST%") else (set "DEST=%LOCALAPPDATA%\Programs\TheArnulWar")
if not exist "%DEST%\texturas" mkdir "%DEST%\texturas"
for %%F in (index.html three.min.js icono.ico TheArnulWar.vbs desinstalar.bat desinstalar.ps1 LEEME.txt) do copy /y "%SRC%%%F" "%DEST%" >nul
copy /y "%SRC%pbr1.js" "%DEST%\texturas" >nul
if defined TAW_TEST goto :eof
powershell -NoProfile -ExecutionPolicy Bypass -File "%SRC%accesos.ps1" -Dest "%DEST%"
start "" wscript.exe "%DEST%\TheArnulWar.vbs"
