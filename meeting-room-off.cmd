@echo off
chcp 65001 >nul
rem 백그라운드 회의실을 끄고 자동 시작을 해제합니다.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0meeting-room\background.ps1" stop
pause
