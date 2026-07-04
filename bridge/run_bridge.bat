@echo off
setlocal
cd /d "%~dp0"
python bridge.py --config "%~dp0bridge_config.json"
