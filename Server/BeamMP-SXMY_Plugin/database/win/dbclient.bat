@echo off
setlocal
rem Windows wrapper for dbclient.py (pure ASCII so cmd parses it correctly)
rem Called by modules/database.lua with: --host H --port P --db D --user U --pass W <cmd> [args]
set "SCRIPT=%~dp0..\dbclient.py"
where python >nul 2>nul
if %errorlevel%==0 (
    python "%SCRIPT%" %*
    exit /b %errorlevel%
)
where py >nul 2>nul
if %errorlevel%==0 (
    py "%SCRIPT%" %*
    exit /b %errorlevel%
)
echo ERROR: python not found, install Python or place a custom dbclient.exe in this folder
exit /b 1
