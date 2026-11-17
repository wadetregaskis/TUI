@echo off
rem Runs one probe in the console this starts in, its record in PROBE_OUT, and
rem marks it done: probe.cmd <probe.py> <record.json> [arguments]
rem
rem Started by drive.py in a new Windows Terminal window or a conhost window.
rem UTF-8 mode, as the records are UTF-8. PROBE_PYTHON names the Python to use
rem (default: python on the PATH). The probe's errors go to <record>.stderr.txt
rem and its exit status to <record>.done, which drive.py waits for.
setlocal
set "PROBE_OUT=%~2"
set PYTHONUTF8=1
if "%PROBE_PYTHON%"=="" set "PROBE_PYTHON=python"
"%PROBE_PYTHON%" "%~dp0run.py" %1 %3 %4 %5 %6 %7 %8 %9 2> "%~2.stderr.txt"
>"%~2.done" echo %ERRORLEVEL%
