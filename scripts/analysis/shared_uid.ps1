# Which vendor apps ask to run under a shared system account, and what the full package list looks like.
param(
  [string]$Backup = $(if ($env:HY320_BACKUP) { $env:HY320_BACKUP }
                      else { throw 'Set HY320_BACKUP to the folder holding your own dump of this projector.' }),
  [string]$ApkDir = (Join-Path $Backup 'analysis\apks'),
  [string]$PkgList = '$PSScriptRoot\..\..'\.scratch\hy320-rework\unit\20261019-222433\packages-all.txt',
  [string]$Out = (Join-Path $Backup 'analysis\inventory\shared_uid.txt')
)
$bt = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Android\sdk\build-tools') -Directory | Sort-Object Name | Select-Object -Last 1
$aapt = Join-Path $bt.FullName 'aapt.exe'

$lines = foreach ($f in Get-ChildItem $ApkDir -Filter *.apk | Sort-Object Name) {
  $tree = cmd /c "`"$aapt`" dump xmltree `"$($f.FullName)`" AndroidManifest.xml 2>&1"
  $uid = ($tree | Select-String 'sharedUserId.*="([^"]+)"' | ForEach-Object { $_.Matches[0].Groups[1].Value }) -join ''
  $persist = if ($tree -match 'android:persistent\(0x[0-9a-f]+\)=\(type 0x12\)0xffffffff') { 'persistent' } else { '' }
  if ($uid -or $persist) { "{0,-42} {1,-24} {2}" -f $f.BaseName, $uid, $persist }
}
"######## apps with a shared account or marked persistent"
$lines
"`n######## package list by origin"
$pk = Get-Content $PkgList | ForEach-Object { ($_ -replace '^package:', '') }
$groups = $pk | ForEach-Object {
  $name = ($_ -split '=')[-1]
  $origin = switch -regex ($name) {
    '^com\.google\.android' { 'google' }
    '^(com\.android|android$|android\.|com\.qualcomm)' { 'aosp' }
    default { 'vendor' }
  }
  [pscustomobject]@{ Origin = $origin; Name = $name; Path = ($_ -split '=')[0] }
}
$groups | Group-Object Origin | ForEach-Object { "{0}: {1}" -f $_.Name, $_.Count }
"`n---- google apps present"
($groups | Where-Object Origin -eq 'google').Name | Sort-Object
$all = "######## apps with a shared account or marked persistent`n" + ($lines -join "`n") + "`n`n######## google apps`n" + (($groups | Where-Object Origin -eq 'google').Name -join "`n")
Set-Content -Encoding utf8 $Out $all
