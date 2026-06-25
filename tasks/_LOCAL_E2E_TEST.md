# 로컬 웹 E2E 테스트 가이드 — 이메일 가입 → 프로필 → DB 저장 확인

> 목적: 모바일 없이 **Flutter 웹 + 로컬 백엔드 + 로컬 PostgreSQL 18(recorme)**로
> "회원가입/로그인 → 프로필 → `users` 테이블에 정보가 저장되는지" 직접 확인한다.

---

## 0. 전제 (이미 완료된 것)
- 로컬 **PostgreSQL 18** 실행 중, DB/롤 `recorme` 생성됨, `application-local.yml` 연결값 일치
- 백엔드: Flyway `V1__init.sql`(users) 적용 확인됨, Supabase 인증 **ES256/JWKS 검증**으로 전환됨(작업 6)
- 앱: 이메일 가입/로그인 UI + 프로필 화면 구현됨, `AuthInterceptor`가 Supabase access token 첨부

---

## 1. Supabase 콘솔 설정 (사용자, 최초 1회)

대시보드 `https://supabase.com/dashboard/project/wcrlawgpmwxyxohwlegc`

1. **Authentication → Sign In / Providers → Email**: **Enable** ON
2. **Confirm email**:
   - **테스트 편의**: 잠시 **OFF** → 가입 즉시 로그인(메일 확인 불필요). 빠른 반복 테스트에 유리
   - **실제와 동일하게**: ON 유지 → 가입 후 받은 메일의 링크 클릭해야 로그인 가능
3. **Authentication → URL Configuration → Site URL / Redirect URLs**: 웹 테스트 origin 추가
   - 예: `http://localhost:8000` (아래 3번에서 고정 포트로 띄움)
   - 확인 메일 링크/소셜 콜백에 필요

> 참고: 이 프로젝트는 **ES256(JWKS)** 서명. 백엔드는 `https://wcrlawgpmwxyxohwlegc.supabase.co/auth/v1/.well-known/jwks.json`의 공개키로 토큰을 검증한다(secret 불필요).

---

## 2. 백엔드 실행 (터미널 1)

```bash
cd backend
./gradlew bootRun
```
- `http://localhost:8080` 기동, context-path `/api/v1`
- 기동 로그에 `Migrating schema "public" to version "1 - init"` / `Started RecordApplication` 확인
- `application-local.yml`의 `supabase.url=https://wcrlawgpmwxyxohwlegc.supabase.co` 로 JWKS 검증 → **환경변수 주입 불필요**

---

## 3. 앱 웹 실행 (터미널 2)

```bash
cd app
flutter run -d chrome --web-port=8000 --dart-define=API_BASE_URL=http://localhost:8080
```
- 크롬이 `http://localhost:8000`으로 열림
- `--dart-define=API_BASE_URL=http://localhost:8080` → 앱이 백엔드를 `http://localhost:8080/api/v1`로 호출
  (지정 안 하면 기본값 `http://10.0.2.2:8080`은 **안드로이드 에뮬레이터 전용**이라 웹에서 동작 안 함)
- `--web-port=8000` → Supabase Redirect URL과 맞추려고 포트 고정

---

## 4. 테스트 시나리오

### 시나리오 1 — 이메일 회원가입 → DB 저장 확인 ⭐
1. 로그인 화면 → **"이메일로 회원가입"** → 닉네임 / 이메일 / 비밀번호 / 비밀번호 확인 입력 → 가입
2. **Confirm OFF**: 바로 로그인 상태 → 메인(캘린더) 진입
   **Confirm ON**: "메일함을 확인하세요" 안내 화면 → 메일 링크 클릭 → 로그인
3. 메인 상단 앱바의 **프로필 아이콘** 탭 → 프로필 화면 진입
   - 이때 앱이 `GET /api/v1/users/me` 호출 → **백엔드가 JIT로 `users` 행 자동 생성**
   - (참고: 일기 화면은 아직 더미라 백엔드를 안 부른다. **프로필 진입이 유일한 JIT 트리거**)
4. 화면에 닉네임·이메일이 보이면 성공. 곧바로 DB 확인:

```bash
# 터미널 3 (psql). 비밀번호는 application-local.yml의 DB_PASSWORD 값.
PGPASSWORD='<로컬 DB 비밀번호>' "/c/Program Files/PostgreSQL/18/bin/psql" -U recorme -d recorme -h localhost \
  -c "SELECT id, supabase_uid, nickname, email, bio, created_at FROM users ORDER BY id;"
```
→ **닉네임 = 가입 시 입력값**, **email = 가입 이메일**, `supabase_uid` 채워짐, `bio`는 NULL(아직 미입력)

### 시나리오 2 — 프로필 수정 → DB 갱신 확인
1. 프로필 화면 → **수정** → 닉네임 변경 + 자기소개(bio) 입력 → 저장 (`PUT /users/me`)
2. 저장 성공 스낵바 + 조회 화면 자동 갱신 확인
3. DB 확인:
```bash
PGPASSWORD='<비밀번호>' "/c/Program Files/PostgreSQL/18/bin/psql" -U recorme -d recorme -h localhost \
  -c "SELECT id, nickname, bio, updated_at FROM users ORDER BY id;"
```
→ 닉네임·bio 갱신, `updated_at`이 `created_at`보다 나중

### 시나리오 3 — 재로그인 시 중복 가입 없음
1. 로그아웃 → 같은 계정으로 다시 로그인 → 프로필 진입
2. DB 확인:
```bash
PGPASSWORD='<비밀번호>' "/c/Program Files/PostgreSQL/18/bin/psql" -U recorme -d recorme -h localhost \
  -c "SELECT count(*) AS rows FROM users WHERE email = '<가입한 이메일>';"
```
→ **1** (JIT가 supabase_uid로 매핑, 중복 INSERT 없음)

### (선택) 시나리오 4 — 구글 로그인
- 웹에서 구글 로그인은 OAuth 리다이렉트 추가 설정이 필요할 수 있음. 우선 **이메일 흐름 위주**로 검증하고, 구글은 모바일/추가설정 후.

---

## 5. 트러블슈팅

| 증상 | 원인 / 확인 |
|---|---|
| 프로필 진입 시 **401** | 백엔드 토큰 검증 실패. 백엔드 로그에 `INVALID_TOKEN`/JWKS 오류? `supabase.url`이 `https://wcrlawgpmwxyxohwlegc.supabase.co`인지, 인터넷 연결(JWKS fetch) 확인 |
| 브라우저 콘솔 **CORS 에러** | 백엔드 CORS 미적용. `SecurityConfig`의 CORS(`localhost:*` 허용) 확인 |
| `users` 테이블이 **빔** | 프로필 화면에 **진입**했는지(JIT 트리거). 일기 화면만 봤다면 백엔드 호출이 없어 행이 안 생김 |
| 가입 자체가 안 됨 | Supabase **Email provider OFF**. 콘솔에서 Enable |
| 메일이 안 옴 | Confirm ON인데 기본 SMTP 발송 제한. 테스트는 Confirm OFF 권장, 운영은 커스텀 SMTP |
| 앱이 API를 못 부름 | `--dart-define=API_BASE_URL=http://localhost:8080` 빠졌는지(웹 기본값은 에뮬용 10.0.2.2) |

---

## 6. 빠른 확인 한 줄 (users 전체 덤프)
```bash
PGPASSWORD='<비밀번호>' "/c/Program Files/PostgreSQL/18/bin/psql" -U recorme -d recorme -h localhost \
  -c "SELECT id, supabase_uid, nickname, email, bio, created_at, updated_at FROM users ORDER BY id;"
```
또는 DBeaver에서 `recorme` 연결 → `users` 테이블 데이터 탭으로 확인.