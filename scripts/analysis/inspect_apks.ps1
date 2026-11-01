# Inspect the copied vendor APKs with the Android SDK tools: identity, permissions, signer.
# Reads the APKs as data only; nothing is installed or run.
param(
  [string]$Backup = $(if ($env:HY320_BACKUP) { $env:HY320_BACKUP }
                      else { throw 'Set HY320_BACKUP to the folder holding your own dump of this projector.' }),
  [string]$ApkDir = (Join-Path $Backup 'analysis\apks'),
  [string]$Out    = (Join-Path $Backup 'analysis\inventory\apk_details.txt')
)
$ErrorActionPreference = 'Stop'
$bt = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Android\sdk\build-tools') -Directory | Sort-Object Name | Select-Object -Last 1
$aapt = Join-Path $bt.FullName 'aapt.exe'
$signer = Join-Path $bt.FullName 'apksigner.bat'

$rows = foreach ($f in Get-ChildItem $ApkDir -Filter *.apk | Sort-Object Name) {
  $badging = & $aapt dump badging $f.FullName 2>$null
  $pkg = ($badging | Select-String "^package: name='([^']+)'" | ForEach-Object { $_.Matches[0].Groups[1].Value }) -join ''
  $label = ($badging | Select-String "^application-label:'([^']*)'" | ForEach-Object { $_.Matches[0].Groups[1].Value }) -join ''
  $sdk = ($badging | Select-String "^sdkVersion:'([^']*)'" | ForEach-Object { $_.Matches[0].Groups[1].Value }) -join ''
  $perms = ($badging | Select-String "^uses-permission: name='([^']+)'" | ForEach-Object { $_.Matches[0].Groups[1].Value })
  $net = @($perms | Where-Object { $_ -match 'INTERNET|NETWORK_STATE|WIFI_STATE|CHANGE_NETWORK' })
  $sharedUid = ($badging | Select-String "sharedUserId='([^']+)'" | ForEach-Object { $_.Matches[0].Groups[1].Value }) -join ''
  # A failing verify is a finding, not an error: capture it through cmd so it never throws.
  $certs = cmd /c "`"$signer`" verify --print-certs `"$($f.FullName)`" 2>&1"
  $verdict = if ($certs -match 'DOES NOT VERIFY') { 'DOES NOT VERIFY' } else { 'verifies' }
  $sha = ($certs | Select-String 'certificate SHA-256 digest: ([0-9a-f]+)' | ForEach-Object { $_.Matches[0].Groups[1].Value }) -join ''
  $dn = ($certs | Select-String 'certificate DN: (.+)$' | ForEach-Object { $_.Matches[0].Groups[1].Value }) -join ''
  [pscustomobject]@{
    File = $f.Name; Package = $pkg; Label = $label; MinSdk = $sdk
    SharedUid = $sharedUid; Internet = ($net -join ','); PermCount = $perms.Count
    SignerSha256 = $sha; SignerDN = $dn; Verify = $verdict; SizeKB = [math]::Round($f.Length / 1KB)
  }
}
$rows | Export-Csv -NoTypeInformation -Encoding utf8 ($Out -replace '\.txt$', '.csv')
$rows | Format-Table File, Package, SharedUid, Internet, PermCount, Verify, SizeKB -AutoSize | Out-String -Width 220 | Set-Content -Encoding utf8 $Out
"--- distinct signers"
$rows | Group-Object SignerSha256 | ForEach-Object {
  "{0}  x{1}  {2}" -f $_.Name.Substring(0, [Math]::Min(16, $_.Name.Length)), $_.Count, (($_.Group.SignerDN | Select-Object -First 1))
}
Get-Content $Out
