@echo off
chcp 65001 >nul
set "CATALOG_PY=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
if exist "%CATALOG_PY%" (
  "%CATALOG_PY%" "%~dp0catalog.py" build
) else (
  python "%~dp0catalog.py" build
)
pause
