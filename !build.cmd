@echo off
if exist desolate.com del desolate.com
if exist desolate-boot.com del desolate-boot.com
if exist desolate.lst del desolate.lst

rem The game for DOS
tools\nasm.exe -f bin desolcoda.asm -o desolate.com -l desolate.lst
if errorlevel 1 goto Failed

dir /-c desolate.com|findstr /R /C:"desolate.com"

rem Variant for the test floppy: -DNODOS = no DOS to return to, the program reboots on exit
tools\nasm.exe -f bin -DNODOS desolcoda.asm -o desolate-boot.com
if errorlevel 1 goto Failed

rem Self-booting floppy image for MartyPC
python tools\mkboot.py desolate-boot.com x-martypc\media\floppies\desolate.img
if errorlevel 1 goto Failed

del desolate-boot.com
echo BUILD SUCCESS
exit /b 0

:Failed
echo BUILD FAILED
exit /b 1
