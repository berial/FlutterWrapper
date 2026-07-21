@echo off
REM doctor.bat - FlutterWrapper diagnostic tool entry point
REM
REM Usage: flutter-wrapper doctor [options]
REM Options: -quick (fast check), -json (machine-readable)
REM
REM Delegates to bin\doctor.ps1 for all logic.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0doctor.ps1" %*
