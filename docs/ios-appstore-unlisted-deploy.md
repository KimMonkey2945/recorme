# iOS 앱스토어 비공개(Unlisted) 배포 실행 체크리스트

> recorme를 **App Store 비공개 배포**로 출시하기 위한 실행용 문서. 검색·차트·추천에 노출되지 않고 **직접 링크로만 설치**된다.
> **Mac 불필요** — Codemagic이 클라우드 macOS로 빌드·서명·업로드를 대행한다. 내 PC는 Windows여도 된다.

## ⚠️ 전제 — 백엔드가 공개로 닿아야 심사를 통과한다 (가장 먼저 확인)

앱스토어는 **앱 설치 파일만** 배포한다. 서버·DB는 별개이며(홈서버 그대로 유지 가능), **Apple 심사관이
실기기에서 로그인·기능을 직접 테스트**한다. 지금 백엔드는 **홈서버 + Tailscale 내부 전용**이라 심사관 폰
(Tailscale 없음)에서 **로그인부터 실패 → 리젝**된다.

- **해결**: 서버를 옮기지 말고 **Tailscale Funnel** 로 홈서버를 **공개 HTTPS(`https://<host>.<tailnet>.ts.net`)**
  로 노출하고 **상시 가동**한다. 절차·주의는 **`docs/deployment.md` → "공개 노출 (Tailscale Funnel)"** 참조.
- **공개 전 보안 조치 완료 필요**: rate limiting·Jenkins 포트 로컬 바인딩·LLM 비용 상한(모두 코드/설정에
  반영됨). 상세는 보안 검토 결과 및 `docs/deployment.md`.
- **앱 연결**: `codemagic.yaml` 의 `API_BASE_URL` 을 이 공개 URL 로 교체해야 앱이 서버에 닿는다(B-2).

## 고정 값 (그대로 사용)

| 항목 | 값 |
|---|---|
| Bundle ID | `com.recorme.app` |
| Firebase 프로젝트 | `recorme-c5e1c` |
| Codemagic 워크플로 | `ios-unlisted-release` (루트 `codemagic.yaml`) |
| 비공개 요청 양식 | https://developer.apple.com/contact/request/unlisted-app/ |

---

## 0. 레포 사전 정비 — ✅ 완료 (코드에 이미 반영됨)

- [x] `app/ios/Runner/Runner.entitlements` 신규 (`aps-environment=production`)
- [x] `app/ios/Flutter/{Debug,Release}.xcconfig` 에 `CODE_SIGN_ENTITLEMENTS` 연결
- [x] `app/ios/Runner/Info.plist` 에 `UIBackgroundModes = remote-notification`
- [x] 루트 `codemagic.yaml` (자동 서명 → IPA → TestFlight 업로드)
- [x] `app/pubspec.yaml` description 정리
- [ ] **1024×1024 앱 아이콘 알파 채널 제거** (알파 있으면 자동 리젝 / Windows에서 편집기·`flutter_launcher_icons`로 재생성 가능)
- [ ] (선택) 런치스크린 브랜딩 — 현재 흰 플레이스홀더
- [ ] **백엔드 공개 노출(Tailscale Funnel) + 보안 조치 완료** — 심사·검증의 숨은 전제. `docs/deployment.md` → "공개 노출" 참조

---

## A. Apple 계정·키 준비 (웹, Mac 불필요)

- [ ] **A-1. Apple Developer Program 가입 완료** (연 $99, 승인 1~2일)
- [ ] **A-2. App ID 등록** — Developer Portal → Identifiers → `+`
  - Bundle ID `com.recorme.app` (Explicit)
  - **Capabilities: Push Notifications 체크** ⚠️ 필수 (안 켜면 서명 실패)
- [ ] **A-3. App Store Connect 앱 레코드 생성** — 내 앱 → `+`
  - 플랫폼 iOS, Bundle ID `com.recorme.app`, 이름 `recorme`, 기본 언어·SKU 지정
  - ⭐ 생성 후 부여되는 **숫자 Apple ID** 를 메모 → **B-2에서 `codemagic.yaml`에 기입**
- [ ] **A-4. APNs 인증키(.p8) 발급** — Developer Portal → Keys → `+` → Apple Push Notifications service(APNs)
  - ⚠️ **다운로드는 1회만 가능** → 안전 보관. Key ID·Team ID 메모
  - → **Firebase 콘솔(`recorme-c5e1c`) → 프로젝트 설정 → Cloud Messaging → Apple 앱 구성 → APNs 인증키 업로드** (iOS 푸시 활성화)
- [ ] **A-5. App Store Connect API 키(.p8) 발급** — App Store Connect → 사용자 및 액세스 → 통합 → App Store Connect API → `+`
  - 권한 **App Manager** / Issuer ID·Key ID·.p8 확보 → **B-1에서 Codemagic에 등록**
- [ ] **A-6. `GoogleService-Info.plist` 추가** — Firebase 콘솔에서 iOS 앱(Bundle ID `com.recorme.app`) 확인 후 plist 다운로드
  - → **`app/ios/Runner/GoogleService-Info.plist`** 위치에 넣기 (레포에 추가)

---

## B. Codemagic 빌드 (웹, Mac 불필요)

- [ ] **B-1. Codemagic 가입·연동** — codemagic.io → GitHub 레포(`record`) 연결
  - Team settings → Integrations → **App Store Connect API 키 등록** (A-5의 Issuer/Key ID/.p8)
  - ⚠️ 등록 이름을 `codemagic.yaml`의 `integrations.app_store_connect: codemagic_asc_api_key` 와 **일치**시키기 (다르면 그 이름으로 수정)
- [ ] **B-2. `codemagic.yaml` 값 채우기** — ① `APP_STORE_APPLE_ID: 0000000000` 을 A-3의 숫자 Apple ID로 교체, ② **`API_BASE_URL` 을 백엔드 공개 주소(Tailscale Funnel `https://<host>.<tailnet>.ts.net`)로 교체** ⚠️ 안 넣으면 앱이 에뮬레이터 기본주소로 빌드돼 실기기·심사관 환경에서 서버에 못 닿는다(`--dart-define` 자동 주입됨)
- [ ] **B-3. 빌드 실행** — 워크플로 `ios-unlisted-release` 수동 실행 또는 브랜치 푸시
  - 자동 서명 → 서명된 `.ipa` 산출 → App Store Connect 자동 업로드(처리에 수십 분)
  - 실패 시 서명/프로파일/capability 로그 확인
- [ ] **B-4. TestFlight 실기기 검증** — ⚠️ **아이폰 필요** (Z Flip3는 Android → 지인 기기/TestFlight 초대)
  - ⚠️ **전제**: 백엔드가 공개로 닿는 상태(Funnel)여야 로그인·기록 검증이 가능하다. **Tailscale 없는 회선**(폰 LTE 등)에서 테스트해 심사관 환경을 재현할 것.
  - 로그인(카카오·구글·이메일) → 일기 작성·확정 → 감정 분석·동적 테마 → **작심삼일 푸시(iOS APNs) 수신**까지 확인

---

## C. 비공개 배포 신청 (웹)

- [ ] **C-1. 버전 정보 작성** — 스크린샷(아이폰 6.7"/6.5" 등), 설명, 지원 URL, 개인정보 처리방침 URL, 카테고리, 연령 등급
- [ ] **C-2. 앱 개인정보(App Privacy) 설문** — 수집 데이터(이메일·사진·일기 텍스트 등) 신고
- [ ] **C-3. 빌드 연결** — B-3에서 올라온 빌드를 버전에 연결
- [ ] **C-4. 심사 메모(Review Notes)에 명시** — "이 앱은 **등록되지 않은 앱(Unlisted)** 으로 배포하기 위한 것입니다." + **소셜 로그인 테스트 계정** 제공. ⚠️ **심사 기간 동안 백엔드 서버(홈서버+Funnel)를 상시 가동**할 것 — 끄면 로그인 불가로 리젝된다.
- [ ] **C-5. 심사에 제출** (전제: 심사 제출 상태여야 요청 가능 — 베타/시험판 불가)
- [ ] **C-6. 비공개 배포 요청 양식 제출** — https://developer.apple.com/contact/request/unlisted-app/
  - ⚠️ 앱 심사 통과 ≠ 비공개 승인 (**별도 검토**, 추가 시간 소요)

---

## D. 승인 후 배포

- [ ] **D-1. 직접 설치 링크 확인** — App Store Connect에서 생성됨. 배포 방법이 자동으로 "등록되지 않은 앱"으로 전환(새 버전부터 적용)
- [ ] **D-2. 링크 공유** — 단축 URL 가능하나 **반드시 링크 동작 테스트**. 검색/차트엔 노출 안 됨
- [ ] **D-3. 접근 통제** — 링크 소지자 누구나 설치 가능 → 앱 내 로그인(Supabase Auth)으로 통제 (이미 구현됨, 요건 충족)

---

## 순서·의존성 요약

```
A-1(가입) ─▶ A-2(App ID+Push) ─▶ A-3(앱 레코드) ──┐
                    └▶ A-4(APNs→Firebase)          ├─▶ B-3(빌드) ─▶ B-4(TestFlight)
   A-5(ASC API키) ─▶ B-1(Codemagic 등록)           │        │
   A-6(GoogleService-Info.plist) ──────────────────┘        ▼
                                              C(심사+비공개 요청) ─▶ D(링크 배포)
```

## 리스크·주의

- **백엔드 공개 미노출 = 리젝**: 심사관이 로그인 테스트를 못 해 반려된다. 배포 전 **Tailscale Funnel 공개 노출 + 상시 가동**을 반드시 확보(`docs/deployment.md`). 홈서버 전원/네트워크가 끊기면 앱 전체가 먹통.
- **Apple 승인 대기**: A-1 완료 전 App Store Connect 접근 불가. A는 병행 가능하나 B부터는 계정 활성 필요.
- **iOS 푸시 미검증**: APNs 경로 실기기 첫 검증 → B-4에서 반드시 확인.
- **아이폰 실기기 필요**: 최종 검증용. 없으면 TestFlight 초대로 지인 기기 활용.
- **1024 아이콘 알파 채널**: 있으면 리젝 → 0번 항목에서 사전 제거.
