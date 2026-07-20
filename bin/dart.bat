@echo off
REM FlutterWrapper dart entry point.
REM Android Studio Flutter plugin never calls this directly (it uses
REM bin/cache/dart-sdk/bin/dart.exe for the analysis server, see
REM docs/flutter-plugin.md section 5.4). This wrapper exists only for
REM users/tools that invoke <sdk>/bin/dart.bat explicitly.
REM
REM Forwards all arguments to dart.ps1 which handles WSL forwarding.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dart.ps1" %*
exit /b %ERRORLEVEL%
