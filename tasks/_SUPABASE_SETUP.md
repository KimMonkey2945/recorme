# Supabase 소셜 로그인 설정 체크리스트 (사용자 작업)

> 이 부분은 외부 콘솔(Google/Kakao/Supabase 대시보드) 작업이라 **직접** 하셔야 합니다.
> 코드는 제가 작성하니, 아래만 진행하고 **발급된 값들을 알려주세요.**

> ✅ **진행 상태(2026-06)**: **Google 로그인 경로 완료** — 웹/Android/iOS client id 생성, Supabase Google provider ON + Client IDs(웹+Android+iOS)·Secret 입력, Skip nonce ON, anon 키·client id 앱 코드(`supabase_config.dart`) 반영, `applicationId`=`com.recorme.app`·debug SHA-1 등록.
> 🔲 **남은 작업**: ③ Kakao 로그인 설정, 안드로이드 실제 로그인 검증.

신규 Supabase 프로젝트: `wcrlawgpmwxyxohwlegc`
- URL: `https://wcrlawgpmwxyxohwlegc.supabase.co`
- Auth 콜백: `https://wcrlawgpmwxyxohwlegc.supabase.co/auth/v1/callback`

---

## 0. MCP 재연결 (DB 작업 위해 필요)
- [ ] Claude Code를 **재시작**(또는 `/mcp`에서 supabase 재인증) → MCP가 신규 프로젝트를 가리키게 함
  - `.mcp.json`은 이미 신규 프로젝트로 바꿔놨습니다. 재시작하면 적용됩니다.

## 1. 앱 식별자 확인 (제가 참고)
- [x] `app/android/app/build.gradle.kts`의 `applicationId` = **`com.recorme.app`** (iOS 번들 ID·MainActivity 패키지도 동일하게 변경 완료)
  - 이 값과 **SHA-1 지문**이 Google Android 설정에 필요합니다.
  - debug SHA-1: `7F:7F:A2:74:77:69:7A:AD:5B:87:07:AE:8E:63:E7:FF:04:28:29:7E` (이 PC의 `~/.android/debug.keystore`)

## 2. Google 로그인 설정
### 2-1. Google Cloud Console (https://console.cloud.google.com)
- [ ] 프로젝트 생성/선택 → **OAuth 동의 화면** 구성(외부, 테스트 사용자에 본인 이메일 추가)
- [ ] **사용자 인증 정보 → OAuth 클라이언트 ID** 3개 생성:
  - [ ] **웹 애플리케이션** → `client id` + `client secret` (← Supabase에 입력)
  - [ ] **Android** → 패키지명(applicationId) + SHA-1 입력 → `client id`
  - [ ] **iOS**(아이폰도 할 경우) → 번들 ID → `client id`
### 2-2. Supabase 대시보드
- [ ] Authentication → Providers → **Google** 사용 설정 ON
- [ ] 웹 `client id` + `client secret` 입력
- [ ] "Authorized Client IDs"에 **Android client id**(필요 시 iOS client id) 추가
### → 저에게 알려줄 값
- 웹 client id, Android client id, (iOS client id)

## 3. Kakao 로그인 설정 (웹 OAuth 방식)
### 3-1. Kakao Developers (https://developers.kakao.com)
- [ ] 애플리케이션 추가 → **REST API 키** 확인
- [ ] 카카오 로그인 **활성화 ON**
- [ ] Redirect URI에 등록: `https://wcrlawgpmwxyxohwlegc.supabase.co/auth/v1/callback`
- [ ] 보안 → **Client Secret** 발급(사용 ON)
- [ ] 동의항목: 닉네임, (가능하면) 이메일 ON
### 3-2. Supabase 대시보드
- [ ] Authentication → Providers → **Kakao** 사용 설정 ON
- [ ] REST API 키(= client id) + Client Secret 입력
### → 저에게 알려줄 값
- (대시보드에 입력만 하면 되고, 앱 코드엔 카카오 키가 직접 안 들어갑니다)

## 3-5. 이메일 회원가입/로그인 설정 (신규 — 이메일 인증 기능)
> 앱에 이메일/비밀번호 가입·로그인 + 확인 메일 필수 흐름을 추가했습니다. 아래 콘솔 설정이 필요합니다.
### Supabase 대시보드
- [ ] Authentication → Sign In / Providers → **Email** 활성화 (ON)
- [ ] **Confirm email = ON** (확인 메일 필수 — 미인증 로그인은 서버가 차단)
- [ ] Authentication → Email Templates → **"Confirm signup"** 템플릿 확인
  - 링크가 `{{ .ConfirmationURL }}`을 포함하고 Redirect URL로 돌아오는지 확인
- [ ] 비밀번호 정책: **최소 길이 6자**(앱 폼 검증과 일치). 더 강하게 할 경우 앱 검증도 함께 조정 필요
- [ ] (선택) "Secure email change"/"Secure password change" 정책 확인
### 운영(프로덕션) 주의
- [ ] 기본 Supabase SMTP는 **발송 rate limit이 빡빡**합니다. 실제 출시 전 **커스텀 SMTP**(SendGrid/Resend 등) 설정 권장
### 비고
- 닉네임은 가입 시 `user_metadata.nickname`으로 저장되며, 백엔드 JIT 프로비저닝이 이를 읽어 `users` 행을 만듭니다(별도 콘솔 설정 불필요).
- **중복 가입 안내**: Email enumeration protection이 켜져 있어도 앱이 `signUp` 응답의 `user.identities` 빈 배열을 감지해 "이미 가입된 이메일이에요"를 표시합니다(콘솔 설정 변경 불필요). protection을 끄면 Supabase가 `user_already_exists` 에러를 직접 주며, 앱은 그 경우도 처리합니다.

## 3-6. 웹(E2E) 로그인 + 비밀번호 재설정 설정 (신규)
> 웹에서 구글 로그인·비밀번호 재설정이 동작하려면 아래 콘솔 설정이 필요합니다. (앱 코드는 이미 `kIsWeb` 분기 적용)
### Google — 웹 OAuth
- [ ] Google Cloud Console → 웹 애플리케이션 OAuth 클라이언트의 **승인된 리디렉션 URI**에 `https://wcrlawgpmwxyxohwlegc.supabase.co/auth/v1/callback` 등록
- [ ] Supabase Authentication → Providers → **Google**에 웹 **Client ID + Client Secret**이 입력돼 있는지 확인(모바일과 동일 provider 사용)
  - 웹은 `signInWithOAuth`(리다이렉트) 방식 → supabase_flutter가 현재 origin으로 콜백을 처리합니다.
### Redirect URLs (웹 origin)
- [ ] Authentication → URL Configuration → **Redirect URLs**에 웹 E2E origin 추가:
  - `http://localhost:8000` (그리고 `http://localhost:8000/**`)
  - 비밀번호 재설정은 `http://localhost:8000/reset-password`(앱 `Uri.base.origin + '/reset-password'`)로 돌아옵니다 → 위 와일드카드(`/**`)면 커버됩니다.
  - 실제 배포 도메인이 생기면 그 origin도 함께 등록하세요.
### 비밀번호 재설정 메일 템플릿
- [ ] Authentication → Email Templates → **"Reset password"** 템플릿 활성화/확인
  - 링크가 `{{ .ConfirmationURL }}`(recovery 토큰 포함)을 담고 위 Redirect URL로 돌아오는지 확인
  - 메일 링크 진입 시 앱은 `AuthChangeEvent.passwordRecovery`를 감지해 `/reset-password` 화면으로 유도합니다.

## 4. Supabase Redirect URL (앱 딥링크)
- [ ] Authentication → URL Configuration → **Redirect URLs**에 추가:
  - `app.recordapp://login-callback`
  (이 스킴은 제가 Android/iOS에 등록합니다. 다른 이름 원하시면 알려주세요.)
  - ※ 이메일 **확인 메일 링크**(`emailRedirectTo`)와 **모바일 비밀번호 재설정 링크**도 이 딥링크로 돌아옵니다. 같은 기기에서 메일 링크를 탭하면 앱이 콜백을 받아 자동 로그인/복구됩니다. 다른 기기(PC 등)에서 인증하면 앱에서 다시 로그인하면 됩니다.

## 5. anon(publishable) 키
- [ ] Supabase → Project Settings → API → **anon public** 키 복사해서 알려주세요
  - (MCP 재연결되면 제가 직접 가져올 수도 있습니다)
  - anon 키는 공개돼도 안전합니다(Auth 전용 키이며, 앱 데이터는 Supabase가 아닌 별도 PostgreSQL + 백엔드 인가로 보호됩니다 — Supabase에 앱 데이터 미저장).

---

## 정리: 제가 받아야 진행 가능한 값
1. anon public 키
2. Google **웹 client id**, **Android client id** (iOS 하면 iOS client id)
3. applicationId / SHA-1 (Android Google 설정에 필요 — 본인이 콘솔에 입력)
4. Google/Kakao 프로바이더를 Supabase 대시보드에서 **ON** 했는지 확인

이 값들이 준비되면 앱 코드에 채워넣고 실제 로그인까지 검증합니다.
