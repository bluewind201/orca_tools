@echo off
chcp 65001 >nul
rem AI 팀 회의실을 이 PC에서 실행합니다 (이미 설치된 Paseo Desktop/CLI와 함께 사용).
rem 처음 한 번은 필요한 패키지를 받고 Gemini를 Paseo에 등록합니다.
cd /d "%~dp0meeting-room"
where node >nul 2>nul || (echo Node.js가 필요해요: https://nodejs.org 에서 LTS 설치 후 다시 실행하세요. & pause & exit /b 1)
if not exist node_modules\@getpaseo\cli (
  echo [setup] 패키지 설치 중...
  set ONNXRUNTIME_NODE_INSTALL=skip
  call npm install --omit=dev || (pause & exit /b 1)
)
node setup-gemini.mjs
echo.
echo 회의실: http://localhost:6769   (끄려면 이 창을 닫으세요)
node server.mjs
pause
