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

## 4. Supabase Redirect URL (앱 딥링크)
- [ ] Authentication → URL Configuration → **Redirect URLs**에 추가:
  - `app.recordapp://login-callback`
  (이 스킴은 제가 Android/iOS에 등록합니다. 다른 이름 원하시면 알려주세요.)

## 5. anon(publishable) 키
- [ ] Supabase → Project Settings → API → **anon public** 키 복사해서 알려주세요
  - (MCP 재연결되면 제가 직접 가져올 수도 있습니다)
  - anon 키는 공개돼도 안전합니다(데이터 보호는 RLS가 담당).

---

## 정리: 제가 받아야 진행 가능한 값
1. anon public 키
2. Google **웹 client id**, **Android client id** (iOS 하면 iOS client id)
3. applicationId / SHA-1 (Android Google 설정에 필요 — 본인이 콘솔에 입력)
4. Google/Kakao 프로바이더를 Supabase 대시보드에서 **ON** 했는지 확인

이 값들이 준비되면 앱 코드에 채워넣고 실제 로그인까지 검증합니다.
