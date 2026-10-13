@echo off
setlocal
title Jentra OS Private Database Input
echo Enter the existing Supabase DATABASE password only in the hidden local prompt.
echo Leave the optional OpenAI key prompt blank for concurrency and load testing.
echo Keep every credential out of chat. No owner token is requested here.
echo This window will retain a public result code if setup fails.
pwsh.exe -NoProfile -ExecutionPolicy RemoteSigned -Command "$taskHelper = Join-Path '%~dp0' '..\scripts\wave5\prepare_private_runtime_inputs_20261013_r5.ps1'; if ((Get-FileHash -LiteralPath $taskHelper -Algorithm SHA256).Hash.ToLowerInvariant() -ne '1453ff6221728ec221f4688c342f9115f9433550bf8a358432b3ec4f69488056') { Write-Host 'PRIVATE_HELPER_SOURCE_CHANGED'; exit 1 }; & $taskHelper"
set "JENTRA_INPUT_RESULT=%ERRORLEVEL%"
echo.
echo Private input helper exit code: %JENTRA_INPUT_RESULT%
echo Share only this exit code or the public failure code with Codex.
echo Keep passwords and keys private.
pause
exit /b %JENTRA_INPUT_RESULT%
