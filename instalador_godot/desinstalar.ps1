# The Arnul War (Godot): quita accesos directos, entrada de "Aplicaciones instaladas" y datos guardados
$name = 'The Arnul War (Godot).lnk'
foreach ($folder in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))) {
  Remove-Item -LiteralPath (Join-Path $folder $name) -ErrorAction SilentlyContinue
}
Remove-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\TheArnulWarGodot' -Recurse -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $env:APPDATA 'Godot\app_userdata\The Arnul War') -Recurse -Force -ErrorAction SilentlyContinue
Add-Type -AssemblyName PresentationFramework
[System.Windows.MessageBox]::Show('The Arnul War (Godot) se ha desinstalado.', 'The Arnul War') | Out-Null
