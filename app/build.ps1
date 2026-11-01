# Build the projector's own small app into an APK, without a build system.
#
# aapt2 turns the manifest into a package, javac compiles the sources against the Android 11
# platform, d8 converts them to Android bytecode, and apksigner signs the result with a key
# generated here on first run. Nothing is installed and the projector is not needed.
# -Source builds a different folder with the same steps: the keyboard lives beside this one
# as its own package, so that it can hold no permissions at all, and it is built by
#   .\build.ps1 -Source ..\keyboard -Apk projector-keyboard-1.0.apk
# Both are signed with the key kept here, so both update in place.
param(
  [string]$Sdk = "$env:LOCALAPPDATA\Android\sdk",
  [string]$Out = $(if ($env:HY320_APPS) { $env:HY320_APPS }
                   elseif ($env:HY320_BACKUP) { Join-Path $env:HY320_BACKUP 'apps' }
                   else { Join-Path $PSScriptRoot 'out' }),
  [string]$Source = $PSScriptRoot,
  [string]$Apk = 'projector-tools-1.3.apk'
)
$ErrorActionPreference = 'Stop'
$app = (Resolve-Path $Source).Path
$work = Join-Path $env:TEMP 'hy320-app-build'
Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $work, (Join-Path $work 'classes') | Out-Null

$bt = Get-ChildItem (Join-Path $Sdk 'build-tools') -Directory | Sort-Object Name | Select-Object -Last 1
$aapt2 = Join-Path $bt.FullName 'aapt2.exe'
$d8 = Join-Path $bt.FullName 'd8.bat'
$zipalign = Join-Path $bt.FullName 'zipalign.exe'
$apksigner = Join-Path $bt.FullName 'apksigner.bat'
$platform = Join-Path $Sdk 'platforms\android-30\android.jar'
if (-not (Test-Path $platform)) { throw "Android 11 platform not found at $platform" }
Write-Output "build tools $($bt.Name), platform android-30"

# 1. The resource package: a manifest, plus any assets.
$apkUnsigned = Join-Path $work 'app-unsigned.apk'
# Assets are carried along if there are any, and so are resources: the app draws its own
# screens, but a launcher needs a real icon and a TV banner to draw a tile for it, and
# those have to be resources because the manifest points at them.
$assets = Join-Path $app 'assets'
$assetArgs = if (Test-Path $assets) { @('-A', $assets) } else { @() }
$res = Join-Path $app 'res'
$resArgs = @()
if (Test-Path $res) {
  $resZip = Join-Path $work 'res.zip'
  & $aapt2 compile --dir $res -o $resZip
  if ($LASTEXITCODE -ne 0) { throw 'aapt2 compile failed' }
  $resArgs = @($resZip)
}
& $aapt2 link -o $apkUnsigned --manifest (Join-Path $app 'AndroidManifest.xml') `
  -I $platform --min-sdk-version 21 --target-sdk-version 30 --java (Join-Path $work 'gen') `
  @resArgs @assetArgs
if ($LASTEXITCODE -ne 0) { throw 'aapt2 link failed' }

# 2. Compile the sources.
$sources = Get-ChildItem (Join-Path $app 'src') -Recurse -Filter *.java | ForEach-Object { $_.FullName }
Write-Output "compiling $($sources.Count) source files"
# javac writes notes to stderr, which PowerShell would treat as failure, so it runs via cmd.
$argfile = Join-Path $work 'javac.args'
# An argument file treats a backslash as an escape, so paths go in with forward slashes.
$fwd = { param($p) $p -replace '\\', '/' }
$argLines = @(
  '-source 8'
  '-target 8'
  '-nowarn'
  "-bootclasspath `"$(& $fwd $platform)`""
  "-classpath `"$(& $fwd $platform)`""
  "-d `"$(& $fwd (Join-Path $work 'classes'))`""
) + ($sources | ForEach-Object { "`"$(& $fwd $_)`"" })
# Plain ASCII, with no byte-order mark: javac reads an argument file literally.
[IO.File]::WriteAllLines($argfile, [string[]]$argLines, (New-Object Text.ASCIIEncoding))
cmd /c "javac `"@$argfile`" 2>&1" | Where-Object { $_ -notmatch 'bootstrap class path|source value|target value|deprecat|^Note:' }
if ($LASTEXITCODE -ne 0) { throw "javac failed with exit $LASTEXITCODE" }

# 3. Convert to Android bytecode.
$classFiles = Get-ChildItem (Join-Path $work 'classes') -Recurse -Filter *.class | ForEach-Object { $_.FullName }
& cmd /c "`"$d8`" --min-api 21 --output `"$work`" --lib `"$platform`" $($classFiles -replace '^|$','"' -join ' ')"
if ($LASTEXITCODE -ne 0) { throw 'd8 failed' }
if (-not (Test-Path (Join-Path $work 'classes.dex'))) { throw 'no classes.dex was produced' }

# 4. Put the bytecode into the package.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($apkUnsigned, 'Update')
try {
  [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
    $zip, (Join-Path $work 'classes.dex'), 'classes.dex',
    [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
} finally { $zip.Dispose() }

# 5. Align and sign. The key is generated once and kept, so later versions update cleanly.
$keystore = Join-Path $PSScriptRoot 'projector-tools.keystore'
if (-not (Test-Path $keystore)) {
  Write-Output 'generating the app signing key (kept, so later versions can update in place)'
  # keytool reports progress on stderr, so it runs via cmd and only its exit code counts.
  cmd /c "keytool -genkeypair -keystore `"$keystore`" -storepass projector -keypass projector -alias projector -keyalg RSA -keysize 2048 -validity 10950 -dname `"CN=HY320 Projector Tools, OU=Owner built, O=Private, C=IT`" 2>&1" | Out-Null
  if (-not (Test-Path $keystore)) { throw 'could not create the signing key' }
}
$aligned = Join-Path $work 'app-aligned.apk'
& $zipalign -p -f 4 $apkUnsigned $aligned
if ($LASTEXITCODE -ne 0) { throw 'zipalign failed' }
New-Item -ItemType Directory -Force $Out | Out-Null
$final = Join-Path $Out $Apk
cmd /c "`"$apksigner`" sign --ks `"$keystore`" --ks-pass pass:projector --key-pass pass:projector --out `"$final`" `"$aligned`" 2>&1"
if (-not (Test-Path $final)) { throw 'signing produced no file' }

Write-Output "`n### the built app"
cmd /c "`"$apksigner`" verify --print-certs `"$final`" 2>&1" | Select-String 'SHA-256 digest|DOES NOT|Verified'
$aapt = Join-Path $bt.FullName 'aapt.exe'
cmd /c "`"$aapt`" dump badging `"$final`" 2>&1" | Select-String "^package:|^sdkVersion|^targetSdkVersion|launchable-activity|^uses-permission|^service"
"file: $final"
"size: $([math]::Round((Get-Item $final).Length/1KB)) KB"
"sha256: $((Get-FileHash $final -Algorithm SHA256).Hash.ToLower())"
