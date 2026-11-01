# Starts one build step (setup, build, patch, sign, check) in WSL, in the background.
#
#   powershell -File scripts\build\start.ps1 build      then watch <build>\build.log
#
# -Build is where the WSL image and the logs live, in WSL's own form (/mnt/<letter>/...),
# because everything below is handed to wsl.exe. It defaults to HY320_BUILD if WSLENV
# translates it for you; otherwise pass it.
#
# WSL shuts a distro down a few seconds after its last wsl.exe call ends, which wipes /tmp
# and the loop mount, so the step runs inside a hidden wsl.exe that stays open until it ends.
# Scripts are read straight from the repo with line endings fixed on the fly: nothing in
# /tmp is relied on.
param([Parameter(Mandatory)][ValidateSet('setup', 'build', 'patch', 'sign', 'check')][string]$Step,
      [string]$Build = $(if ($env:HY320_BUILD -like '/mnt/*') { $env:HY320_BUILD }
                         else { throw 'Pass -Build as a WSL path, e.g. /mnt/d/hy320-build.' }))
# Where this script sits, in WSL's own form, so nothing here is tied to one machine.
$repo = '/mnt/' + $PSScriptRoot.Substring(0, 1).ToLower() +
        ($PSScriptRoot.Substring(2).Replace('\', '/'))
$log = "$Build/$Step.log"
$cmd = "mkdir -p $Build; export SUDO_UID=1000 SUDO_GID=1000 REPO=$repo; " +
       "sed 's/\r`$//' $repo/$Step.sh | bash > $log 2>&1; echo EXIT=`$? >> $log"
if ($Step -eq 'check') {
    wsl.exe -u root -e bash -c "sed 's/\r`$//' $repo/check.sh | bash"
    return
}
$p = Start-Process -PassThru -WindowStyle Hidden -FilePath 'wsl.exe' -ArgumentList @('-u', 'root', '-e', 'bash', '-c', "`"$cmd`"")
"started $Step in wsl.exe pid $($p.Id); log $Build/$Step.log"
