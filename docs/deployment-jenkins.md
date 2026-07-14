# Jenkins 자동화 따라하기 (백엔드 + 앱 APK)

홈서버에 **db + backend 컨테이너까지 가동 완료**된 상태에서, **Jenkins CI/CD 자동화를 처음부터 끝까지
따라 하는** 실행 가이드다. `recorme-jenkins` 컨테이너가 아직 안 떠 있는 지금 상태에서 시작한다.

- 이 문서는 **명령·클릭·입력값·검증**에 집중한다. "왜 이렇게 설계했는가"는 중복 서술하지 않고
  [`docs/deployment.md`](./deployment.md) Phase 6/6.5 와 `Jenkinsfile`·`deploy/docker-compose.yml`
  주석에 위임한다(필요 지점마다 링크).
- 완주하면: **버튼 하나로 백엔드 무중단 재배포**, **버튼 하나로 서명된 Android APK 생성**.

> 표기 약속: 아래 명령의 서버 레포 경로는 `~/server/recorme` 를 가정한다(Phase 3 clone 위치).
> 다른 곳에 clone 했다면 **본인 경로로 바꿔서** 실행할 것.

전체 흐름:

```
0. 전제 확인 → 1. Jenkins 컨테이너 기동 → 2. UI 초기 설정 → 3. GitHub 자격증명 등록
             → 4. 백엔드 잡 생성·첫 배포 → 5. 앱 APK 잡 생성·빌드 → 6. 트러블슈팅 → 7.(선택) 자동화
```

---

## 0. 전제 조건 체크리스트

시작 전 아래가 **모두** 충족됐는지 확인한다(하나라도 안 되면 뒤에서 조용히 실패한다).

- [ ] **Phase 1~4 완료** — WSL2 + Docker 설치, 저장소 clone, `recorme-db` + `recorme-backend`(:8080)
      가동 중. (`docker ps` 로 두 컨테이너 확인. 상세: [`deployment.md`](./deployment.md) Phase 1~4.)
- [ ] **`deploy/.env` 가 서버에 값까지 채워져 존재** — `~/server/recorme/deploy/.env`.
      gitignored 라 clone 으로 안 따라온다. 개발 PC에서 만든 값을 서버로 옮겨 뒀어야 한다
      (Jenkins Deploy 스테이지가 이 파일로 시크릿을 공급한다).
      확인: `test -f ~/server/recorme/deploy/.env && echo OK`.
- [ ] **GitHub PAT 준비** — private 저장소(`KimMonkey2945/recorme`) clone·SCM 자격증명용.
      Phase 3에서 clone 할 때 쓴 PAT 를 **그대로 재사용**한다. (public 이면 생략 가능하나 등록 권장.)
- [ ] **서버 레포 경로 확인** — 아래 명령의 `DEPLOY_DIR=$(pwd)/deploy` 산정 기준이 된다.

---

## 1. Jenkins 컨테이너 기동

Jenkins 는 **커스텀 이미지([`deploy/jenkins.Dockerfile`](../deploy/jenkins.Dockerfile))** 로 띄운다.
스톡 `jenkins/jenkins:lts-jdk21` 에는 `docker` CLI·`docker compose`(v2)·buildx 가 없어 파이프라인의
`docker build`/`docker compose`/BuildKit `--secret` 이 실패하기 때문. compose 가 `--build` 로 자동 빌드한다.

레포 루트에서:

```bash
cd ~/server/recorme
DEPLOY_DIR=$(pwd)/deploy docker compose --env-file deploy/.env -f deploy/docker-compose.yml up -d --build jenkins
```

- **`DEPLOY_DIR=$(pwd)/deploy`** — compose 가 이 경로를 컨테이너 안 `/deploy-env:ro` 로 마운트한다.
  Jenkins 워크스페이스에는 `.env` 가 없으므로(gitignored), 배포 시 시크릿을 여기서 공급한다.
  이 값을 빼면 기본값 `/srv/recorme/deploy` 를 마운트하려다 시크릿이 비어 배포가 실패한다.
- **`--env-file deploy/.env`** — compose 파일 전체의 `${...}` 치환을 채운다(빠지면 미설정 var 경고·빈값).
- **`--build`** — 커스텀 이미지를 처음 빌드한다(최초 1회는 apt 설치로 수 분 소요).

기동 확인:

```bash
docker ps | grep recorme-jenkins        # Up 상태인지
docker logs recorme-jenkins             # 부팅 로그(아래 2단계에서 초기 비밀번호도 여기서 찾는다)
```

> db·backend 컨테이너는 계속 떠 있어야 한다(`restart: unless-stopped`). Jenkins 만 새로 추가하는 것이며
> 기존 두 컨테이너는 건드리지 않는다.

---

## 2. Jenkins UI 접속 & 초기 설정 마법사

### 2-1. 접속

Jenkins 는 보안상 **`127.0.0.1:9090` 호스트 로컬 전용**으로 바인딩돼 있다(root + docker.sock 이라
UI 탈취 시 호스트·DB 전체 장악 위험 → LAN/Tailnet/공개망에 절대 노출하지 않는다).

- **서버 PC에서 직접**: 브라우저로 `http://localhost:9090`.
  (WSL2 는 localhost 포워딩을 지원하므로 Windows 호스트 브라우저에서도 `localhost:9090` 로 닿는다.)
- **다른 PC에서 원격**: SSH 터널로만.
  ```bash
  ssh -L 9090:127.0.0.1:9090 <서버-사용자>@<서버-주소>
  ```
  그 후 로컬 브라우저에서 `http://localhost:9090`.

### 2-2. 초기 관리자 비밀번호로 잠금 해제

첫 화면 "Unlock Jenkins" 에 넣을 초기 비밀번호를 꺼낸다:

```bash
docker exec recorme-jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

(또는 `docker logs recorme-jenkins` 출력에서 `Please use the following password...` 아래 값.)
이 값을 UI 입력창에 붙여넣고 **Continue**.

### 2-3. 플러그인 설치

- **Install suggested plugins** 선택. (Pipeline, Git, Credentials Binding 등 필요한 것이 모두 포함된다.)
- 설치가 끝날 때까지 대기(네트워크에 따라 수 분).

### 2-4. 첫 관리자 계정 생성

- Username / Password / Full name / E-mail 입력 → **Save and Continue**.
- "Instance Configuration" 의 Jenkins URL 은 기본값(`http://localhost:9090/`) 그대로 → **Save and Finish**
  → **Start using Jenkins**.

> ✅ 여기까지 성공하면 Jenkins 대시보드가 뜬다. 컨테이너·계정 셋업은 끝. 이제 잡을 만든다.

---

## 3. GitHub 자격증명(PAT) 등록

파이프라인이 private 저장소를 clone 하려면 자격증명이 필요하다. 한 번 등록해 두면 백엔드·앱 잡이 공용한다.

- 상단 **Manage Jenkins → Credentials → System → Global credentials (unrestricted) → Add Credentials**.
- 입력:
  - **Kind**: `Username and password`
  - **Username**: GitHub 사용자명 (`KimMonkey2945`)
  - **Password**: **PAT** (발급받은 토큰 문자열)
  - **ID**: `github-pat`  ← 잡에서 이 ID로 고른다(기억할 것)
  - Description: 자유(예: `GitHub PAT (clone)`)
- **Create**.

> public 저장소면 이 단계를 건너뛰고 잡에서 Credentials 를 `- none -` 로 둬도 clone 된다. 다만 나중에
> private 전환·rate limit 대비로 등록을 권장한다.

---

## 4. 백엔드 자동배포 파이프라인 잡 (`Jenkinsfile`)

[`Jenkinsfile`](../Jenkinsfile) 은 3-stage(Checkout → Build image → Deploy) 수동 트리거 파이프라인이다.

### 4-1. 잡 생성

- 대시보드 **New Item** → 이름 `recorme-backend` → **Pipeline** 선택 → **OK**.
- 설정 화면에서 **Pipeline** 섹션까지 내려가 아래처럼 채운다:
  - **Definition**: `Pipeline script from SCM`
  - **SCM**: `Git`
  - **Repository URL**: `https://github.com/KimMonkey2945/recorme.git`
  - **Credentials**: `github-pat` (3단계에서 만든 것)
  - **Branch Specifier**: `*/main`
  - **Script Path**: `Jenkinsfile`
- **Save**.

> `DEPLOY_ENV`(시크릿 `.env` 경로)는 compose 가 이미 `/deploy-env/.env` 로 주입하므로 잡에서 따로
> 설정할 필요 없다. 트리거도 비워 둔다(수동 버튼 전용).

### 4-2. 첫 배포 실행

- 잡 화면에서 **지금 빌드(Build Now)**.
- 좌측 빌드 번호(#1) → **Console Output** 으로 진행 확인:
  1. **Checkout** — 최신 `main` 체크아웃.
  2. **Build image** — `docker build -t recorme-backend:latest ./backend`
     (빌드 JDK 는 [`backend/Dockerfile`](../backend/Dockerfile) 안에 내장 — Jenkins 에 JDK/JAVA_HOME 불필요).
  3. **Deploy** — `docker compose ... up -d --no-deps --no-build backend` 로 **backend 컨테이너만 무중단
     재생성**(db·jenkins 는 안 건드림) → dangling 이미지 정리.

> 최초 bring-up(`up -d db backend`)은 Phase 4에서 이미 수동으로 했다. Jenkins 는 그 이후의 **backend
> 갱신**만 담당한다. db 가 내려가 있으면 backend 가 재시작 루프에 빠지니 db·jenkins 는 항상 떠 있게 둔다.

### 4-3. 검증

```bash
docker ps | grep recorme-backend        # 방금 재생성돼 Up (일시) 상태
docker logs --tail 50 recorme-backend   # cloud 프로파일로 정상 기동 로그
```

- 폰(Tailscale) 또는 서버에서 API 응답 확인:
  ```bash
  curl -s http://localhost:8080/api/v1/diaries/shared/anytoken   # 연결됨(404/JSON) 이면 OK
  ```
- ✅ 이후로는 **코드 push → "지금 빌드" 클릭** 만으로 백엔드가 갱신된다.

---

## 5. 앱(Android APK) 빌드 잡 (`Jenkinsfile.app`)

백엔드와 **같은 Jenkins·docker 소켓**으로, 버튼 하나에 서명된 APK 를 만든다. 빌드는
[`app/Dockerfile`](../app/Dockerfile)(Flutter SDK 내장) 안에서 일어나 **서버에 Flutter·Android SDK 설치가
불필요**하다. iOS 는 macOS 가 필요해 제외(Codemagic 사용).

> ⚠️ **앱 잡은 "APK 생성"까지가 끝**이다. 백엔드처럼 서버에 자동 반영되지 않는다. 빌드된 APK 를 Jenkins
> **Artifacts** 에서 내려받아 **폰에 수동 설치**한다(Jenkins 는 폰에 앱을 밀어넣지 못한다).

### 5-1. (권장) 릴리즈 서명 자격증명 등록 — 1회

등록하지 않으면 debug 서명으로 빌드되는데, 빌드마다 debug 키가 달라 **덮어설치 업데이트가 서명 불일치로
실패**한다(새로 설치만 가능). 업데이트를 유지하려면 등록한다.

- **Manage Jenkins → Credentials → System → Global → Add Credentials** 에서 **Kind = `Secret file`** 2개:
  - **ID `recorme-key-properties`** ← 값 채운 `app/android/key.properties` 파일 업로드
  - **ID `recorme-release-keystore`** ← `recorme-release.jks` 파일 업로드 (Phase 8에서 생성)
- `key.properties` 안의 `storeFile=recorme-release.jks` 로 둔다(빌드가 `android/app/` 에 주입한다).

### 5-2. 잡 생성

- **New Item** → 이름 `recorme-app` → **Pipeline** → **OK**.
- **Pipeline** 섹션:
  - **Definition**: `Pipeline script from SCM`, **SCM**: `Git`
  - **Repository URL**: `https://github.com/KimMonkey2945/recorme.git`
  - **Credentials**: `github-pat` (백엔드 잡과 동일 재사용)
  - **Branch Specifier**: `*/main`
  - **Script Path**: `Jenkinsfile.app`
- **Save**.

### 5-3. 빌드 실행

- 잡 화면 **Build with Parameters(파라미터와 함께 빌드)**:
  - **`API_BASE_URL`**: 실기기가 붙을 서버 주소(**포트까지, `/api/v1` 없이**). 예: `http://100.x.y.z:8080`.
    (비우면 Validate 스테이지가 명시적으로 빌드를 실패시킨다.)
  - **`RELEASE_SIGNING`**: 5-1에서 자격증명을 등록했으면 **켠 채로**. 미등록이면 **꺼서** debug 빌드.
- **Build** → Console Output 으로 진행 확인:
  1. **Checkout** → 2. **Validate**(API_BASE_URL 검사) → 3. **Build APK**(BuildKit `--secret` 로 서명 자료
     주입, `docker build --target build ... ./app`) → 4. **Extract APK**(`docker cp` 로 컨테이너에서 추출).

### 5-4. 산출물 내려받기 & 설치

- 빌드 성공 후 해당 빌드 화면 **Artifacts → `artifact/app-release.apk`** 다운로드.
- 파일을 폰으로 전송해 설치(또는 `adb install app-release.apk`).

> ⏳ **첫 빌드는 느리다**: `ghcr.io/cirruslabs/flutter` 이미지 pull(수 GB) + pub get + Android Gradle
> 의존성 다운로드가 겹쳐 i5-2400 에선 오래 걸린다(정상). 이후엔 이미지·pub·gradle 캐시로 빨라진다.

---

## 6. 트러블슈팅 & 단계별 성공 판정

| 증상 | 원인 / 조치 |
|---|---|
| `permission denied on /var/run/docker.sock` | jenkins 서비스가 `user: root` 로 도는지 확인(compose 에 명시됨). |
| `docker: command not found` / `docker compose` 실패 | 커스텀 이미지로 빌드 안 됨 → `up -d --build jenkins` 로 재빌드(`jenkins.Dockerfile`). |
| Deploy 단계 시크릿 빈값·`variable is not set` 경고 | `DEPLOY_DIR=$(pwd)/deploy` 로 기동했는지 + 서버에 `deploy/.env` 존재하는지 확인. |
| backend 가 재시작 루프 | db 가 떠 있는지(`docker ps`) 확인. db·jenkins 는 항상 유지. |
| clone 실패(Authentication failed) | `github-pat` 자격증명의 PAT 유효성·repo 권한 확인. |
| 앱 빌드 `API_BASE_URL 이 비었습니다` | Build with Parameters 에서 서버 주소를 넣고 재실행. |

**완주 체크리스트:**

- [ ] `docker ps` 에 `recorme-jenkins` Up
- [ ] `http://localhost:9090` 대시보드 접속·로그인 성공
- [ ] `github-pat` 자격증명 등록됨
- [ ] `recorme-backend` 잡 첫 빌드 성공 → backend 컨테이너 갱신 확인
- [ ] (앱) `recorme-app` 잡 빌드 성공 → `app-release.apk` Artifacts 다운로드
- [ ] (앱, 권장) `recorme-key-properties`·`recorme-release-keystore` 등록해 릴리즈 서명

---

## 7. (선택) 수동 버튼 → 자동 폴링 전환

기본은 **수동 "지금 빌드" 버튼**이다 — 개인 프로젝트라 "원할 때 한 번 눌러 배포"가 예측 가능하고, 서버를
외부에 열지 않는 Tailscale 구성상 GitHub 웹훅도 못 쓰기 때문.

자동 배포를 원하면 [`Jenkinsfile`](../Jenkinsfile) 의 `pipeline { ... }` 안에 트리거 블록을 되살린다:

```groovy
triggers { pollSCM('H/5 * * * *') }   // 5분마다 main 변경 감지 시 자동 빌드
```

커밋·push 후 백엔드 잡이 자동으로 돈다. (앱 잡은 파라미터가 필요하므로 수동 유지 권장.)

---

**관련 문서**: 전체 배포 절차 [`deployment.md`](./deployment.md) · 파이프라인 정의
[`Jenkinsfile`](../Jenkinsfile) / [`Jenkinsfile.app`](../Jenkinsfile.app) · 오케스트레이션
[`deploy/docker-compose.yml`](../deploy/docker-compose.yml) · Jenkins 이미지
[`deploy/jenkins.Dockerfile`](../deploy/jenkins.Dockerfile)
