# 로컬 웹 테스트 (소셜: 친구·공유·피드·공감)

브라우저에서 풀스택으로 소셜 기능을 테스트하는 절차. 백엔드(로컬 PostgreSQL) + Flutter 웹(Chrome)을 함께 띄운다.

## 사전 요건
- 네이티브 PostgreSQL 18이 `localhost:5432`에 상주(DB/계정 `recorme`). 기동 시 Flyway가 V1~V14 자동 적용.
- `backend/gemini.env`(LLM_API_KEY) 있으면 실제 감정 분석(확정 시 DONE). 없으면 Stub 폴백(감정 NEUTRAL).

## 1) 백엔드
```bash
bash scripts/run-backend.sh
# 또는: cd backend && set -a && source ./gemini.env && set +a && ./gradlew bootRun
```
- `http://localhost:8080/api/v1`, Flyway `now at version v14` 로그 확인.
- CORS는 `localhost:*`/`127.0.0.1:*` 허용(PATCH 포함).

## 2) 웹 앱
```bash
bash scripts/run-web.sh
# 또는: cd app && flutter run -d chrome --web-port=8000 --dart-define=API_BASE_URL=http://localhost:8080
```
- Chrome이 `http://localhost:8000`으로 열린다.

## 3) 로그인 (웹)
- **이메일/비밀번호 로그인 권장**(리다이렉트 불필요, 포트 무관). 이미 확인 완료된 계정으로 로그인.
- 구글 OAuth는 Supabase Site URL/Redirect에 `http://localhost:8000`이 등록돼 있어야 동작(미등록 시 이메일 로그인 사용).
- 로그인하면 Supabase access token이 자동 첨부되고 백엔드가 최초 요청 시 JIT로 `users` 행을 생성한다.

## 4) 소셜 기능 테스트 시나리오
2개 계정이 필요하다 — **일반 창 + 시크릿(Incognito) 창**에 각각 다른 계정으로 로그인.
1. **친구**: 프로필 → 친구 → 친구 추가. 내 친구코드 복사, 상대 창에서 코드/닉네임으로 검색·요청 → 요청함에서 수락.
2. **공개범위**: 일기 작성 시 공개범위 칩(나만/친구/전체) 선택. 확정 후 상세 AppBar에서 공개범위 변경.
3. **공유**: 상세 AppBar 공유(친구/전체 공개일 때). 링크 복사 → `GET /api/v1/diaries/shared/{token}`.
4. **피드**: 하단 4번째 탭. 친구의 FRIENDS/PUBLIC·전체 PUBLIC·본인 기록(모두 DONE)이 감정 카드로. 카드 탭 → 전문.
5. **공감**: 카드/전문의 하트 버튼 토글(낙관적 갱신). 상대 창에서 카운트 반영 확인(새로고침).

> ⚠️ 피드는 **확정(DONE)** 기록만 노출된다. 작성 후 "오늘을 기억하기"로 확정하고 감정 분석(약 1분, Stub면 즉시 NEUTRAL)이 끝나야 피드에 뜬다.
> ⚠️ 한글 IME는 flutter_quill 웹 한계로 에디터 조합 입력이 제한(영문 정상). 소셜 흐름 검증엔 무관.

## 종료
- 각 터미널에서 Ctrl+C. (백그라운드 기동 시 해당 gradle/flutter 프로세스 종료)
