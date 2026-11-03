# AI 팀 회의 시작 프롬프트

Orca(PC 앱, 브라우저, 모바일 어디서든)에서 프로젝트 작업공간을 열고 **Claude 에이전트**를 하나 시작한 다음, 아래 내용을 붙여 넣으세요. 맨 위 `목표:` 줄만 바꾸면 됩니다.
이 Claude가 PM(리드)이 되어 다른 AI들에게 일을 나누고, 그 과정이 회의실 페이지(`http://<NAS Tailscale IP>:6769`)에 그대로 보입니다.

---

```text
목표: <여기에 이번 작업 목표를 적어주세요. 예: 카페 예약 랜딩 페이지 만들기>

너는 이 프로젝트의 PM이야. Orca orchestration 스킬(`orca-ide skills get orchestration`)을 읽고, 아래 규칙대로 AI 팀을 운영해줘.

1. `orca-ide orchestration run-create --objective "<목표>"`로 이번 회의(Run)를 만든다.
2. 목표를 역할별 작업으로 나눈다. 작업 제목은 반드시 역할 머리말로 시작한다:
   [PM] / [분석] / [디자인] / [개발] / [QA]
   필요 없는 역할은 빼도 되고, 의존 관계는 --deps로 건다.
3. 각 작업은 `orca-ide orchestration worker-start`로 시작하고 --task-title과 --display-name에 같은 역할 머리말을 붙인다. 에이전트 배정:
   - [분석]  → --agent gemini
   - [디자인] → --agent gemini
   - [개발]  → --agent codex
   - [QA]   → --agent claude
   같은 작업공간에서 충돌이 날 작업은 --worktree new-child로 분리한다.
4. 각 작업 spec에는 다음을 꼭 넣는다:
   - 무엇을 만들고 어떤 파일을 건드려도 되는지, 끝났다는 증거가 무엇인지
   - "시작할 때와 중요한 결정마다 `orca-ide orchestration send --type status --subject <요약> --body <내용>`으로 PM에게 상황을 공유할 것"
   - "다른 역할에게 물어볼 게 있으면 `orca-ide orchestration ask`로 PM에게 질문할 것"
5. 팀원 질문은 직접 답하거나, 다른 역할의 작업자에게 `send --to dispatch:<id>`로 전달해서 답을 받아 `reply`로 돌려준다. 이렇게 대화가 오가야 회의실 화면에 보인다.
6. 시작할 때와 마무리할 때 `send --to @all --type status`로 팀 전체에 공지한다.
7. 내가 결정해야 할 일(비용, 방향 전환, 되돌리기 어려운 작업)은 진행하지 말고 나에게 먼저 물어본다.
8. 모든 작업이 끝나면 작업별 결과, 증거, 남은 문제를 정리해서 보고한다.
```

---

## 역할 바꾸기

역할 이름, 색, 이모지, 인식 단어는 NAS의 `/docker/orca/home/meeting-room/roles.json`에서 고칠 수 있어요. 저장 후 페이지를 새로고침하면 바로 반영됩니다. 예를 들어 "마케터" 역할을 추가하려면 `roles` 목록에 이렇게 한 줄 넣고, 프롬프트에 `[마케팅]` 머리말을 추가하면 됩니다.

```json
{ "id": "marketing", "name": "마케터", "emoji": "📣", "color": "#d4543a", "match": ["마케팅", "marketing"] }
```
