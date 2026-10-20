@echo off
setlocal
set "MS=C:\intelFPGA_lite\17.1\modelsim_ase\win32aloem"
set "PATH=%MS%;%PATH%"
set "WORK=%TEMP%\msim_game"
if exist "%WORK%" rmdir /s /q "%WORK%"
mkdir "%WORK%" 2>nul
cd /d "%WORK%"

echo [1/3] vlib work ...
vlib work
if errorlevel 1 goto fail

echo [2/3] vlog -sv ... (compile)
vlog -sv "%~dp0..\src\rtl\game_core.sv" "%~dp0tb_game_core.sv"
if errorlevel 1 goto fail

echo [3/3] vsim ... (run)
vsim -c -do "run -all; quit -f" tb_game_core

echo.
echo ==== simulation finished. Look for PASS / FAIL above ====
pause
exit /b 0

:fail
echo.
echo ==== COMPILE FAILED. See errors above ====
pause
exit /b 1
