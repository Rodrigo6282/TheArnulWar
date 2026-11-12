# The Arnul War: quita accesos directos, entrada de "Aplicaciones instaladas" y datos guardados
$name = "The Arnul War.lnk"
foreach ($folder in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))) {
  Remove-Item -LiteralPath (Join-Path $folder $name) -ErrorAction SilentlyContinue
}
Remove-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\TheArnulWar' -Recurse -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'TheArnulWar') -Recurse -Force -ErrorAction SilentlyContinue
Add-Type -AssemblyName PresentationFramework
[System.Windows.MessageBox]::Show("The Arnul War se ha desinstalado.", "The Arnul War") | Out-Null
