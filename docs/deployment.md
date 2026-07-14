 # 배포 가이드 (홈서버: WSL2 + Docker + Jenkins + Tailscale)

recorme 백엔드를 집 서버 PC(Windows 10)에 배포하는 실전 절차서다. 각 Phase 는
shrimp task 와 1:1 대응한다. **⚠️ 표시는 "가이드 예시와 실제 프로젝트가 달라 그대로 하면
터지는 지점"**이니 반드시 지킬 것.

## 목표 아키텍처

```
[서버 PC: Windows 10] → WSL2 Ubuntu → Docker
   ├─ postgres:18      (recorme DB, Flyway V1~V17 자동 적용, 포트 외부 미노출)
   ├─ backend (Spring) :8080
   ├─ jenkins          :9090  (수동 "지금 빌드" 버튼 → 빌드·배포)
   └─ (ollama)         :11434  ← 보류(하드웨어 한계), Gemini 사용
[클라우드 그대로]  Supabase Auth · FCM · Gemini API
[폰(Z Flip3)]  Tailscale VPN → 서버 :8080
```

- **네트워킹은 Tailscale**: 이중 공유기·포트포워딩·CGNAT를 회피하고 외부에 포트를 열지 않는다.
- **Ollama 보류**: i5-2400(AVX2 미지원·GPU 없음)은 멀티모달 CPU 추론이 분당 단위로 느리다.
  기본 **Gemini** 사용(`LlmClient` 추상화라 언제든 전환). 하루 1건이면 무료 등급으로 충분.
- 저장소: `https://github.com/KimMonkey2945/recorme.git` (branch `main`).

## 🔄 서버 재기동 & 현재 배포 상태 (전원 껐다 켤 때 필독)

### 현재 배포된 것 (2026-07-03 기준)
- WSL2 Ubuntu + Docker 컨테이너: **`recorme-db`(postgres:18) + `recorme-backend`(:8080) 가동 중**.
  (Jenkins·ollama는 아직 미구성.)
- 데이터는 Docker **명명 볼륨에 디스크 영속**: `recorme_pgdata`(일기 DB), `recorme_uploads`(사진).
- 폰 접속: **Tailscale HTTP** — `API_BASE_URL=http://<서버 Tailscale IP>:8080`.
- 앱: Z Flip3에 릴리즈 APK 설치(**Impeller off**로 영상 재생 안정화, debug 서명).
- 클라우드 그대로: Supabase Auth · Gemini · FCM.

### ❓ 전원 꺼도 되나? → 네, 데이터 안전. 셋업 다시 안 해도 됩니다.
일기·사진·`deploy/.env`·DB는 전부 **디스크(볼륨/파일)에 남습니다.** clone·시크릿 입력·DB 마이그레이션·
앱 빌드를 **다시 할 필요 없습니다.** 그냥 전원 꺼도 되고, 정중히 내리려면:
```bash
cd ~/server/recorme
docker compose --env-file deploy/.env -f deploy/docker-compose.yml stop
```

### 전원 켠 뒤 재기동 절차 (⚠️ 자동시작 미구성 상태라 수동 1스텝)
1. **Ubuntu 터미널을 연다** → WSL 기동 → systemd가 Docker 시작 → `restart: unless-stopped`인
   `recorme-db`·`recorme-backend`가 **자동 복귀**.
2. 확인:
   ```bash
   docker ps          # recorme-db, recorme-backend 가 (healthy) 인지
   tailscale status   # 폰·서버 온라인인지. 안 떠 있으면: sudo tailscale up
   ```
3. 폰에서 앱 열어 접속 확인.

> ⚠️ **터미널 창을 닫으면 WSL이 몇 초 뒤 꺼져 서버도 내려갑니다.** 서버를 계속 켜두려면 **터미널을
> 열어둔 채** 두세요. 매번 터미널 안 열고 자동으로 살리려면 아래 **Phase 10(상시화)**를 하면 됩니다.

### 완전 처음부터(새 PC 등) 재구축할 때
아래 **Phase 1~4** + `deploy/.env` 전송(Phase 3 메모) + 앱 빌드(Phase 8) 순서를 그대로 따르면 됩니다.
`deploy/.env`는 git에 없으니 **따로 백업**해두세요(POSTGRES_PASSWORD·SUPABASE_URL·LLM_API_KEY·FCM base64).

### 아직 남은 것 / 알려진 이슈

**앱 이슈·기능 (다음에 손보기)**
- ⏳ **푸시 알림(FCM)**: 동작 이슈 있음 — 나중에 손보기로 보류.
- ✅ **감정 분석 코멘트 누락**: 원인은 `max-tokens`(400) 절단 → JSON 파싱 실패 → NEUTRAL 폴백(빈 코멘트).
  `max-tokens`를 1024로 상향 + Gemini `thinkingBudget=0`(thinking 비활성) + 스키마에서 코멘트·제목을 앞으로
  재배치 + `finishReason=MAX_TOKENS` 경고 로그 추가. 앱 UI도 빈 문자열은 렌더하지 않도록 가드 강화.
  (배포 시 `LLM_API_KEY` 주입 여부 확인 필요 — 무키면 Stub가 항상 빈 코멘트 반환.)
- ✅ **로딩 러닝 영상 2회 재생**: `PENDING→DONE` 전환 시 Stack 오버레이 element 재생성이 원인.
  두 오버레이에 `ValueKey` 부여로 해결. 겸사겸사 러닝 영상 크기도 화면 폭 55%로 축소.
- ✅ **작심삼일 수정 기능 추가**: `PUT /resolutions/{id}`로 진행 중 결심의 제목·알림 시각 수정.
  상세 화면(ONGOING만)에 수정 버튼 + 수정 화면 추가. 시작일 변경은 미지원(삭제 후 재작성).

**배포/인프라 미구성 (선택)**
- ⏭️ Jenkins 자동배포(Phase 6), 통합테스트(Phase 5), 백업(Phase 11), 상시화(Phase 10).

## 시작 전 준비 체크리스트 (사용자가 직접 할 일)

Phase 실행과 별개로, **본인이 미리 준비/결정해야 하는 것**을 한곳에 모았다. 오늘 시작 전에 훑을 것:

- [ ] **`POSTGRES_PASSWORD`** 로 쓸 강한 비밀번호 하나 정하기(새로 생성). → `deploy/.env` 에 넣음(P3).
- [ ] **GitHub PAT 발급** — repo 가 private 이면 서버 `git clone`(P3)부터 인증 필요, Jenkins SCM 자격증명(P6)도
      **같은 PAT 재사용**. GitHub → Settings → Developer settings → Personal access tokens, `repo` 스코프.
      (repo 가 public 이면 clone·폴링에 토큰 불필요.)
- [ ] **보유 시크릿 모으기**(이미 갖고 있는 값): `SUPABASE_URL`(app `supabase_config.dart`),
      `LLM_API_KEY`(`backend/gemini.env`), FCM 서비스계정 JSON → `base64 -w0 fcm.json` 로 인코딩.
- [ ] **폰(Z Flip3)에 Tailscale 앱** 미리 설치 + 서버와 **동일 계정**으로 로그인 준비(P7).
- [ ] (HTTPS 접속을 택할 경우) **Tailscale 관리 콘솔에서 MagicDNS + HTTPS Certificates 활성화**
      (기본 꺼짐 — 안 켜면 `tailscale serve` 가 인증서를 못 받음). login.tailscale.com → DNS 탭(P7).
- [ ] **offsite 백업 대상 결정**(P11, 중요): 이 서버 HDD 는 15년 됨 → 원본·백업 동반 손실 위험.
      rclone→Google Drive 또는 개발 PC 주기 복사 중 하나는 꼭 정할 것.
- [ ] **Windows Update 사용 시간대** 넓게 설정(예고 없는 자동 재부팅 방지, P10).
- [ ] (선택) **릴리즈 키스토어 생성 여부 결정**(P8): Play Store 미배포 + 항상 같은 PC 빌드면 **debug
      폴백으로도 충분**(build.gradle.kts 가 `key.properties` 없으면 debug 서명). 다만 PC 교체/키 재생성 시
      "덮어 설치 업데이트"가 서명 불일치로 실패 → 안심하려면 키스토어 1회 생성·백업.

## 미리 준비된 산출물 (이 저장소에 커밋됨)

| 파일 | 용도 |
|---|---|
| `backend/Dockerfile` | self-contained 멀티스테이지 빌드(호스트 JDK/JAVA_HOME 의존 제거) |
| `backend/.dockerignore` | 빌드 컨텍스트 최소화·시크릿 제외 |
| `deploy/docker-compose.yml` | db + backend + jenkins 오케스트레이션(정합성 교정 반영) |
| `deploy/env.example` | 환경변수 템플릿(→ 서버에서 `deploy/.env`로 복사) |
| `Jenkinsfile` | 백엔드 수동(버튼) 트리거 CI/CD 파이프라인 |
| `Jenkinsfile.app` | 앱(Android APK) 수동(버튼) 빌드 파이프라인 — 산출물로 APK 보관 |
| `app/Dockerfile` | Flutter SDK 내장 앱 빌드 이미지(self-contained, iOS 제외) |
| `app/.dockerignore` | 앱 빌드 컨텍스트 최소화·시크릿 제외 |
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

> **⚠️ private repo 면 clone 부터 인증 필요**: HTTPS clone 시 GitHub 사용자명 + **PAT**(비밀번호 자리)를
> 입력한다. 이 PAT 를 Phase 6 Jenkins SCM 자격증명에도 그대로 재사용한다. public repo 면 토큰 없이 clone 됨.

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

> **⏳ 첫 `--build` 는 오래 걸린다**: i5-2400 에서 멀티스테이지 빌드가 Gradle 의존성
> (anthropic-java·firebase-admin 등)을 전부 받고 컴파일하므로 **첫 빌드 20~40분**도 정상이다. 멈춘 게
> 아니니 기다릴 것. 이후 빌드는 BuildKit 캐시로 훨씬 빨라진다.

확인 사항:
- **⚠️ `SPRING_PROFILES_ACTIVE=cloud` 로 떴는지**(compose 가 강제 주입). local 로 뜨면
  application-local.yml 이 이미지에 없어 기동 실패한다.
- 로그에 **Flyway 가 V1~V17 을 순서대로 적용**했는지(빈 DB 최초 기동 시).
- **⚠️ FCM 자격증명 실측**: 로그에 `Push service = FCM` 이 떠야 한다. `Push service = Stub` 이면
  `FCM_CREDENTIALS`(Base64) 파싱 실패로 폴백된 것 — 값·인코딩 재확인(`base64 -w0` 로 한 줄인지).
  (백엔드 `PushConfig` 는 파일 경로/Base64 둘 다 지원하므로 Base64 문자열도 정상 처리된다.)
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
> ⏳ 첫 실행은 Testcontainers 가 테스트용 postgres 이미지를 pull 하고 Gradle 의존성을 받으므로 느리다(정상).

## Phase 6 — Jenkins 구성 & 파이프라인

> 👉 **클릭·명령 단위로 그대로 따라 하려면 [`deployment-jenkins.md`](./deployment-jenkins.md)** 참조
> (컨테이너 기동 → UI 초기설정 → 자격증명 → 백엔드·앱 잡 생성까지 실행 가이드). 아래는 설계 요약이다.

Jenkins 컨테이너는 **커스텀 이미지(`deploy/jenkins.Dockerfile`) 필수** — 스톡 `lts-jdk21` 에는
docker CLI 도 `docker compose`(v2 플러그인)도 없어 자동배포가 실패한다. 이 이미지는 둘 다 설치하며,
compose 가 자동으로 빌드한다.

```bash
cd ~/server/recorme
# jenkins 이미지 빌드 후 기동. DEPLOY_DIR 은 서버의 실제 deploy 디렉터리(.env 포함).
# --env-file 을 붙여 Phase 4 와 통일(compose 는 파일 전체를 보간하므로, 빠지면 미설정 var 경고·빈값이 뜬다).
DEPLOY_DIR=$(pwd)/deploy docker compose --env-file deploy/.env -f deploy/docker-compose.yml up -d --build jenkins
docker logs recorme-jenkins   # 초기 관리자 비밀번호
```
브라우저 `http://localhost:9090` → 초기 설정.

> **docker.sock 권한**: jenkins 서비스는 compose 에서 `user: root` 로 돌므로 `/var/run/docker.sock`
> 접근 권한이 있다(파이프라인의 `docker build`/`docker compose` 정상 동작). 만약 `permission denied on
> docker.sock` 이 나면 `user: root` 가 유지됐는지 확인.

**시크릿(.env) 접근**: Jenkins 는 `checkout scm` 워크스페이스에 레포를 새로 받는데 `.env` 는
gitignore 라 거기 없다. 그래서 compose 의 jenkins 서비스가 **서버 deploy 디렉터리를 `/deploy-env`
로 읽기 마운트**하고, `DEPLOY_ENV=/deploy-env/.env`(컨테이너 내부 경로)로 통일해 Deploy 스테이지가
`--env-file` 로 시크릿을 공급한다. `DEPLOY_DIR` 환경변수로 좌측 호스트 경로를 서버 실제 경로에 맞춘다.

그 후 파이프라인 잡 생성:
- SCM: recorme 저장소, **자격증명(PAT 또는 deploy key) 등록**(private repo clone용).
- Script Path: `Jenkinsfile`.
- `DEPLOY_ENV` 는 compose 가 이미 `/deploy-env/.env` 로 주입(잡에서 덮어쓸 필요 없음).
- 배포 방법: **"지금 빌드(Build Now)" 버튼**을 누르면 최신 main 을 checkout → 이미지 빌드 → backend
  컨테이너 무중단 갱신. 배포하고 싶을 때만 한 번 누른다.
- 검증: 코드 push 후 "지금 빌드" 클릭 → 빌드·배포가 성공하는지.

**왜 수동(버튼) 트리거인가**: 개인 프로젝트라 "원할 때 한 번 눌러 배포"가 자동 폴링보다 예측 가능하고
서버 부하도 없다. (서버를 외부에 열지 않는 Tailscale 구성상 GitHub 웹훅도 못 쓴다.) 나중에 자동
배포를 원하면 `Jenkinsfile` 의 `triggers { pollSCM('H/5 * * * *') }` 블록을 되살리면 된다.

> 참고: 최초 bring-up(`up -d db backend`)은 Phase 4 에서 수동으로 하고, 이후 backend 갱신만 Jenkins 가
> `up -d --no-deps --no-build backend` 로 처리한다. db 가 내려가 있으면 backend 가 재시작 루프에 빠질 수
> 있으니 db·jenkins 는 항상 떠 있게 둔다(`restart: unless-stopped`).

## Phase 6.5 — (선택) 앱(Android APK) 빌드 잡

백엔드와 **같은 Jenkins·docker 소켓**을 써서, 버튼 하나로 서명된 APK 를 만드는 잡을 추가한다.
빌드는 `app/Dockerfile`(Flutter SDK 내장 이미지) *안*에서 일어나므로 **서버에 Flutter·Android SDK 를
설치할 필요가 없다**(백엔드와 같은 self-contained 철학). **iOS 는 macOS 가 필요해 제외** — iOS 는
Codemagic(`codemagic.yaml`)을 그대로 쓴다.

> ⚠️ **앱 잡은 "APK 생성"까지가 끝이다.** 백엔드처럼 서버에 자동 반영되는 게 아니라, 빌드된 APK 를
> Jenkins **Artifacts** 에서 내려받아 **폰에 수동 설치**한다(Jenkins 는 폰에 앱을 밀어넣지 못한다).

**(권장) 릴리즈 서명 자격증명 등록 (1회):** 안 하면 debug 서명으로 빌드되는데, 빌드마다 debug 키가
달라 **"덮어 설치 업데이트"가 서명 불일치로 실패**한다(새로 설치만 가능). 업데이트를 유지하려면 릴리즈
키스토어(Phase 8 에서 만드는 `recorme-release.jks`)와 `key.properties` 를 Jenkins 자격증명으로 등록한다.

- Jenkins → **Manage Jenkins → Credentials → (global) → Add Credentials** 에서 **Secret file** 2개:
  - `recorme-key-properties` ← 값 채운 `app/android/key.properties` 파일
  - `recorme-release-keystore` ← `recorme-release.jks` 파일
- `key.properties` 의 `storeFile=recorme-release.jks` 로 둔다(빌드가 `android/app/` 에 주입한다).

**잡 생성 & 실행:**
- 새 **Pipeline** 잡 생성 → SCM: recorme 저장소(백엔드 잡과 같은 PAT 자격증명 재사용), **Script Path:
  `Jenkinsfile.app`**.
- **"파라미터와 함께 빌드(Build with Parameters)"** 클릭 →
  - `API_BASE_URL`: 서버 주소(포트까지, `/api/v1` 없이). 예: `http://100.x.y.z:8080`.
  - `RELEASE_SIGNING`: 자격증명을 등록했으면 켜둔 채로. 미등록이면 꺼서 debug 빌드.
- 빌드 성공 후 이 빌드의 **Artifacts → `artifact/app-release.apk`** 내려받기 → 폰 전송·설치.

> ⏳ **첫 빌드는 느리다**: cirruslabs/flutter 이미지 pull(수 GB) + pub get + Android Gradle 의존성
> 다운로드까지 겹쳐 i5-2400 에선 오래 걸린다(정상). 이후엔 이미지·pub·gradle 캐시로 훨씬 빨라진다.
> `app/Dockerfile` 의 베이스 태그가 `stable` 이라 Dart `^3.10.x` 와 어긋나 깨지면 버전 태그로 고정할 것.

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
  **⚠️ 선행 조건**: Tailscale 관리 콘솔(login.tailscale.com) **DNS 탭에서 MagicDNS + HTTPS
  Certificates 를 활성화**해야 한다(기본 꺼짐). 안 켜면 `serve` 가 인증서를 발급받지 못한다.
- (기본) HTTP: `API_BASE_URL=http://100.x.y.z:8080`. 이미 커밋된 network_security_config 가
  cleartext 를 허용하므로 릴리즈 앱에서도 동작(콘솔 설정 불필요).

> ⚠️ `serve` 는 **Tailnet 내부 전용**(내 기기들만 접근). 위 두 방식 모두 **Tailscale 이 깔린 기기에서만**
> 닿는다. 낯선 사용자·앱스토어 심사관은 접근 불가 → 아래 Funnel 필요.

## 공개 노출 (Tailscale Funnel) — 앱스토어 배포/외부 사용자용

앱스토어(비공개) 배포 시 **Apple 심사관이 실기기에서 로그인·기능을 직접 테스트**한다. 백엔드가 Tailnet
내부 전용이면 심사관 폰에서 못 닿아 **로그인 실패 → 리젝**된다. 서버를 옮기지 않고 홈서버를 그대로 둔 채
**공개 인터넷 HTTPS 로 노출**하려면 `tailscale funnel` 을 쓴다. (`serve`=내부, `funnel`=공개)

**⚠️ 선행: 공개 노출 전 보안 조치를 먼저 완료할 것** — rate limiting(구현됨: `RateLimitFilter`),
Jenkins 포트 로컬 바인딩(`deploy/docker-compose.yml` — `127.0.0.1:9090`), LLM 비용 상한(구현됨:
일일 확정 한도·미래/과거 날짜 검증). 상세는 보안 검토 결과 참조.

**F-1. 관리 콘솔(login.tailscale.com):**
- DNS 탭: **MagicDNS ON + HTTPS Certificates ON**(serve 와 동일 선행 조건).
- Access Controls(ACL): 서버 노드에 `funnel` 속성 부여.
  ```json
  "nodeAttrs": [{ "target": ["<서버-호스트 또는 tag>"], "attr": ["funnel"] }]
  ```

**F-2. 서버에서 Funnel 켜기**(tailscaled 가 도는 곳 = §교정2 처럼 WSL 안 권장):
```bash
tailscale funnel --bg 8080          # https://<host>.<tailnet>.ts.net → http://127.0.0.1:8080
tailscale funnel status             # 공개 URL·매핑 확인
```
- Funnel 은 **공개 포트 443/8443/10000 만** 사용(기본 443 → 로컬 8080 프록시).
- ⚠️ tailscaled 가 8080(백엔드)에 닿아야 한다. WSL 안에서 tailscaled·docker 를 함께 두면 `127.0.0.1:8080`
  로 바로 닿는다. tailscaled 가 Windows 호스트면 `tailscale serve --bg --https=443 http://<WSL-IP>:8080`
  로 대상을 명시한 뒤 `tailscale funnel 443 on`.

**F-3. 외부 검증**(Tailscale 없는 회선, 예: 폰 LTE):
```bash
curl https://<host>.<tailnet>.ts.net/api/v1/diaries/shared/<임의토큰>   # 연결됨(404/JSON) 이면 OK
```

**동반 운영 조치(필수):**
- 호스트 방화벽에서 **5432 인바운드 차단**(Funnel 은 8080 만 공개). DB 는 컨테이너 내부망 전용.
- 공개 호스트에서 **`backend/docker-compose.yml` 절대 기동 금지**(5432 를 `record/record/record` 로 여는
  로컬 개발용 파일). 배포는 `deploy/docker-compose.yml` 만 사용.
- `deploy/.env` 의 `POSTGRES_PASSWORD` 를 **강한 무작위 값**으로.
- ⚠️ 서버·컨테이너 **상시 가동 필수** — 특히 **Apple 심사 기간에 서버를 끄면 리젝**된다.

**앱 연결:** iOS 는 `codemagic.yaml` 의 `API_BASE_URL` 을 이 공개 URL 로 교체(`--dart-define` 자동 주입).
Android 는 `build_release` 스크립트에 같은 URL 을 넘긴다.

## 보안 강화 재배포 체크리스트 (서버 컴퓨터에서 실행)

공개 노출 대비 보안 조치(rate limiting·Jenkins 잠금·LLM 비용 상한)를 **git 저장소 코드/설정**에 반영했다.
서버가 이를 **다시 받아 재배포**해야 실제로 적용된다. (실행 경로는 예시 — 서버 실제 레포 경로로 조정)

- [ ] **1. 코드 받기**: `cd ~/server/recorme && git pull`
- [ ] **2. 백엔드 재배포**(rate limit·LLM 상한 적용):
  ```bash
  docker compose --env-file deploy/.env -f deploy/docker-compose.yml up -d --build backend
  ```
  또는 Jenkins "지금 빌드" 버튼. **DB 마이그레이션 없음**(스키마 무변경, 쿼리만 추가) → 재배포만으로 적용.
- [ ] **3. Jenkins 재생성**(포트 로컬 바인딩 `127.0.0.1:9090` 적용):
  ```bash
  docker compose --env-file deploy/.env -f deploy/docker-compose.yml up -d jenkins
  ```
  `jenkins_home` 볼륨 유지(설정·잡 보존). ⚠️ 이후 **타 PC 에서 `서버IP:9090` 접속 불가** → SSH 터널로만:
  `ssh -L 9090:127.0.0.1:9090 <서버>` 후 `http://localhost:9090`.
- [ ] **4. `deploy/.env` 점검**: `POSTGRES_PASSWORD` 강한 값 권장(⚠️ 이미 초기화된 DB 는 `.env` 만 바꿔도
  안 바뀜 — 컨테이너에서 `ALTER USER recorme PASSWORD '...';` 후 `.env` 동기화). `SUPABASE_URL`·`LLM_API_KEY`·
  `FCM_CREDENTIALS` 존재 확인.
- [ ] **5. 공개 노출**: 위 "공개 노출 (Tailscale Funnel)" 절차(F-1~F-3) 수행 → 공개 URL 확보.
- [ ] **6. 검증**: Tailscale 없는 회선에서 `curl https://<host>.<tailnet>.ts.net/api/v1/diaries/shared/x` 연결 확인.
  rate limit 은 무인증 경로 빠른 반복 호출 시 429 확인(정상 사용 무영향).
- [ ] **7. 방화벽·운영 규율**: 호스트 5432 인바운드 차단, `backend/docker-compose.yml` 기동 금지,
  **심사 기간 서버 상시 가동**.

> 참고: 앱 코드 변경(있을 경우)은 서버가 아니라 **빌드 파이프라인**(iOS=Codemagic, Android=`build_release`)에서
> `API_BASE_URL` 을 공개 URL 로 주어 재빌드해야 적용된다(서버 재배포와 별개).

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
로그인·기록 CRUD·감정분석 E2E 확인. **키스토어·비밀번호는 (서버가 아닌) 다른 곳에도 백업**(분실 시
같은 앱으로 업데이트 설치가 영영 불가).

> ✅ `recorme-release.jks`·`key.properties` 는 이미 `.gitignore`(`**/*.jks`, `app/android/key.properties`)로
> 제외돼 커밋되지 않는다. (커밋되는 건 `key.properties.example` 템플릿뿐.)

## Phase 9 — FCM 실기기 라이브 검증

`FCM_CREDENTIALS` 주입 상태에서 작심삼일 리마인더/완주 푸시·딥링크·팬아웃을 Z Flip3 에서 확인
(ROADMAP 잔여 검증 ①).

## Phase 10 — 서버 상시화

- Windows: 설정 → 전원 → 절전 "안 함".
- 작업 스케줄러: 로그온 시 `wsl.exe -d Ubuntu -- sleep infinity`(숨김 실행) → 부팅 후 WSL+Docker 자동 기동.
- netplwiz 자동 로그인 → 정전 후 무인 복구.
- compose 의 `restart: unless-stopped` 확인.
- **⚠️ Windows Update 자동 재부팅**: 예고 없이 서버를 내릴 수 있다. 설정 → Windows 업데이트 → **사용
  시간(Active hours)을 넓게** 잡아 자동 재부팅을 억제한다.
- **무인 복구 리허설 1회**: 실제로 서버 PC 를 재부팅해 보고, 수동 개입 없이 db·backend·jenkins 가
  자동 기동되고 폰에서 접속되는지 확인한다(자동 로그인 + 스케줄러 + restart 정책이 맞물리는지). 이 리허설
  한 번이 정전·업데이트 재부팅 대비의 전부다.

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

**⭐ offsite 사본 (가장 중요)**: 위 백업은 **원본과 같은 디스크**에 저장된다. 이 서버 HDD 는 15년 된
물건이라 **디스크가 죽으면 일기 데이터와 백업이 함께 사라진다**. recorme 는 개인 일기라 데이터가 곧
전부이므로, 덤프를 반드시 **서버 밖**으로 복사한다(3-2-1 까진 아니어도 최소 "2-1").
```bash
# 예1) rclone 으로 Google Drive 업로드 (사전 `rclone config` 로 gdrive 리모트 등록)
rclone copy ~/backups gdrive:recorme-backups --include "*.dump" --include "*.tgz"
# 예2) 개발 PC 로 주기 복사 (scp/rsync) — 최소한 이거라도
```
- 위 백업·offsite 복사를 **cron 등록** + 로그 로테이션(오래된 백업 정리 포함).
- **복원 리허설 1회**: 위 복원 절차를 실제로 한 번 돌려 데이터가 살아나는지 확인해야 백업을 신뢰할 수 있다.

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
