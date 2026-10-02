@echo off
REM ============================================================
REM  Demarrer-Audit.cmd  -  Audit de securite (LECTURE SEULE)
REM  Sur un PC Windows client : clic droit > Executer en tant
REM  qu'administrateur. L'audit ne modifie rien.
REM ============================================================
cd /d "%~dp0"
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo.
  echo  [!] Relancez ce fichier par un CLIC DROIT ^> "Executer en tant qu'administrateur".
  echo.
  pause
  exit /b 1
)
echo Lancement de l'audit (lecture seule)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0audit-windows.ps1"
echo.
pause
