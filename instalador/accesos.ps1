param([Parameter(Mandatory=$true)][string]$Dest)
# The Arnul War: accesos directos (escritorio y menu Inicio) y registro en "Aplicaciones instaladas"
$ErrorActionPreference = 'Stop'
$name = "The Arnul War"
$vbs  = Join-Path $Dest 'TheArnulWar.vbs'
$ico  = Join-Path $Dest 'icono.ico'
# Limpia la version anterior ("TheArnul's War") si existe
foreach ($folder in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))) {
  Remove-Item -LiteralPath (Join-Path $folder "TheArnul's War.lnk") -ErrorAction SilentlyContinue
}
Remove-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\TheArnulsWar' -Recurse -ErrorAction SilentlyContinue
foreach ($old in @((Join-Path $env:LOCALAPPDATA 'Programs\TheArnulsWar'), (Join-Path $env:LOCALAPPDATA 'TheArnulsWar'))) {
  if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Recurse -Force -ErrorAction SilentlyContinue }
}
$sh = New-Object -ComObject WScript.Shell
foreach ($folder in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))) {
  $lnk = $sh.CreateShortcut((Join-Path $folder "$name.lnk"))
  $lnk.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
  $lnk.Arguments = '"' + $vbs + '"'
  $lnk.WorkingDirectory = $Dest
  $lnk.IconLocation = "$ico,0"
  $lnk.Description = $name
  $lnk.Save()
}
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\TheArnulWar'
New-Item -Path $key -Force | Out-Null
$size = [int]((Get-ChildItem $Dest -Recurse -File | Measure-Object Length -Sum).Sum / 1KB)
$str = @{ DisplayName = $name; DisplayVersion = '1.0.0'; Publisher = 'TheArnul'; DisplayIcon = $ico; InstallLocation = $Dest;
          UninstallString = '"' + (Join-Path $Dest 'desinstalar.bat') + '"' }
foreach ($k in $str.Keys) { New-ItemProperty -Path $key -Name $k -Value $str[$k] -PropertyType String -Force | Out-Null }
foreach ($k in @('NoModify','NoRepair')) { New-ItemProperty -Path $key -Name $k -Value 1 -PropertyType DWord -Force | Out-Null }
New-ItemProperty -Path $key -Name 'EstimatedSize' -Value $size -PropertyType DWord -Force | Out-Null
