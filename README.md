# 시놀로지 NAS에 Paseo 서버 올리기 (DS225+)

NAS에서 [Paseo](https://paseo.sh) 데몬을 24시간 돌리고, PC·폰은 Tailscale로 접속해서 지시만 하는 구성입니다.
AI 팀은 3명입니다: **PM = Gemini**, **개발·리뷰 = Claude**, **디자인 = Codex**.

```
[폰: Paseo 앱]  ─┐
[PC: 브라우저/앱] ─┼── Tailscale ──> [NAS: paseo 컨테이너]
                                     ├ :6767 Paseo 데몬 + 웹 UI
                                     ├ :6769 AI 팀 회의실
                                     ├ Claude Code / Codex / Gemini CLI
                                     └ /workspace (git 프로젝트)
```

| 파일 | 역할 |
|---|---|
| `Dockerfile` | 공식 `ghcr.io/getpaseo/paseo` 이미지 + Claude Code·Codex·Gemini CLI + gh + 회의실 |
| `nas-entrypoint.sh` | NAS 사용자 권한(PUID/PGID) 맞추기, Gemini 등록, 회의실 실행 후 Paseo 시작 |
| `docker-compose.yml` | 포트, 볼륨, 환경변수 (개인 값은 `.env`) |
| `meeting-room/` | AI 팀 회의실 페이지와 [`TEAM_PROMPT.md`](meeting-room/TEAM_PROMPT.md) (3명 팀 지시문) |

> 테스트(2026-11-06): Paseo 0.15.2 데몬에 에이전트를 띄워 회의실이 상태·대화를 읽는 것, 컨테이너 기동과 uid 1026 권한 처리, Gemini 자동 등록, 재시작 유지까지 확인했습니다. 실제 Claude·Codex·Gemini 로그인과 NAS 위 빌드는 아래 단계에서 직접 확인이 필요합니다.

---

## Orca에서 옮겨오기 (이미 Orca를 쓰던 NAS)

SSH로 NAS에 접속해서 차례로 실행합니다.

```bash
cd /volume1/docker/orca
sudo docker compose down                 # Orca 컨테이너 정지 (데이터는 home/ 에 그대로 남아요)
git config core.fileMode false
git fetch origin && git reset --hard origin/main
echo 'PASEO_PASSWORD=원하는비밀번호' >> .env   # 웹/앱 접속 비밀번호 (필수)
mkdir -p paseo-home
sudo docker compose up -d --build --remove-orphans
sudo docker logs -f paseo                # "[paseo] starting daemon" 이 보이면 성공 (Ctrl+C로 빠져나오기)
```

- 처음 빌드는 5~10분 걸립니다. 프로젝트 폴더 `workspace/`는 Orca 때 것을 그대로 씁니다.
- Orca 시절 로그인을 옮기고 싶으면(선택) `up` 전에 실행하세요. 안 해도 아래 4번에서 다시 로그인하면 됩니다.
  ```bash
  mkdir -p paseo-home/.claude paseo-home/.config
  cp -a home/.claude/. paseo-home/.claude/ ; cp -a home/.claude.json paseo-home/.claude/ 2>/dev/null
  cp -a home/.codex home/.gemini home/.gitconfig paseo-home/ 2>/dev/null ; cp -a home/.config/gh paseo-home/.config/ 2>/dev/null
  ```
- Orca로 되돌리고 싶으면 `git checkout orca-final` 후 `sudo docker compose up -d --build --remove-orphans` 하면 됩니다.

## 처음 설치하는 경우

1. 패키지 센터에서 **Container Manager**와 **Tailscale**을 설치하고 Tailscale에 로그인합니다. PC와 폰에도 같은 계정으로 Tailscale을 켭니다.
2. SSH에서 `id`로 uid(보통 1026), gid(보통 100)를 확인합니다.
3. 저장소를 받습니다.
   ```bash
   cd /volume1/docker && sudo git clone https://github.com/bluewind201/orca_tools orca && cd orca
   cp .env.example .env && vi .env      # PUID, PGID, PASEO_PASSWORD 채우기
   sudo docker compose up -d --build
   ```

## 4. AI와 GitHub 로그인 (한 번만)

```bash
sudo docker exec -it -u paseo paseo bash -l
```

안에서 차례로 실행합니다. 로그인 링크나 코드가 나오면 PC 브라우저에서 승인합니다.

```bash
claude                       # Claude Code 로그인 후 /exit
codex login --device-auth    # ChatGPT 계정으로 Codex 로그인
NO_BROWSER=true gemini       # Google 로그인. 링크를 열고 받은 코드를 붙여 넣은 뒤 /quit
gh auth login                # GitHub (HTTPS 선택)
git config --global user.name  "이름"
git config --global user.email "메일"
paseo provider ls            # claude, codex, gemini 가 보이면 준비 완료
exit
```

Gemini는 Paseo에 기본으로 없어서, 컨테이너가 시작할 때 `paseo-home/.paseo/config.json`에 ACP 방식(`gemini --acp`)으로 자동 등록합니다.
Gemini 로그인이 계속 실패하면 [Google AI Studio](https://aistudio.google.com/apikey)에서 키를 받아 `paseo-home/.gemini/.env`에 `GEMINI_API_KEY=...` 한 줄을 넣어도 됩니다.

## 5. PC·폰 연결

- **브라우저:** Tailscale을 켜고 `http://100.119.72.114:6767` 을 열어 비밀번호(`PASEO_PASSWORD`)를 넣습니다.
- **Paseo 앱(PC·모바일):** 연결 추가 → 직접 연결 → 주소 `100.119.72.114:6767`, 비밀번호 입력. 폰의 Tailscale이 켜져 있어야 합니다.
- **QR로 연결(선택):** `sudo docker exec -it -u paseo paseo paseo daemon pair` 를 실행하면 QR과 링크가 나옵니다.

## 6. AI 팀 회의실

`http://100.119.72.114:6769` 를 엽니다. Paseo의 모든 에이전트가 담비로 나타나고, 에이전트끼리 `paseo send`로 메시지를 주고받으면 회의 테이블로 모여 말풍선과 ✉️가 오갑니다.

- 위쪽 선택 상자로 작업공간(프로젝트)별로 볼 수 있습니다.
- 오른쪽 **작업 보드**: 진행 중 / 승인 대기 / 대기 / 답변 완료 / 오류. 지금 쓰는 도구와 마지막 발언이 보입니다.
- **대화 기록**: 사장님 지시, 에이전트끼리의 대화, 각자의 발언.
- 아직 에이전트가 없으면 오른쪽 위 **데모 보기**로 움직임을 먼저 볼 수 있습니다.
- 접근 제한(선택): `.env`에 `MEETING_ROOM_TOKEN=원하는단어` → `http://…:6769/?token=원하는단어`

**팀 작업 시작:** Paseo에서 Gemini 에이전트를 만들고 [`meeting-room/TEAM_PROMPT.md`](meeting-room/TEAM_PROMPT.md)의 프롬프트를 붙여 넣으세요.

## 운영 메모

- **업데이트:** `cd /volume1/docker/orca && git pull && sudo docker compose build --pull && sudo docker compose up -d`. 로그인과 프로젝트는 `paseo-home/`, `workspace/`에 있어 유지됩니다.
- **권한 오류:** 로그에 `cannot write`가 보이면 안내된 `synoacltool -del` 과 `chown` 명령을 실행하고 컨테이너를 다시 시작하세요.
- **메모리:** DS225+ 기본 2GB는 빠듯합니다. AI 3명이 동시에 돌면 6GB 이상을 권장합니다.
- **보안:** 6767, 6769 포트를 공유기에서 열지 마세요. DSM 방화벽은 `100.64.0.0/10`(Tailscale)과 내부망만 허용하세요. `paseo-home/`에는 AI 로그인 정보가 있으니 공개 백업에 넣지 마세요.
- 예전 Orca 데이터(`home/`)는 지워지지 않습니다. Paseo가 잘 돌면 나중에 지워도 됩니다.
