@echo off
cd /d %~dp0..
python .claude\translation\sync.py status
pause
