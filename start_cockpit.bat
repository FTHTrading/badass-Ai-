@echo off
title FTH Global - Doc-Intelligence Cockpit Automator
color 0B
echo ==========================================================
echo       FTH GLOBAL - DOC-INTELLIGENCE COCKPIT BOOT
echo ==========================================================
echo Checking local HTTP server environment...
echo.

:: Check if Node/NPX is installed
where npx >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    echo [FOUND] Node.js and NPX packages.
    echo Launching local http-server on port 8080...
    echo Browser window opening automatically.
    echo Press Ctrl+C in this terminal window to stop the server.
    echo.
    start "" "http://localhost:8080/public/index.html"
    npx http-server -p 8080 ./
    goto end
)

:: Check if Python is installed
where python >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    echo [FOUND] Python runtime.
    echo Launching local python server on port 8080...
    echo Browser window opening automatically.
    echo Press Ctrl+C in this terminal window to stop the server.
    echo.
    start "" "http://localhost:8080/public/index.html"
    python -m http.server 8080
    goto end
)

:: Fallback if no server package is found
echo [WARNING] Node.js and Python are not registered in your Windows PATH.
echo Microphone dictation may be limited by local sandbox restrictions.
echo Launching Cockpit console directly via file protocol...
echo.
start "" "%~dp0public\index.html"

:end
pause
