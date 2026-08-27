@echo off
setlocal
rem Cross-platform fallback wrapper (pure ASCII)
set "SCRIPT=%~dp0dbclient.py"
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
echo ERROR: python not found, install Python or place a custom dbclient.exe here
exit /b 1
