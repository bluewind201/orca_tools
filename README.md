# Windows Docker Desktop에 Paseo AI 팀 서버 올리기

Windows PC의 Docker Desktop에서 [Paseo](https://paseo.sh) 데몬을 돌리고, 같은 PC의 브라우저나 폰(Tailscale)으로 지시하는 구성입니다.
AI 팀은 3명입니다: **PM = Gemini**, **개발·리뷰 = Claude**, **디자인 = Codex**.

```
[폰: Paseo 앱] ── Tailscale ──┐
[PC: 브라우저]  ── localhost ──┼──> [Docker Desktop: paseo 컨테이너]
                              │      ├ :6767 Paseo 데몬 + 웹 UI
                              │      ├ :6769 AI 팀 회의실
                              │      ├ Claude Code / Codex / Gemini CLI
                              │      └ /workspace  =  paseo_tools\workspace 폴더
```

| 파일 | 역할 |
|---|---|
| `Dockerfile` | 공식 `ghcr.io/getpaseo/paseo` 이미지 + Claude Code·Codex·Gemini CLI + gh + 회의실 |
| `nas-entrypoint.sh` | 사용자 권한 맞추기, Gemini 등록, 회의실 실행 후 Paseo 시작 (Windows·NAS 공용) |
| `docker-compose.yml` | 포트, 볼륨, 환경변수 (개인 값은 `.env`) |
| `meeting-room/` | AI 팀 회의실 페이지와 [`TEAM_PROMPT.md`](meeting-room/TEAM_PROMPT.md) (3명 팀 지시문) |

## 1. 준비

1. [Docker Desktop](https://www.docker.com/products/docker-desktop/)을 설치하고 실행합니다. 설치 중 **WSL 2 사용**을 켜 두세요.
   Docker Desktop → Settings → General → **Start Docker Desktop when you sign in**을 켜 두면 PC를 켤 때 서버도 같이 켜집니다.
2. [Git for Windows](https://git-scm.com/download/win)를 설치합니다.
3. 폰에서도 쓰려면 PC와 폰에 [Tailscale](https://tailscale.com/download)을 설치하고 같은 계정으로 로그인합니다. PC 트레이의 Tailscale 아이콘에서 PC의 **100.x.y.z** 주소를 확인해 둡니다.

## 2. 설치

PowerShell을 열고 실행합니다. 폴더는 원하는 곳으로 바꿔도 됩니다.

```powershell
cd $HOME
git clone https://github.com/bluewind201/paseo_tools
cd paseo_tools
copy .env.example .env
notepad .env          # PASEO_PASSWORD=원하는비밀번호 로 바꾸고 저장 (PUID/PGID는 1000 그대로)
docker compose up -d --build
docker logs -f paseo  # "[paseo] starting daemon" 이 보이면 성공 (Ctrl+C로 빠져나오기)
```

처음 빌드는 5~10분 걸립니다. Docker Desktop 화면의 **Containers**에서 `paseo`가 초록색이면 실행 중입니다.

## 3. AI와 GitHub 로그인 (한 번만)

```powershell
docker exec -it -u paseo paseo bash -l
```

컨테이너 안에서 차례로 실행합니다. 로그인 링크나 코드가 나오면 브라우저에서 승인합니다.

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

로그인 정보는 `paseo_tools\paseo-home` 폴더에 저장되어 컨테이너를 다시 만들어도 유지됩니다.
Gemini는 Paseo에 기본으로 없어서, 컨테이너가 시작할 때 `paseo-home\.paseo\config.json`에 ACP 방식(`gemini --acp`)으로 자동 등록합니다.
Gemini 로그인이 계속 실패하면 [Google AI Studio](https://aistudio.google.com/apikey)에서 키를 받아 `paseo-home\.gemini\.env`에 `GEMINI_API_KEY=...` 한 줄을 넣어도 됩니다.

## 4. 프로젝트 넣기

`paseo_tools\workspace` 폴더가 컨테이너 안의 `/workspace`입니다. 컨테이너 안에서 클론하는 것을 권장합니다.

```powershell
docker exec -it -u paseo -w /workspace paseo git clone https://github.com/<계정>/<저장소>
```

Windows 탐색기와 VS Code에서도 `workspace` 폴더의 파일이 그대로 보입니다.

## 5. 접속

- **이 PC 브라우저:** `http://localhost:6767` → 비밀번호(`PASEO_PASSWORD`)
- **폰(Paseo 앱):** Tailscale을 켜고 연결 추가 → 직접 연결 → 주소 `<PC의 Tailscale IP>:6767`, 비밀번호 입력
- **QR로 연결(선택):** `docker exec -it -u paseo paseo paseo daemon pair`
- Windows 방화벽 창이 뜨면 **개인 네트워크**만 허용하세요.

## 6. AI 팀 회의실

`http://localhost:6769` (폰에서는 `http://<PC의 Tailscale IP>:6769`). Paseo의 모든 에이전트가 담비로 나타나고, 에이전트끼리 `paseo send`로 메시지를 주고받으면 회의 테이블로 모여 말풍선과 ✉️가 오갑니다.

- 위쪽 선택 상자로 작업공간(프로젝트)별로 볼 수 있습니다.
- 오른쪽 **작업 보드**: 진행 중 / 승인 대기 / 대기 / 답변 완료 / 오류. 지금 쓰는 도구와 마지막 발언이 보입니다.
- **대화 기록**: 사장님 지시, 에이전트끼리의 대화, 각자의 발언.
- 아직 에이전트가 없으면 오른쪽 위 **데모 보기**로 움직임을 먼저 볼 수 있습니다.
- 역할 이름·색은 `paseo-home\meeting-room\roles.json`에서 고칩니다.
- 접근 제한(선택): `.env`에 `MEETING_ROOM_TOKEN=원하는단어` → `http://…:6769/?token=원하는단어`

**팀 작업 시작:** Paseo에서 Gemini 에이전트를 만들고 [`meeting-room/TEAM_PROMPT.md`](meeting-room/TEAM_PROMPT.md)의 프롬프트를 붙여 넣으세요.

## 운영 메모

- **업데이트:** `cd $HOME\paseo_tools; git pull; docker compose build --pull; docker compose up -d`
- **PC가 절전 모드에 들어가면** 서버도 멈춥니다. 오래 맡겨 둘 땐 Windows 설정 → 전원에서 절전을 끄세요.
- **메모리:** Docker Desktop → Settings → Resources에서 메모리를 6GB 이상 주는 것을 권장합니다 (AI 3명 동시 실행).
- **줄바꿈:** 저장소에 `.gitattributes`가 있어 Windows에서 받아도 스크립트가 LF로 유지됩니다. 예전에 받은 폴더에서 `bad interpreter` 오류가 나면 이미지를 다시 빌드하면 됩니다 (빌드할 때 자동으로 고칩니다).
- **보안:** 공유기에서 6767, 6769 포트를 열지 마세요. `paseo-home`에는 AI 로그인 정보가 있으니 공개 백업이나 클라우드 공유 폴더에 넣지 마세요.

---

## 부록: 시놀로지 NAS에 올리는 경우

같은 파일로 NAS에서도 돌릴 수 있습니다. 다른 점만 적습니다.

- SSH에서 `id`로 uid/gid를 확인해 `.env`에 `PUID=1026`, `PGID=100`처럼 넣습니다.
- 위치는 `/volume1/docker/paseo_tools`, 명령 앞에 `sudo`를 붙입니다.
- 로그에 `cannot write`가 보이면 안내된 `synoacltool -del`과 `chown` 명령을 실행하고 다시 시작합니다.
- 접속 주소는 NAS의 Tailscale IP입니다. DS225+ 기본 2GB 메모리는 빠듯해 6GB 이상을 권장합니다.
- 예전 Orca 구성은 `git checkout f20b0c4`에 남아 있습니다.
