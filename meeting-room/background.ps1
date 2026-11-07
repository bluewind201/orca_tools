# AI 팀 회의실을 창 없이 백그라운드로 실행하고, Windows 로그인 때 자동으로 시작되게 합니다.
#   start  : (처음이면 설치) → 기존 실행 정리 → 숨김 실행 → 자동 시작 등록
#   stop   : 실행 중지 → 자동 시작 해제
#   status : 실행 여부 확인
param([ValidateSet('start', 'stop', 'status')][string]$Action = 'start', [switch]$Quiet)

$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$server = Join-Path $dir 'server.mjs'
$log = Join-Path $dir 'meeting-room.log'
$startup = Join-Path ([Environment]::GetFolderPath('Startup')) 'paseo-meeting-room.vbs'
$port = if ($env:MEETING_ROOM_PORT) { $env:MEETING_ROOM_PORT } else { 6769 }

function Say($msg) { if (-not $Quiet) { Write-Host $msg } }

function Get-RoomProcs {
  Get-CimInstance Win32_Process -Filter "Name='node.exe' OR Name='cmd.exe'" |
    Where-Object { $_.CommandLine -and $_.CommandLine.Contains($server) }
}

function Stop-Room {
  # Stop the restart loop (cmd.exe) first, then node, so nothing restarts it.
  Get-RoomProcs | Sort-Object { $_.Name -ne 'cmd.exe' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

function Test-Room {
  try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 "http://localhost:$port/healthz").StatusCode -eq 200 } catch { $false }
}

switch ($Action) {
  'start' {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js가 필요해요. https://nodejs.org 에서 LTS를 설치한 뒤 다시 실행하세요.' }
    if (-not (Test-Path (Join-Path $dir 'node_modules\@getpaseo\cli'))) {
      Say '[회의실] 처음 실행이라 패키지를 설치하는 중...'
      $env:ONNXRUNTIME_NODE_INSTALL = 'skip'
      Push-Location $dir
      try { & npm install --omit=dev; if ($LASTEXITCODE) { throw 'npm install 실패' } } finally { Pop-Location }
    }
    & node (Join-Path $dir 'setup-gemini.mjs')

    Stop-Room
    if ((Test-Path $log) -and (Get-Item $log).Length -gt 5MB) { Remove-Item $log -Force }
    # Restart node if it ever exits, waiting 5 seconds between tries.
    $loop = "for /l %i in () do (node `"$server`" >> `"$log`" 2>&1 & ping -n 6 127.0.0.1 >nul)"
    Start-Process -FilePath cmd.exe -ArgumentList "/d /c $loop" -WorkingDirectory $dir -WindowStyle Hidden

    # Auto start at Windows sign-in (UTF-16 so a Korean user folder name survives)
    $vbs = 'CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""' + $PSCommandPath + '"" start -Quiet", 0, False'
    Set-Content -Path $startup -Value $vbs -Encoding Unicode

    $ok = $false
    for ($i = 0; $i -lt 15 -and -not $ok; $i++) { Start-Sleep -Seconds 1; $ok = Test-Room }
    if ($ok) { Say "[회의실] 백그라운드에서 실행 중: http://localhost:$port  (이 창은 닫아도 돼요)" }
    else { Say "[회의실] 아직 응답이 없어요. 로그를 확인하세요: $log" }
    Say '[회의실] Windows에 로그인하면 자동으로 다시 시작돼요. 끄려면 meeting-room-off.cmd'
  }
  'stop' {
    Stop-Room
    if (Test-Path $startup) { Remove-Item $startup -Force }
    Say '[회의실] 껐어요. 자동 시작도 해제했어요.'
  }
  'status' {
    $procs = @(Get-RoomProcs | Where-Object Name -eq 'node.exe')
    if (Test-Room) { Say "[회의실] 실행 중 (node 프로세스 $($procs.Count)개): http://localhost:$port" } else { Say '[회의실] 꺼져 있어요.' }
    Say ("[회의실] 자동 시작: " + $(if (Test-Path $startup) { '켜짐' } else { '꺼짐' }))
  }
}
