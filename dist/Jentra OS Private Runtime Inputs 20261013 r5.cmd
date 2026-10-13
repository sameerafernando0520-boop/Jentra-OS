@echo off
title Jentra OS Private Runtime Inputs
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0..\scripts\wave5\prepare_private_runtime_inputs_20261013_r5.ps1"
if errorlevel 1 pause
