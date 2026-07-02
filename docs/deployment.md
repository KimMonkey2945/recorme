# 배포 가이드 (홈서버: WSL2 + Docker + Jenkins + Tailscale)

recorme 백엔드를 집 서버 PC(Windows 10)에 배포하는 실전 절차서다. 각 Phase 는
shrimp task 와 1:1 대응한다. **⚠️ 표시는 "가이드 예시와 실제 프로젝트가 달라 그대로 하면
터지는 지점"**이니 반드시 지킬 것.

## 목표 아키텍처

```
[서버 PC: Windows 10] → WSL2 Ubuntu → Docker
   ├─ postgres:18      (recorme DB, Flyway V1~V10 자동 적용, 포트 외부 미노출)
   ├─ backend (Spring) :8080
   ├─ jenkins          :9090  (pollSCM 5분 → 자동 빌드·배포)
   └─ (ollama)         :11434  ← 보류(하드웨어 한계), Gemini 사용
[클라우드 그대로]  Supabase Auth · FCM · Gemini API
[폰(Z Flip3)]  Tailscale VPN → 서버 :8080
```

- **네트워킹은 Tailscale**: 이중 공유기·포트포워딩·CGNAT를 회피하고 외부에 포트를 열지 않는다.
- **Ollama 보류**: i5-2400(AVX2 미지원·GPU 없음)은 멀티모달 CPU 추론이 분당 단위로 느리다.
  기본 **Gemini** 사용(`LlmClient` 추상화라 언제든 전환). 하루 1건이면 무료 등급으로 충분.
- 저장소: `https://github.com/KimMonkey2945/recorme.git` (branch `main`).

## 미리 준비된 산출물 (이 저장소에 커밋됨)

| 파일 | 용도 |
|---|---|
| `backend/Dockerfile` | self-contained 멀티스테이지 빌드(호스트 JDK/JAVA_HOME 의존 제거) |
| `backend/.dockerignore` | 빌드 컨텍스트 최소화·시크릿 제외 |
| `deploy/docker-compose.yml` | db + backend + jenkins 오케스트레이션(정합성 교정 반영) |
| `deploy/env.example` | 환경변수 템플릿(→ 서버에서 `deploy/.env`로 복사) |
| `Jenkinsfile` | pollSCM 5분 CI/CD 파이프라인 |
| `app/.../res/xml/network_security_config.xml` | Tailscale HTTP(cleartext) 허용 |
| `app/android/key.properties.example` | 릴리즈 서명 키 템플릿 |
| `app/scripts/build_release.{ps1,sh}` | API_BASE_URL 주입 릴리즈 빌드 |

---

## Phase 1 — WSL2 기본 세팅

```bash
# 1) systemd 활성화 (Docker 자동시작에 필요)
sudo tee /etc/wsl.conf > /dev/null <<'EOF'
[boot]
systemd=true
EOF
```
Windows cmd 에서 `wsl --shutdown` 후 Ubuntu 재실행.
```bash
# 2) 패키지 업데이트
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git ca-certificates gnupg
```

## Phase 2 — Docker Engine 설치 (WSL 내)

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```
터미널 재접속 후 `docker run hello-world` 로 검증.

## Phase 3 — 저장소 클론 & 시크릿 배치

```bash
mkdir -p ~/server && cd ~/server
git clone https://github.com/KimMonkey2945/recorme.git
cd recorme
cp deploy/env.example deploy/.env
```
`deploy/.env` 를 편집해 값 채우기. **⚠️ 정합성 핵심:**
- 데이터소스 var 는 **`DB_URL` / `DB_USER` / `DB_PASSWORD`** (SPRING_DATASOURCE_* 아님).
- `SUPABASE_URL` 필수(앱의 supabase_config.dart 와 동일 프로젝트).
- `LLM_API_KEY` 는 로컬 `gemini.env` 의 키를 그대로.
- `FCM_CREDENTIALS` 는 서비스계정 JSON 을 Base64 로: `base64 -w0 fcm.json` 결과를 붙여넣기.
- `POSTGRES_*` 만 채우면 `DB_USER/DB_PASSWORD` 는 자동 폴백(단일 진실원). DB 이름은 `recorme` 로 일치.

## Phase 4 — DB + 백엔드 기동 & Flyway 검증

`--env-file deploy/.env` 를 명시해 `${...}` 치환 시크릿을 확실히 공급한다(실행 위치·compose 버전에
따른 `.env` 자동로드 모호성 제거).

```bash
cd ~/server/recorme
docker compose --env-file deploy/.env -f deploy/docker-compose.yml up -d db
docker compose --env-file deploy/.env -f deploy/docker-compose.yml up -d --build backend
docker compose --env-file deploy/.env -f deploy/docker-compose.yml logs -f backend
```
확인 사항:
- **⚠️ `SPRING_PROFILES_ACTIVE=cloud` 로 떴는지**(compose 가 강제 주입). local 로 뜨면
  application-local.yml 이 이미지에 없어 기동 실패한다.
- 로그에 **Flyway 가 V1~V10 을 순서대로 적용**했는지(빈 DB 최초 기동 시).
- 파일 업로드 시 명명 볼륨 `recorme_uploads`(→ `/app/var/storage`)에 저장되는지(**⚠️ STORAGE_ROOT 경로 일치**).
- **⚠️ 데이터 안착 확인**: `docker exec recorme-db sh -c 'echo $PGDATA'` → `/var/lib/postgresql/data`,
  `docker volume ls | grep recorme` 에 `recorme_pgdata`·`recorme_uploads` 존재.
- 컨테이너 `STATUS` 가 `healthy` 로 뜨는지(`docker ps`).

## Phase 5 — Testcontainers 통합테스트 실행

Docker 가 생겼으니 그동안 보류한 통합테스트를 서버에서 일괄 실행한다(ROADMAP 잔여 검증 ②).
```bash
sudo apt install -y openjdk-21-jdk
cd ~/server/recorme/backend
./gradlew test
```

## Phase 6 — Jenkins 구성 & 파이프라인

Jenkins 컨테이너는 **커스텀 이미지(`deploy/jenkins.Dockerfile`) 필수** — 스톡 `lts-jdk21` 에는
docker CLI 도 `docker compose`(v2 플러그인)도 없어 자동배포가 실패한다. 이 이미지는 둘 다 설치하며,
compose 가 자동으로 빌드한다.

```bash
cd ~/server/recorme
# jenkins 이미지 빌드 후 기동. DEPLOY_DIR 은 서버의 실제 deploy 디렉터리(.env 포함).
DEPLOY_DIR=$(pwd)/deploy docker compose -f deploy/docker-compose.yml up -d --build jenkins
docker logs recorme-jenkins   # 초기 관리자 비밀번호
```
브라우저 `http://localhost:9090` → 초기 설정.

**시크릿(.env) 접근**: Jenkins 는 `checkout scm` 워크스페이스에 레포를 새로 받는데 `.env` 는
gitignore 라 거기 없다. 그래서 compose 의 jenkins 서비스가 **서버 deploy 디렉터리를 `/deploy-env`
로 읽기 마운트**하고, `DEPLOY_ENV=/deploy-env/.env`(컨테이너 내부 경로)로 통일해 Deploy 스테이지가
`--env-file` 로 시크릿을 공급한다. `DEPLOY_DIR` 환경변수로 좌측 호스트 경로를 서버 실제 경로에 맞춘다.

그 후 파이프라인 잡 생성:
- SCM: recorme 저장소, **자격증명(PAT 또는 deploy key) 등록**(private repo pollSCM용).
- Script Path: `Jenkinsfile`.
- `DEPLOY_ENV` 는 compose 가 이미 `/deploy-env/.env` 로 주입(잡에서 덮어쓸 필요 없음).
- 검증: main 에 push → 5분 내 자동 빌드·배포되는지.

**왜 pollSCM(폴링)인가**: 서버를 외부에 열지 않으니(Tailscale) GitHub 웹훅이 서버로 못 들어온다.
5분 폴링이면 개인 프로젝트엔 충분하다.

> 참고: 최초 bring-up(`up -d db backend`)은 Phase 4 에서 수동으로 하고, 이후 backend 갱신만 Jenkins 가
> `up -d --no-deps --no-build backend` 로 처리한다. db 가 내려가 있으면 backend 가 재시작 루프에 빠질 수
> 있으니 db·jenkins 는 항상 떠 있게 둔다(`restart: unless-stopped`).

## Phase 7 — Tailscale 연결

```bash
# WSL 내
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up   # 출력된 링크로 구글 로그인
tailscale ip -4     # 서버의 Tailscale IP (예: 100.x.y.z)
```
폰에도 Tailscale 앱 설치 + 동일 계정 로그인.

**⚠️ Windows 10 주의**: WSL mirrored networking(Windows 11 전용)이 없으므로, **tailscaled 를 WSL
안에서 실행**해 서버 IP 를 WSL 인스턴스에 두는 이 구성이 가장 단순하다. `docker` 가 `0.0.0.0:8080`
에 포트를 게시하므로 폰→WSL Tailscale IP:8080 로 바로 닿는다. tun 장치가 없다는 오류가 나면
`sudo tailscaled --tun=userspace-networking` 로 폴백.

**§교정3 접속 방식 결정(택1):**
- (권장) HTTPS: `sudo tailscale serve --bg 8080` → `https://<host>.<tailnet>.ts.net` 로 접속.
  앱 manifest 손 안 대고 유효 인증서 확보. `API_BASE_URL=https://<host>.<tailnet>.ts.net`.
- (기본) HTTP: `API_BASE_URL=http://100.x.y.z:8080`. 이미 커밋된 network_security_config 가
  cleartext 를 허용하므로 릴리즈 앱에서도 동작.

## Phase 8 — 앱 릴리즈 서명 & 빌드 & 설치

**§교정4 릴리즈 키스토어(개발 PC에서 1회):**
```bash
cd app/android/app   # 또는 원하는 안전한 위치
keytool -genkey -v -keystore recorme-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias recorme
cp ../key.properties.example ../key.properties   # 값 채우기 (gitignore 됨)
```
**빌드(개발 PC):**
```powershell
# Windows
cd app
.\scripts\build_release.ps1 -ApiBaseUrl "https://<host>.<tailnet>.ts.net"
```
```bash
# Linux/macOS/WSL
cd app && ./scripts/build_release.sh "https://<host>.<tailnet>.ts.net"
```
`build/app/outputs/flutter-apk/app-release.apk` → 폰 전송(카톡/드라이브/USB) → 설치.
로그인·기록 CRUD·감정분석 E2E 확인. **키스토어·비밀번호는 안전히 백업**(분실 시 업데이트 불가).

## Phase 9 — FCM 실기기 라이브 검증

`FCM_CREDENTIALS` 주입 상태에서 작심삼일 리마인더/완주 푸시·딥링크·팬아웃을 Z Flip3 에서 확인
(ROADMAP 잔여 검증 ①).

## Phase 10 — 서버 상시화

- Windows: 설정 → 전원 → 절전 "안 함".
- 작업 스케줄러: 로그온 시 `wsl.exe -d Ubuntu -- sleep infinity`(숨김 실행) → 부팅 후 WSL+Docker 자동 기동.
- netplwiz 자동 로그인 → 정전 후 무인 복구.
- compose 의 `restart: unless-stopped` 확인.

## Phase 11 — 백업 & 복원

compose 에 `name: recorme` 가 있어 볼륨은 `recorme_pgdata`·`recorme_uploads` 다(실행 위치 무관).

**백업**
```bash
# DB: 커스텀 포맷(-Fc) → 복원 유연성↑(선택적 복원·병렬). 매일 03:00 cron 권장.
docker exec recorme-db pg_dump -U recorme -Fc recorme > ~/backups/recorme_$(date +%F).dump
# 사진 볼륨(recorme_uploads) tar 백업
docker run --rm -v recorme_uploads:/data -v ~/backups:/b alpine tar czf /b/uploads_$(date +%F).tgz -C /data .
```

**복원**(백엔드 중단 → 복원 → 재기동 순서)
```bash
docker compose -f deploy/docker-compose.yml stop backend
# DB 복원: 기존 객체를 정리하고 덮어씀(--clean --if-exists). db 컨테이너는 떠 있어야 함.
docker exec -i recorme-db pg_restore -U recorme -d recorme --clean --if-exists < ~/backups/recorme_YYYY-MM-DD.dump
# 사진 복원: 볼륨에 tar 풀기
docker run --rm -v recorme_uploads:/data -v ~/backups:/b alpine sh -c "cd /data && tar xzf /b/uploads_YYYY-MM-DD.tgz"
docker compose -f deploy/docker-compose.yml start backend
```
> ⚠️ 덤프에는 `flyway_schema_history` 도 포함된다. 빈 새 DB/볼륨에 복원하면 정합적이나, 이미 Flyway 를
> 돌린 DB 에 겹쳐 복원할 땐 `--clean` 으로 기존 스키마를 먼저 정리해야 충돌이 없다. 백업은 **복원
> 리허설을 한 번 해봐야** 신뢰할 수 있다.
- cron 등록 + 로그 로테이션(오래된 백업 정리 포함).

## Phase 12 — (보류) Ollama 실험

여유 시 compose 의 ollama 블록 주석 해제 → `docker exec recorme-ollama ollama pull qwen2.5vl:3b` →
`deploy/.env` 에 `LLM_PROVIDER=ollama`, `OLLAMA_BASE_URL=http://ollama:11434` → 속도 체감 후 판단.

---

## 트러블슈팅 (조용한 실패 체크리스트)

- **백엔드가 바로 죽음** → 프로파일 확인(`SPRING_PROFILES_ACTIVE=cloud`?), `DB_URL/DB_USER/DB_PASSWORD`
  누락 아닌지, Flyway placeholder 오류 로그 확인.
- **앱이 서버에 연결 안 됨(릴리즈)** → cleartext 차단 가능성. network_security_config 반영됐는지,
  또는 Tailscale HTTPS 로 전환. Tailscale ping 되는지(`tailscale status`).
- **사진이 재배포 후 사라짐** → `STORAGE_ROOT` 가 볼륨 경로(`/app/var/storage`)와 일치하는지.
- **앱 업데이트 설치 실패** → 릴리즈 키 불일치. 항상 같은 `recorme-release.jks` 로 서명.
- **Jenkins 빌드에서 docker 명령 실패** → jenkins 컨테이너에 docker CLI 설치(커스텀 이미지).
