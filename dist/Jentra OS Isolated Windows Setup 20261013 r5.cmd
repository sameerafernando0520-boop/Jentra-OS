@echo off
title Jentra OS Isolated Windows Setup
echo This creates the already-approved NEW standard account jentra-w5-runtime.
echo Run this file as administrator and handle UAC yourself.
echo Existing Windows sessions, accounts and acceptance stores are preserved.
echo Keep the new Windows password out of chat; enter it only in the hidden prompts.
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0..\scripts\wave5\prepare_native_runtime_profile_20261013_r5.ps1" -Mode Provision
echo.
echo Setup exit code: %ERRORLEVEL%
pause
