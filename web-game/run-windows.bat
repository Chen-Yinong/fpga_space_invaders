@echo off
setlocal
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Node.js is not installed.
  echo Download and install it from https://nodejs.org, then run this file again.
  pause
  exit /b 1
)
start "Space Invaders Server" cmd /k "node server.mjs"
timeout /t 1 /nobreak >nul
start "" http://127.0.0.1:4173
endlocal
