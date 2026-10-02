@echo off
REM Double-cliquer pour lancer l'audit (demande l'elevation administrateur).
cd /d "%~dp0"
powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0Audit-Poste-Windows.ps1\"'"
