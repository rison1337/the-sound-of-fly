@echo off
setlocal
cd /d "%~dp0"
if not exist "..\.venv\Scripts\pythonw.exe" (
  echo Droffel Python environment is missing. See README.md.
  pause
  exit /b 1
)
start "" "..\.venv\Scripts\pythonw.exe" "%~dp0studio.py"
