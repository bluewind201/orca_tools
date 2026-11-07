@echo off
chcp 65001 >nul
rem AI 팀 회의실을 창 없이 백그라운드로 켜고, 로그인할 때 자동으로 켜지게 합니다.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0meeting-room\background.ps1" start
pause
