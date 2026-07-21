@echo off
REM fw.bat - FlutterWrapper v3 Unified CLI entry point
REM
REM Usage: fw <command> [options]
REM   fw doctor              Full diagnostic check
REM   fw repair <module>     Repair a specific component
REM   fw provider            Show detected SDK providers
REM   fw flutter current     Show current Flutter version
REM   fw flutter use <ver>   Switch Flutter version
REM   fw status              Quick environment summary
REM   fw version             Show FlutterWrapper version
REM
REM Delegates to bin\fw.ps1 for all logic.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fw.ps1" %*
