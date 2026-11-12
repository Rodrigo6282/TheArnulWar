' The Arnul War - lanzador
' Abre el juego en una ventana propia (Microsoft Edge o Google Chrome en modo aplicacion).
' Si no encuentra ninguno, lo abre en el navegador predeterminado.
Option Explicit
Dim sh, fso, dir, page, url, prof, args, exe, cands, c
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
page = dir & "\index.html"
url = "file:///" & Replace(Replace(page, "\", "/"), " ", "%20")
prof = sh.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\TheArnulWar\perfil"
cands = Array( _
  sh.ExpandEnvironmentStrings("%ProgramFiles(x86)%") & "\Microsoft\Edge\Application\msedge.exe", _
  sh.ExpandEnvironmentStrings("%ProgramFiles%") & "\Microsoft\Edge\Application\msedge.exe", _
  sh.ExpandEnvironmentStrings("%ProgramFiles%") & "\Google\Chrome\Application\chrome.exe", _
  sh.ExpandEnvironmentStrings("%ProgramFiles(x86)%") & "\Google\Chrome\Application\chrome.exe", _
  sh.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\Google\Chrome\Application\chrome.exe")
exe = ""
For Each c In cands
  If exe = "" Then
    If fso.FileExists(c) Then exe = c
  End If
Next
args = " --app=""" & url & """ --user-data-dir=""" & prof & """ --start-maximized --no-first-run --no-default-browser-check --autoplay-policy=no-user-gesture-required"
If WScript.Arguments.Count > 0 Then
  If WScript.Arguments(0) = "/prueba" Then
    WScript.Echo exe & args
    WScript.Quit
  End If
End If
If exe <> "" Then
  sh.Run """" & exe & """" & args, 1, False
Else
  sh.Run """" & page & """", 1, False
End If
