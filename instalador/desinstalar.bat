@echo off
rem The Arnul War - desinstalacion
taskkill /f /fi "WINDOWTITLE eq The Arnul War*" >nul 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0desinstalar.ps1"
cd /d "%TEMP%"
(goto) 2>nul & rd /s /q "%~dp0"
