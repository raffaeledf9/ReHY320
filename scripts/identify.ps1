# Ticket 07: read-only identity and inventory of the HY320 over USB ADB.
# Runs a fixed list of read commands; never writes to the projector.
# Usage: powershell -ExecutionPolicy Bypass -File identify.ps1 [-SelfTest]
param([switch]$SelfTest)
$ErrorActionPreference = 'Stop'

# Returns the serials of USB devices in state "device"; throws on any other state.
function Get-ReadyUsbSerials([string[]]$lines) {
    $rows = $lines | Where-Object { $_ -match '^\S+\s+(device|unauthorized|offline|no permissions)\b' }
    $bad = $rows | Where-Object { $_ -notmatch '^\S+\s+device\b' }
    if ($bad) { throw "Device not ready: $($bad -join '; ')" }
    # Network devices have serials like ip:port or mDNS names with ':'; USB serials do not.
    return @($rows | ForEach-Object { ($_ -split '\s+')[0] } | Where-Object { $_ -notmatch ':' })
}

if ($SelfTest) {
    $ok = @(Get-ReadyUsbSerials @('List of devices attached', 'ABC123  device product:x model:y', '192.168.1.9:5555  device product:x'))
    if ($ok.Count -ne 1 -or $ok[0] -ne 'ABC123') { throw 'selftest: ready device not found' }
    try { Get-ReadyUsbSerials @('ABC123  unauthorized usb:1-2'); throw 'selftest: unauthorized accepted' }
    catch { if ($_.Exception.Message -notlike 'Device not ready*') { throw } }
    if (@(Get-ReadyUsbSerials @('List of devices attached')).Count -ne 0) { throw 'selftest: empty list' }
    'selftest ok'; return
}

$adb = (Get-Command adb).Source
$serials = @(Get-ReadyUsbSerials (& $adb devices -l))
if ($serials.Count -ne 1) { throw "Expected exactly one projector on USB, found $($serials.Count). Check the cable and USB debugging." }
$s = $serials[0]

$out = Join-Path $PSScriptRoot "..\.scratch\hy320-rework\unit\$(Get-Date -Format yyyyMMdd-HHmmss)"
New-Item -ItemType Directory -Force $out | Out-Null
Start-Transcript (Join-Path $out 'transcript.txt') | Out-Null

$reads = [ordered]@{
    'getprop'         = 'getprop'
    'id'              = 'id'
    'display'         = 'wm size; wm density'
    'partitions'      = 'cat /proc/partitions'
    'by-name'         = 'ls -l /dev/block/by-name 2>&1; ls -l /dev/block/platform/*/by-name 2>&1'
    'mmc-nodes'       = 'ls -l /dev/block/mmcblk0* 2>&1'
    'mounts'          = 'cat /proc/mounts'
    'df'              = 'df'
    'packages-all'    = 'pm list packages -f -u'
    'packages-disabled' = 'pm list packages -d'
    'packages-thirdparty' = 'pm list packages -3'
}
foreach ($name in $reads.Keys) {
    & $adb -s $s shell $reads[$name] | Out-File -Encoding utf8 (Join-Path $out "$name.txt")
    "read $name"
}

$prop = Get-Content (Join-Path $out 'getprop.txt')
$keys = 'ro.build.fingerprint','ro.product.board','ro.product.device','ro.product.model','ro.board.platform',
        'ro.hardware','ro.build.display.id','ro.build.version.security_patch','ro.product.cpu.abilist'
$summary = foreach ($k in $keys) { $prop | Where-Object { $_.StartsWith("[$k]") } }
$summary += Get-Content (Join-Path $out 'display.txt')
$summary += Get-Content (Join-Path $out 'mmc-nodes.txt')
$summary | Out-File -Encoding utf8 (Join-Path $out 'summary.txt')
$summary
Stop-Transcript | Out-Null
"Saved to $out"
