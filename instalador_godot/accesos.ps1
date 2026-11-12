param([Parameter(Mandatory=$true)][string]$Dest)
# The Arnul War (Godot): accesos directos y registro en "Aplicaciones instaladas"
$ErrorActionPreference = 'Stop'
$name = 'The Arnul War (Godot)'
$exe  = Join-Path $Dest 'TheArnulWar.exe'
$sh = New-Object -ComObject WScript.Shell
foreach ($folder in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))) {
  $lnk = $sh.CreateShortcut((Join-Path $folder "$name.lnk"))
  $lnk.TargetPath = $exe
  $lnk.WorkingDirectory = $Dest
  $lnk.IconLocation = "$exe,0"
  $lnk.Description = $name
  $lnk.Save()
}
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\TheArnulWarGodot'
New-Item -Path $key -Force | Out-Null
$size = [int]((Get-ChildItem $Dest -Recurse -File | Measure-Object Length -Sum).Sum / 1KB)
$str = @{ DisplayName = $name; DisplayVersion = '0.1.0'; Publisher = 'TheArnul'; DisplayIcon = $exe; InstallLocation = $Dest;
          UninstallString = '"' + (Join-Path $Dest 'desinstalar.bat') + '"' }
foreach ($k in $str.Keys) { New-ItemProperty -Path $key -Name $k -Value $str[$k] -PropertyType String -Force | Out-Null }
foreach ($k in @('NoModify','NoRepair')) { New-ItemProperty -Path $key -Name $k -Value 1 -PropertyType DWord -Force | Out-Null }
New-ItemProperty -Path $key -Name 'EstimatedSize' -Value $size -PropertyType DWord -Force | Out-Null
