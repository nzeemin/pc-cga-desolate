@echo off
rem Start MartyPC booting desolate.img (built by !build.cmd)
if not exist x-martypc\media\floppies\desolate.img (
  echo desolate.img not found, run !build.cmd first
  exit /b 1
)
cd x-martypc
start martypc.exe --auto-poweron --config_file martypc-desolate.toml -m fd:0:media/floppies/desolate.img
