@echo off
setlocal
set "MS=D:\components\modelsim_ase\win32aloem"
set "PATH=%MS%;%PATH%"
set "WORK=%TEMP%\msim_render"
if exist "%WORK%" rmdir /s /q "%WORK%"
mkdir "%WORK%" 2>nul
cd /d "%WORK%"

vlib work
vlog -sv "%~dp0..\src\rtl\vga_timing.sv" "%~dp0..\src\rtl\sprite_render.sv" "%~dp0tb_render.sv"
if errorlevel 1 goto fail
vsim -c -do "run -all; quit -f" tb_render
if errorlevel 1 goto fail

copy /y frame.ppm "%~dp0frame.ppm" >nul
echo.
echo frame.ppm saved to: %~dp0frame.ppm
echo To view as PNG:  py "%~dp0ppm2png.py" "%~dp0frame.ppm" "%~dp0frame.png"
pause
exit /b 0

:fail
echo ==== FAILED ====
pause
exit /b 1