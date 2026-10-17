@echo off
setlocal
set "V=D:\fpga\2026.1\Vivado\bin"
set "R=%~dp0.."
set "W=%TEMP%\xsim_all_%RANDOM%"
mkdir "%W%" 2>nul
cd /d "%W%"

echo ==========================================================
echo  [1/4] tb_game_core
echo ==========================================================
call "%V%\xvlog.bat" -sv "%R%\src\rtl\game_core.sv" "%R%\sim\tb_game_core.sv" >nul 2>nul
call "%V%\xelab.bat" tb_game_core -s s1 >nul 2>nul
call "%V%\xsim.bat" s1 -runall 2>&1 | findstr /C:"PASS" /C:"FAIL" /C:"TB "

echo.
echo ==========================================================
echo  [2/4] tb_gesture_dir_fsm
echo ==========================================================
call "%V%\xvlog.bat" -sv "%R%\src\rtl\gesture_dir_fsm.sv" "%R%\sim\tb_gesture_dir_fsm.sv" >nul 2>nul
call "%V%\xelab.bat" tb_gesture_dir_fsm -s s2 >nul 2>nul
call "%V%\xsim.bat" s2 -runall 2>&1 | findstr /C:"cmd=" /C:"FAIL" /C:"TB "

echo.
echo ==========================================================
echo  [3/4] tb_render   (makes frame.ppm)
echo ==========================================================
call "%V%\xvlog.bat" -sv "%R%\src\rtl\vga_timing.sv" "%R%\src\rtl\sprite_render.sv" "%R%\sim\tb_render.sv" >nul 2>nul
call "%V%\xelab.bat" tb_render -s s3 >nul 2>nul
call "%V%\xsim.bat" s3 -runall 2>&1 | findstr /C:"FRAME_DONE"
copy /y frame.ppm "%R%\sim\frame.ppm" >nul 2>nul

echo.
echo ==========================================================
echo  [4/4] tb_dyn_render   (makes frame_0..8.ppm)
echo ==========================================================
call "%V%\xvlog.bat" -sv "%R%\src\rtl\debounce.sv" "%R%\src\rtl\game_core.sv" "%R%\src\rtl\vga_timing.sv" "%R%\src\rtl\sprite_render.sv" "%R%\src\rtl\top_button_game.sv" "%R%\sim\tb_dyn_render.sv" >nul 2>nul
call "%V%\xelab.bat" tb_dyn_render -s s4 >nul 2>nul
call "%V%\xsim.bat" s4 -runall 2>&1 | findstr /C:"frame_" /C:"ALL FRAMES"

echo.
echo ==========================================================
echo  DONE.  PPM images in: %W%
echo ==========================================================
pause