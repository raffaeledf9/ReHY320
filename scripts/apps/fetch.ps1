# Download the open-source apps the projector will run, and check each one.
# Downloads only; nothing is installed and nothing touches the projector.
param([string]$Dir = $(if ($env:HY320_APPS) { $env:HY320_APPS }
                       elseif ($env:HY320_BACKUP) { Join-Path $env:HY320_BACKUP 'apps' }
                       else { throw 'Set HY320_BACKUP (or HY320_APPS, or pass -Dir) to where the apps should be downloaded.' }))
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $Dir | Out-Null
$bt = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Android\sdk\build-tools') -Directory | Sort-Object Name | Select-Object -Last 1
$signer = Join-Path $bt.FullName 'apksigner.bat'
$aapt = Join-Path $bt.FullName 'aapt.exe'

# name, url, expected file digest (empty = none published), expected signer digest (empty = none published)
$apps = @(
  @{ Name = 'airplay-server-0.0.36.apk'
     Url  = 'https://github.com/jqssun/android-airplay-server/releases/download/v0.0.36/app-release.apk'
     File = 'b8c7c595ed93f91562feedce92c27800f08f9c84df424f6ac2045e82324cf2a4'
     Cert = '64ca1fa39ddf9e0e89c57d73fb681d2a5b35ae20f071771e2eb401b5032ef1a9' }
  @{ Name = 'material-files-1.7.5.apk'
     Url  = 'https://f-droid.org/repo/me.zhanghai.android.files_40.apk'
     File = ''
     Cert = '' }
)

foreach ($a in $apps) {
  $path = Join-Path $Dir $a.Name
  if (-not (Test-Path $path)) {
    Write-Output "### downloading $($a.Name)"
    try { Invoke-WebRequest -UseBasicParsing $a.Url -OutFile $path }
    catch { Write-Output "   DOWNLOAD FAILED: $($_.Exception.Message)"; continue }
  }
  $size = (Get-Item $path).Length
  $fileHash = (Get-FileHash $path -Algorithm SHA256).Hash.ToLower()
  Write-Output "### $($a.Name): $([math]::Round($size/1MB,1)) MB"
  Write-Output "   file sha256:   $fileHash"
  if ($a.File) {
    Write-Output "   published:     $($a.File)"
    Write-Output "   file digest:   $(if ($fileHash -eq $a.File) { 'MATCHES' } else { 'DOES NOT MATCH - do not install' })"
  } else {
    Write-Output "   file digest:   nothing published to compare against; recorded above"
  }
  $certs = cmd /c "`"$signer`" verify --print-certs `"$path`" 2>&1"
  $sha = ($certs | Select-String 'certificate SHA-256 digest: ([0-9a-f]+)' | ForEach-Object { $_.Matches[0].Groups[1].Value }) -join ''
  $verdict = if ($certs -match 'DOES NOT VERIFY') { 'signature DOES NOT VERIFY' } else { 'signature verifies' }
  Write-Output "   $verdict"
  Write-Output "   signer sha256: $sha"
  if ($a.Cert) {
    Write-Output "   pinned signer: $($a.Cert)"
    Write-Output "   signer:        $(if ($sha -eq $a.Cert) { 'MATCHES the pinned key' } else { 'DOES NOT MATCH - do not install' })"
  } else {
    Write-Output "   signer:        nothing published to compare against; recorded so a later update signed differently is visible"
  }
  $badging = cmd /c "`"$aapt`" dump badging `"$path`" 2>&1"
  $pkg = ($badging | Select-String "^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'" | ForEach-Object { "$($_.Matches[0].Groups[1].Value) version $($_.Matches[0].Groups[3].Value) (code $($_.Matches[0].Groups[2].Value))" }) -join ''
  $abis = ($badging | Select-String "native-code: (.+)$" | ForEach-Object { $_.Matches[0].Groups[1].Value }) -join ''
  $sdk = ($badging | Select-String "^sdkVersion:'([^']+)'" | ForEach-Object { $_.Matches[0].Groups[1].Value }) -join ''
  $net = ($badging | Select-String "uses-permission: name='android.permission.INTERNET'") -ne $null
  Write-Output "   package:       $pkg"
  Write-Output "   needs Android: API $sdk and up | native code: $(if ($abis) { $abis } else { 'none (works on any processor)' })"
  Write-Output "   internet permission: $net"
}
Write-Output "`n### files in $Dir"
Get-ChildItem $Dir | Select-Object Name, Length | Format-Table -AutoSize | Out-String
