@echo off
setlocal
set "MS=D:\components\modelsim_ase\win32aloem"
set "PATH=%MS%;%PATH%"
set "R=%~dp0.."
set "W=%TEMP%\msim_all"
if exist "%W%" rmdir /s /q "%W%"
mkdir "%W%" 2>nul
cd /d "%W%"
vlib work >nul

echo ==========================================================
echo  [1/4] game logic   tb_game_core
echo ==========================================================
vlog -sv "%R%\src\rtl\game_core.sv" "%R%\sim\tb_game_core.sv" >nul
vsim -c -do "run -all; quit -f" tb_game_core 2>&1 | findstr /C:"PASS" /C:"FAIL" /C:"TB "

echo.
echo ==========================================================
echo  [2/4] gesture FSM  tb_gesture_dir_fsm
echo ==========================================================
vlog -sv "%R%\src\rtl\gesture_dir_fsm.sv" "%R%\sim\tb_gesture_dir_fsm.sv" >nul
vsim -c -do "run -all; quit -f" tb_gesture_dir_fsm 2>&1 | findstr /C:"PASS" /C:"FAIL" /C:"TB "

echo.
echo ==========================================================
echo  [3/4] static render  tb_render  (makes frame.ppm)
echo ==========================================================
vlog -sv "%R%\src\rtl\vga_timing.sv" "%R%\src\rtl\sprite_render.sv" "%R%\sim\tb_render.sv" >nul
vsim -c -do "run -all; quit -f" tb_render 2>&1 | findstr /C:"FRAME_DONE" /C:"Error"
copy /y frame.ppm "%R%\sim\frame.ppm" >nul

echo.
echo ==========================================================
echo  [4/4] dynamic render  tb_dyn_render  (makes frame_0..8.ppm)
echo ==========================================================
vlog -sv "%R%\src\rtl\debounce.sv" "%R%\src\rtl\game_core.sv" "%R%\src\rtl\vga_timing.sv" "%R%\src\rtl\sprite_render.sv" "%R%\src\rtl\top_button_game.sv" "%R%\sim\tb_dyn_render.sv" >nul
vsim -c -do "run -all; quit -f" tb_dyn_render 2>&1 | findstr /C:"frame_" /C:"ALL FRAMES"
copy /y frame_0.ppm "%R%\sim\frame_0.ppm" >nul
copy /y frame_8.ppm "%R%\sim\frame_8.ppm" >nul

echo.
echo ==========================================================
echo  ALL SIMULATIONS DONE.
echo  PPM images are in: %W%
echo  Convert to PNG:  py "%R%\sim\ppm2png.py" frame.ppm frame.png
echo ==========================================================
pause