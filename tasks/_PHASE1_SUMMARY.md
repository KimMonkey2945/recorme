# Phase 1 완료 요약 + 현재 결정 대기

> 📌 **인증 아키텍처 확정(2026-06)**: 자체 JWT/`SocialVerifier` → **Supabase Auth**로 전환 확정.
> 앱은 Supabase SDK로 소셜 로그인, 백엔드는 Supabase JWT 검증 + `users` JIT 프로비저닝(`users.supabase_uid` 매핑).
> 관련 문서(`docs/`, `CLAUDE.md`, `ROADMAP.md`) 정합화 완료. 백엔드/앱 레거시 코드 정리는 **Task 007/010**에서 수행.

## ✅ Phase 1 (애플리케이션 골격) 전부 완료

| Task | 내용 | 검증 |
|---|---|---|
| 001 | 백엔드 스캐폴드 + Flyway V1(4테이블·부분유니크 `uq_diary_user_day`) + Testcontainers 테스트 코드 | `compileTestJava` 통과 / Docker 실행은 프로젝트 완성 후 |
| 002 | 표준응답·예외·JWT·커서페이징·SocialVerifier 골격 | 단위 테스트 통과 / 컨텍스트(Docker)는 후순위 |
| 003 | Flutter feature-first + go_router 5화면 + 하단 탭 셸 + 인증 가드 | `flutter analyze` 0건 |
| 004 | 모델/DTO + Dio·인터셉터 + secure storage + Riverpod provider | analyze 0건 + 모델 테스트 3/3 |

- 작업 파일: `tasks/001~004*.md`, ROADMAP 갱신 완료
- 앱은 지금 실행하면: 로그인 화면 → "임시 로그인(개발용)" 버튼 → 메인(캘린더)/목록/작성/상세 화면 이동이 백엔드 없이 동작(골격)

---

## ❓ 지금 결정 대기: "freezed 코드 생성" 방향

**freezed란?** Dart 모델의 반복 코드(`fromJson`/`copyWith`/`==` 등)를 자동 생성해주는 도구.
`docs/mobile.md`가 권장. 그런데 현재 Flutter 버전 + 카카오/구글 로그인 패키지 충돌로 그 **자동 생성기(build_runner)가 안 돌아감**.
→ 임시로 모델을 **손으로 작성**해 우회함(동작 동일).

### 선택지
- **A. (권장) 소셜 SDK를 Phase 3로 미루고 freezed 복구**
  - 카카오/구글은 실제 로그인(Task 010) 전엔 불필요 → 지금 빼면 충돌 사라져 freezed 자동 생성 동작
  - docs 원래 방침 유지, Task 010에서 소셜 SDK 재추가 시 재점검
- **B. 손 작성 모델 유지** — 현 상태. 단순·견고하나 모델 많아지면 보일러플레이트 수작업
- **C. Flutter SDK 업그레이드로 정합 시도** — 리스크 가장 큼(전체 툴체인 변경)

### 다음 할 일
- 위 A/B/C 중 선택 → 알려주시면 반영
- 그 후 Phase 2(UI/UX, Task 005~006) 진행 가능
