@echo off
REM FlutterWrapper entry point.
REM Android Studio spawns this as <sdk>/bin/flutter.bat <args>.
REM Forwards all arguments to flutter.ps1 which handles WSL forwarding.
REM
REM Do not add logic here; .bat is hard to debug. Keep it a one-liner.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0flutter.ps1" %*
exit /b %ERRORLEVEL%
