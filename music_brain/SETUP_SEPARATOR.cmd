@echo off
setlocal
cd /d "%~dp0.."
if not exist ".tools\music-separator\Scripts\python.exe" (
  ".venv\Scripts\python.exe" -m venv ".tools\music-separator"
  if errorlevel 1 exit /b 1
)
".tools\music-separator\Scripts\python.exe" -m pip install torch==2.5.1 torchaudio==2.5.1 --index-url https://download.pytorch.org/whl/cu124
if errorlevel 1 exit /b 1
".tools\music-separator\Scripts\python.exe" -m pip install demucs==4.0.1 scipy soundfile
if errorlevel 1 exit /b 1
pause
