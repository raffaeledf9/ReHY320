@echo off
rem Starts the probation receiver, listening for the router's syslog.
rem
rem A wrapper because the scheduled task's command line is capped at 262
rem characters. It must be python.exe, not pythonw.exe: the Windows firewall
rem rule that lets the router's syslog in is scoped to that one binary, and a
rem program-scoped rule admits nothing else. Minimised, so the console it needs
rem does not follow the laptop around.
rem
rem Set these two for your own house before the first run, or pass them in:
rem   HY320_PC   the address this PC has on the home network, the same one given
rem              to the router as its Remote Log Server and to the firewall rule
rem   HY320_LAN  the home network's prefix, trailing dot included
if "%HY320_PC%"=="" set HY320_PC=%1
if "%HY320_LAN%"=="" set HY320_LAN=192.168.1.
if "%HY320_PC%"=="" echo Set HY320_PC to this PC's address on the home network. & exit /b 2
set ROOT=%~dp0..\..
start "HY320 syslog" /min "python" ^
 "%ROOT%\scripts\probation\receiver.py" %HY320_PC% %HY320_LAN% ^
 "%ROOT%\scripts\probation\expected.txt" "%ROOT%\.scratch\probation-log"
