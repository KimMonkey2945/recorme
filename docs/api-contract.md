# record API 계약

> Base URL: `/api/v1`. 모든 응답은 표준 포맷을 따르며, 목록은 커서 페이징을 사용한다.

> ⚠️ **이 문서는 확정 명세가 아니라 작업 기준 스냅샷이다.** 엔드포인트·요청/응답 형태·정책은 개발 진행과 요구사항 변화에 따라 **얼마든지 변경될 수 있으며**, 변경 시 관련 문서(PRD·backend·database)와 함께 정합을 맞춘다.

## 1. 표준 응답 포맷

```jsonc
// 성공
{ "success": true, "data": { /* ... */ }, "error": null }

// 실패
{ "success": false, "data": null, "error": { "code": "DIARY_NOT_FOUND", "message": "기록을 찾을 수 없습니다." } }
```

- HTTP 상태 코드는 의미에 맞게 사용(200/201/400/401/403/404/409/500). 본문 `error.code`로 세부 사유 구분.
- 인증 필요한 엔드포인트는 헤더 `Authorization: Bearer <Supabase access token>`.

## 2. 커서 페이징

- 요청: `?cursor=<lastId>&size=20` (첫 페이지는 `cursor` 생략).
- 응답 `data`: `{ "items": [...], "nextCursor": 1234, "hasNext": true }`.
- 정렬은 `id DESC`(최신순). OFFSET 미사용.

## 3. 엔드포인트

### 인증 (auth)

로그인·세션은 **앱이 Supabase Auth로 직접 처리**한다. 별도 백엔드 로그인/리프레시/로그아웃 엔드포인트는 없다.

- 앱: Supabase SDK로 **소셜 로그인**(구글 `signInWithIdToken` / 카카오 `signInWithOAuth`) 또는 **이메일 가입/로그인**(`signUp`(닉네임은 `user_metadata`) / `signInWithPassword`) → Supabase 세션(access JWT + refresh, SDK가 저장·자동 갱신).
- 앱→백엔드: 보호 API 호출 시 `Authorization: Bearer <Supabase access token>`.
- 백엔드: Supabase JWT를 검증(**JWKS ES256 비대칭**)하고 `sub`(uuid)로 `users`를 JIT 프로비저닝(최초 요청 시 자동 가입). **이메일·소셜 모두 동일 형식의 토큰이라 provider 분기 없이 같은 경로로 처리**된다.
- 로그아웃: 앱에서 `supabase.auth.signOut()`(백엔드 호출 없음).
- 401/만료 시: Supabase SDK가 자동 갱신, 갱신 불가 시 재로그인.

### 사용자/프로필 (users)
| 메서드 | 경로 | 설명 | 인증 |
|---|---|---|---|
| GET | `/users/me` | 현재 사용자 프로필 조회(JIT 프로비저닝 보장) | ○ |
| PUT | `/users/me` | 내 프로필 수정(닉네임·자기소개) | ○ |
| POST | `/users/me/avatar` | 프로필 이미지 업로드(multipart) | ○ |

```jsonc
// GET /users/me  응답 data
{ "uuid": "...", "nickname": "...", "email": "...", "profileImageUrl": "...", "bio": "..." }
// profileImageUrl: 내부 업로드는 상대 경로(/files/avatars/...), 외부 소셜 제공분은 절대 URL.
//                  앱이 http로 시작하면 그대로, 아니면 apiBaseUrl과 결합해 표시한다.

// PUT /users/me  요청 (nickname 필수, bio 선택. email·profileImageUrl은 이 경로에서 수정 불가)
{ "nickname": "새 닉네임", "bio": "한 줄 소개" }
// 응답 data: 갱신된 user (GET /users/me 와 동일 형태)
// 에러: 검증 실패(닉네임 빈값/길이 50 초과, bio 300 초과) → 400 VALIDATION_ERROR / 미인증 → 401 UNAUTHORIZED

// POST /users/me/avatar  요청: multipart/form-data, part name="file" (이미지 1개)
// 응답 data: 갱신된 user (profileImageUrl이 새 경로로 갱신됨). 검증·저장·DB 갱신을 즉시 수행.
// 에러: 비이미지/손상 파일 → 400 INVALID_FILE / 용량 초과 → 413 FILE_TOO_LARGE / 미인증 → 401 UNAUTHORIZED
```

> **프로필 이미지 = 백엔드 파일 업로드.** 닉네임/자기소개 수정(`PUT`)과 이미지 업로드(`POST .../avatar`)를 **분리**해, 텍스트 수정이 이미지를 덮어쓰지 않는다. 파일 바이너리는 백엔드 로컬 디스크에 저장하고 DB에는 경로만 보관한다(BYTEA 미사용, Supabase Storage 미사용). 허용 형식 jpg/png/webp, 최대 5MB(매직바이트 검증).

> provider 범위는 **이메일 + 소셜(카카오·구글)**. 소셜은 Supabase Authorized Client IDs로 검증, 이메일은 Supabase Email provider(확인 메일 필수). **애플은 추후 Supabase Apple provider로 확장**한다.

### 정적 파일 (files)
| 메서드 | 경로 | 설명 | 인증 |
|---|---|---|---|
| GET | `/files/**` | 업로드된 이미지 서빙(UUID 파일명) | ✕(공개) |

> 프로필 이미지는 공유 화면에서 비로그인자도 보므로 공개 서빙한다. 파일명이 UUID라 URL 추측·열거가 불가하다. 컨텍스트 경로를 포함한 실제 URL은 `/api/v1/files/...`이며, DB에는 호스트 비종속 상대 경로(`/files/...`)만 저장한다.

### 기록 (diary)
| 메서드 | 경로 | 설명 | 인증 |
|---|---|---|---|
| POST | `/diaries` | 하루 기록 저장(**upsert**: 날짜 미존재 시 생성, 존재 시 갱신). `confirm=false`→DRAFT 저장, `confirm=true`→확정. 확정 기록 재저장 시 409 | ○ |
| PUT | `/diaries/{id}` | id 기반 기록 수정(**DRAFT만 수정 가능**, 확정 기록은 409 `DIARY_ALREADY_CONFIRMED`) | ○ |
| GET | `/diaries/{id}` | 기록 상세 | ○ |
| GET | `/diaries/me/summary?yearMonth=YYYY-MM` | 월별 기록 존재 요약(캘린더 dot 렌더링용) | ○ |
| GET | `/diaries/by-date/{date}` | 특정 날짜(YYYY-MM-DD) 내 기록 단건 조회 | ○ |
| GET | `/diaries/me` | 내 기록 목록(커서 페이징) | ○ |
| GET | `/diaries/me/emotions/recent` | 최근 사용한 **직접 입력 감정** 목록(작성기 추천 칩용) | ○ |
| GET | `/diaries/shared/{shareToken}` | 공유 링크로 단건 조회 | 조건부 |
| DELETE | `/diaries/{id}` | 기록 소프트 삭제 | ○ |
| POST | `/diaries/images` | **인라인** 이미지 업로드(multipart, part명 `file`, 1장). 반환된 `url`을 앱이 본문 Delta에 삽입 | ○ |

> ⚠️ **정정(구현 기준)**: 첨부 사진은 **기록에 종속된 1:N 리소스가 아니다**. `diary_images` 테이블은 V5에서 제거됐고, 사진은 본문(`content` = Quill Delta JSON)에 **인라인 임베드**된다. 따라서 **응답에 `images[]` 배열은 없고**, 업로드 경로도 `POST /diaries/{id}/images`(기록 종속)가 아니라 **`POST /diaries/images`**(기록 비종속)이며, 개별 이미지 삭제 엔드포인트(`DELETE /diaries/{id}/images/{imageId}`)도 **존재하지 않는다**(본문에서 지우면 저장 시 반영).

```jsonc
// POST /diaries  요청 (날짜 키 기반 upsert)
// confirm: 생략/false → '등록'(DRAFT 저장, 수정 가능) / true → '오늘을 기억하기'(확정)
// content: Quill Delta JSON 문자열(인라인 이미지 임베드 포함). contentText: 평문 1~500자.
// emotion / emotionLabel: 둘 다 선택 사항이며 배타적이다(아래 '감정 입력' 참조).
{ "content": "{\"ops\":[{\"insert\":\"오늘은...\\n\"}]}", "contentText": "오늘은...",
  "writtenDate": "2026-06-15", "visibility": "FRIENDS", "confirm": false,
  "emotion": "JOY", "emotionLabel": null }
// 응답 data — 신규 생성은 201 Created, 기존 갱신은 200 OK
// contentText는 1~500자(앱 maxLength·백엔드 @Size(500)·DB CHECK 동일 상수). 초과 시 400 VALIDATION_ERROR.
// 이미 확정된(DRAFT 아닌) 날짜에 재저장 시 409 DIARY_ALREADY_CONFIRMED (삭제 후 재작성만 허용).

// 등록(confirm=false) 응답: analysisStatus="DRAFT"
{ "id": 10, "shareToken": "...", "content": "{\"ops\":[...]}", "contentText": "오늘은...",
  "writtenDate": "2026-06-15", "visibility": "FRIENDS", "analysisStatus": "DRAFT",
  "emotion": "JOY", "emotionLabel": null, "reactionCount": 0 }

// 확정(confirm=true) 응답: LLM 감정 분석 flag(record.analysis.enabled)에 따라 갈린다.
//   flag OFF(**현재 기본값 — Task 024 적용됨**) → 즉시 analysisStatus="DONE"(PENDING 대기·폴링 없음).
//                              감정은 사용자 입력값(primaryEmotion/emotionLabel), AI 필드는 전부 null.
//   flag ON(record.analysis.enabled=true) → analysisStatus="PENDING" → 비동기 LLM 분석 후 DONE(AI 필드 채움).
// ⚠️ 응답의 감정 필드 키: 프리셋은 primaryEmotion(코드), 자유 입력은 emotionLabel. (요청 바디 키는 emotion/emotionLabel)
{ "id": 10, "shareToken": "...", "content": "{\"ops\":[...]}", "contentText": "오늘은...",
  "writtenDate": "2026-06-15", "visibility": "FRIENDS", "analysisStatus": "DONE",
  "primaryEmotion": "JOY", "emotionLabel": null, "reactionCount": 0 }

// GET /diaries/{id}  응답 data — analysisStatus: DRAFT/PENDING/DONE/FAILED
// images[] 배열은 없다(사진은 content Delta 안에 인라인 임베드).
{ "id": 10, "shareToken": "...", "content": "{\"ops\":[...]}", "contentText": "...",
  "writtenDate": "2026-06-15", "visibility": "FRIENDS", "analysisStatus": "DONE",
  "primaryEmotion": "JOY", "emotionLabel": null, "reactionCount": 3 }

// POST /diaries/images  요청: multipart/form-data, part명 "file"(1장)
//    응답 data: { "url": "/files/diaries/2026/06/{uuid}.jpg" } — 앱이 이 경로를 본문 Delta에 삽입한다.
//    비이미지/손상 파일 400 INVALID_FILE, 5MB 초과 413 FILE_TOO_LARGE.
```

**감정 입력 (Phase 7 — 사용자 직접 입력)**

```jsonc
// SaveDiaryRequest 의 감정 필드 (POST /diaries · PUT /diaries/{id} 공통)
//   emotion      : 프리셋 코드(JOY/SADNESS/ANGER/CALM/ANXIETY/NEUTRAL). emotion_types 마스터 참조. nullable
//   emotionLabel : 직접 입력 감정(자유 텍스트, 최대 20자). nullable
// ▸ 둘 다 **선택 사항**이다 — 감정을 넣지 않아도 확정(오늘을 기억하기)할 수 있다.
// ▸ 둘을 **동시에 지정하면 400 EMOTION_CONFLICT** (배타적).
{ "emotion": "CALM",  "emotionLabel": null }        // 프리셋 선택
{ "emotion": null,    "emotionLabel": "설레는" }     // 직접 입력(≤20자)
{ "emotion": null,    "emotionLabel": null }        // 감정 미입력(정상)
{ "emotion": "CALM",  "emotionLabel": "설레는" }     // ✗ 400 EMOTION_CONFLICT

// GET /diaries/me/emotions/recent  응답 data
// 내가 최근에 쓴 **직접 입력 감정**을 최신순으로(중복 제거, 상한 10) — 작성기의 '최근 사용' 추천 칩.
{ "items": ["설레는", "지치는", "뿌듯한"] }
```

> ✅ **위 '감정 입력'은 Task 024로 구현됨.** 기본값 `record.analysis.enabled=false` 에서 감정은 **사용자 직접 입력**(프리셋 `emotion` 또는 자유 텍스트 `emotionLabel`, 상호 배타·둘 다 선택)이고 확정 시 즉시 `DONE` 이다. `emotionLabel` 은 저장·상세 응답·`GET /diaries/me/emotions/recent` 로 라운드트립한다. flag 를 `true` 로 켜면 V7 의 LLM 비동기 분석(`PENDING`→`DONE`)이 무손상 복구된다. 감정은 **순수 기록 메타데이터**(캘린더 점 색·감정 칩·월간 회고 통계 전용)이며 **캐릭터 리액션·미션 판정·아이템 해금 어디에도 관여하지 않는다**(캐릭터 도메인에 감정 규칙 없음).

```jsonc
// GET /diaries/me/summary?yearMonth=2026-06  응답 data
// 해당 월에 (소프트 삭제되지 않은) 기록이 존재하는 날짜 목록 → 캘린더 dot 표시에 사용
{ "yearMonth": "2026-06", "dates": ["2026-06-01", "2026-06-03", "2026-06-15"] }

// GET /diaries/by-date/2026-06-15  응답 data (GET /diaries/{id} 와 동일 형태)
// 해당 날짜 기록이 없으면 404 + error.code = "DIARY_NOT_FOUND"
{ "id": 10, "shareToken": "...", "content": "{\"ops\":[...]}", "contentText": "...",
  "writtenDate": "2026-06-15", "visibility": "FRIENDS", "analysisStatus": "DONE",
  "emotion": "JOY", "emotionLabel": null, "reactionCount": 3 }

// GET /diaries/me?cursor=&size=  응답 data (커서 페이징, id DESC, OFFSET 미사용)
// 목록 항목은 본문 전체 대신 평문 발췌(preview)와 대표 이미지 1장(thumbnailUrl)만 싣는다.
{ "items": [ { "id": 12, "preview": "...", "writtenDate": "2026-06-16", "analysisStatus": "DONE",
               "emotion": "CALM", "emotionLabel": null,
               "thumbnailUrl": "/files/diaries/2026/06/{uuid}.jpg" } ],
  "nextCursor": 12, "hasNext": true }
```

> **캘린더 진입 흐름**: 메인(캘린더) 화면은 `GET /diaries/me/summary`로 점(dot)을 그린다. 사용자가 날짜를 탭하면 `GET /diaries/by-date/{date}`로 단건을 조회해, **있으면 상세 화면, 404면 신규 작성 화면**으로 분기한다. 두 엔드포인트 모두 `(user_id, written_date)` 인덱스로 처리되어 `/diaries/me` 전체 페이징보다 효율적이다.

> ⚠️ **확정 후 폴링(현재 동작)**: LLM 감정 분석이 **활성**이므로 `confirm=true` 응답은 `PENDING`이고, 비동기 분석 완료 후 `DONE`이 된다 — 클라이언트는 기존의 "상세 재조회 → `DONE` 시 자동 갱신" 경로를 그대로 쓴다. Task 024로 분석 flag를 끄면 `confirm=true` 응답이 곧 `DONE`이 되어 폴링이 사라지고, 확정 직후 바로 캐릭터 리액션(`GET /characters/me/reaction?diaryId=`, Task 028)으로 넘어가게 된다.

> **하루 1기록 + draft→확정 정책**: `POST /diaries`는 `(user_id, written_date)` 부분 유니크(`deleted_at IS NULL`)를 충돌 키로 한 upsert다. 같은 날짜로 다시 저장하면 INSERT 대신 기존 행을 UPDATE한다. 덕분에 클라이언트는 기록 `id`를 몰라도 항상 `POST /diaries`(날짜+내용)만 호출하면 되고(신규/수정 분기 불필요), 다중 기기·오프라인 동기화로 인한 **중복 날짜 경쟁 조건(409)도 발생하지 않는다**. `confirm=false`는 `DRAFT`(수정가능)로 저장하고, `confirm=true`는 **확정**한다. **`DRAFT` 상태인 기록만 수정 가능**하며, 확정된 기록에 재저장하면 409 `DIARY_ALREADY_CONFIRMED`다(삭제 후 같은 날짜 재작성은 허용). `PUT /diaries/{id}`는 상세 화면에서 id를 이미 아는 경우의 명시적 수정 경로이며, 동일하게 DRAFT만 수정 가능하고 확정 기록은 409다. **확정이 코인·경험치·미션 해금의 유일한 트리거이므로, 확정 후 수정 불가 규칙은 보상 어뷰징 방지 장치이기도 하다.**

### 피드 (feed) — Phase 6 구현본
| 메서드 | 경로 | 설명 | 인증 |
|---|---|---|---|
| GET | `/feed?cursor=&size=` | 본인 + PUBLIC + 수락친구 FRIENDS의 **DONE** 기록 감정 카드(id DESC 커서, 차단 상대 제외) | ○ |
| GET | `/feed/{id}` | 피드 카드 전문(viewer-aware; 볼 수 없으면 404). 기존 owner-only `GET /diaries/{id}`는 유지 | ○ |

> **피드 카드 DTO**: `{ id, authorUuid, authorNickname, authorProfileImageUrl, moodEmoji, aiTitle, preview(content_text 발췌), writtenDate, visibility, primaryEmotion, backgroundColor, accentColor, reactionCount, reactedByMe }` — 전문(content)은 싣지 않고 탭 시 `/feed/{id}`로 조회.

> ✅ **현재(Task 024 적용, flag off 기본)**: LLM 분석이 꺼져 있어 `moodEmoji`·`aiTitle`·`backgroundColor`·`accentColor`는 **항상 null**이다(필드는 보존). 앱은 감정 배경색 대신 중립 카드 + 감정 칩(`primaryEmotion` / `emotionLabel`)으로 렌더한다. flag를 켜면 분석 완료(`DONE`) 시 이 필드들이 채워지는 기존 동작으로 돌아간다.

### 친구 (friends) — Phase 6 구현본
| 메서드 | 경로 | 설명 | 인증 |
|---|---|---|---|
| POST | `/friends/requests` | 친구 요청. 바디 `{friendCode}` 또는 `{targetUuid}`(내부 id 비노출). 역방향 대기요청이면 자동 수락. 신규 201 | ○ |
| POST | `/friends/requests/{id}/accept` | 요청 수락(수신자 본인만) | ○ |
| POST | `/friends/requests/{id}/reject` | 요청 거절(행 삭제) | ○ |
| GET | `/friends/requests?direction=incoming\|outgoing&cursor=&size=` | 받은/보낸 요청 목록(커서) | ○ |
| GET | `/friends?cursor=&size=` | 친구 목록(수락됨, 커서) | ○ |
| GET | `/friends/search?query=` | 친구코드 정확 + 닉네임 부분 검색(상한 20, relation 라벨: NONE/REQUESTED/INCOMING/FRIEND/BLOCKED) | ○ |
| DELETE | `/friends/{userUuid}?block=` | 친구 삭제(block=false) 또는 차단(block=true, 상호 비노출). 멱등 | ○ |

> `GET /users/me` 응답에 내 `friendCode`(8자) 포함. 신규 에러코드: `FRIEND_SELF`(400)/`FRIEND_ALREADY`·`FRIEND_REQUEST_ALREADY_SENT`·`FRIEND_BLOCKED`(409)/`FRIEND_REQUEST_NOT_FOUND`(404).

### 공개범위·공유 (Phase 6 구현본)
| 메서드 | 경로 | 설명 | 인증 |
|---|---|---|---|
| PATCH | `/diaries/{id}/visibility` | 공개범위만 변경(`{visibility}`). **확정 기록도 허용**(본문 불변과 분리) | ○ |
| GET | `/diaries/shared/{shareToken}` | 공유 링크 단건 공개 조회(작성자 표시명·본문·테마). 활성·확정·**PRIVATE 아님**만(PRIVATE·DRAFT는 404) | 조건부(비인증 허용) |

### 공감 리액션 (reactions) — Phase 6 구현본
| 메서드 | 경로 | 설명 | 인증 |
|---|---|---|---|
| POST | `/diaries/{id}/reactions` | 공감 추가(1인 1회 EMPATHY, 멱등). 볼 수 없는 글이면 404 | ○ |
| DELETE | `/diaries/{id}/reactions` | 공감 취소(멱등) | ○ |

> 둘 다 `{ reactionCount, reacted }`를 반환(UI 즉시 동기화). 댓글 API는 범위 제외(공감만 제공).

### 작심삼일 (resolutions)

> 작심삼일 = 시작일 + 할일(`title`) + **3일**. 매일 '완료'를 체크해 3일 완주하면 `SUCCESS`, 하루라도 그 날(KST 자정 전) 미완료면 `FAILED`. 성공하면 '다음 3일'로 **연장**해 연속(streak)을 이어간다. 동시에 여러 개 진행 가능.

| 메서드 | 경로 | 설명 | 인증 |
|---|---|---|---|
| POST | `/resolutions` | 작심삼일 생성(신규 리소스 → **201**) | ○ |
| GET | `/resolutions/me?status=&cursor=&size=` | 내 결심 목록(커서 페이징, id DESC). `status` 필터 optional | ○ |
| GET | `/resolutions/me/calendar?yearMonth=YYYY-MM` | 월별 캘린더((날짜, 결심)당 1행) | ○ |
| GET | `/resolutions/{id}` | 결심 단건 상세(헤더 + 3일 체크) | ○ |
| POST | `/resolutions/{id}/checks/today` | 오늘자 완료 체크(**멱등**) | ○ |
| POST | `/resolutions/{id}/extend` | 성공한 결심을 '다음 3일'로 연장(신규 리소스 → **201**) | ○ |
| PUT | `/resolutions/{id}` | 진행 중(ONGOING) 결심의 제목·알림 시각 수정(시작일은 수정 불가) | ○ |
| DELETE | `/resolutions/{id}` | 결심 취소(소프트 삭제) | ○ |

```jsonc
// POST /resolutions  요청
// startDate: "yyyy-MM-dd"(오늘/미래만, 과거는 400). endDate는 서버가 startDate+2로 파생(요청에 없음).
// reminderTime: "HH:mm" 또는 "HH:mm:ss"(매일 알림 벽시계 시각, KST). 생략/null이면 알림 없음.
{ "title": "매일 물 2L 마시기", "startDate": "2026-07-01", "reminderTime": "21:00" }
// 응답 data (201 Created) = ResolutionDetail
{ "id": 42, "title": "매일 물 2L 마시기", "startDate": "2026-07-01", "endDate": "2026-07-03",
  "status": "ONGOING", "reminderTime": "21:00:00", "streakSeq": 1,
  "checks": [
    { "checkDate": "2026-07-01", "dayIndex": 1, "status": "PENDING", "completedAt": null },
    { "checkDate": "2026-07-02", "dayIndex": 2, "status": "PENDING", "completedAt": null },
    { "checkDate": "2026-07-03", "dayIndex": 3, "status": "PENDING", "completedAt": null } ] }
// title 1~100자(백엔드 @Size(100)·DB CHECK 동일 상수). status: ONGOING/SUCCESS/FAILED.
// streakSeq: 연장 체인 내 순번(1부터, "N연속"). checks는 생성 시 3행(day_index 1·2·3) 프리생성.

// GET /resolutions/me?status=ONGOING&cursor=&size=  응답 data (커서 페이징, id DESC, OFFSET 미사용)
// status(옵션): ONGOING|SUCCESS|FAILED. 항목은 상세의 checks 대신 dayStatuses만 얇게 싣는다.
// ⚠️ dayStatuses는 배열이 아니라 day_index 순 체크 상태를 콤마로 결합한 "문자열"이다
//    (예: "DONE,PENDING,PENDING"). 클라이언트가 콤마로 분해해 1·2·3일차 도트로 렌더한다.
{ "items": [
    { "id": 42, "title": "매일 물 2L 마시기", "startDate": "2026-07-01", "endDate": "2026-07-03",
      "status": "ONGOING", "streakSeq": 1, "dayStatuses": "DONE,PENDING,PENDING" } ],
  "nextCursor": 42, "hasNext": false }

// GET /resolutions/me/calendar?yearMonth=2026-07  응답 data = List<ResolutionCalendarDay>
// (날짜, 결심)당 1행 — 하루에 여러 결심이 진행될 수 있음. 활성(미삭제) 결심의 체크만.
// resolutionStatus: 소속 결심 상태(ONGOING/SUCCESS/FAILED), checkStatus: 그 날짜 체크 상태(PENDING/DONE/MISSED).
[ { "date": "2026-07-01", "resolutionId": 42, "title": "매일 물 2L 마시기",
    "resolutionStatus": "ONGOING", "checkStatus": "DONE" },
  { "date": "2026-07-02", "resolutionId": 42, "title": "매일 물 2L 마시기",
    "resolutionStatus": "ONGOING", "checkStatus": "PENDING" } ]

// GET /resolutions/{id}  응답 data = ResolutionDetail (위 POST 응답과 동일 형태)

// POST /resolutions/{id}/checks/today  (요청 바디 없음)
// 완료 대상 날짜는 서버가 KST '오늘'로 결정한다(요청에 날짜 인자 없음). 응답 data = 갱신된 ResolutionDetail.
// 멱등: 오늘 체크를 DONE으로 전이하고, 이미 DONE이면 재요청도 200. 3일 모두 DONE이면 status가 SUCCESS로 전이.
// 에러: 진행 중(ONGOING)이 아니면 409 RESOLUTION_NOT_ACTIVE / 오늘 체크가 없으면(미래 시작 등) 409 RESOLUTION_CHECK_NOT_TODAY.

// POST /resolutions/{id}/extend  요청
// reminderTime(옵션): 지정하면 새 결심에 적용, 생략/null이면 이전 결심의 알림 시각을 승계. title·기간은 승계.
{ "reminderTime": "22:00" }
// 응답 data (201 Created) = 새 결심의 ResolutionDetail. 같은 streak_group, streakSeq = 이전 + 1.
// 시작일 = max(이전 endDate + 1, 오늘). 에러: 성공(SUCCESS)이 아니면 409 RESOLUTION_NOT_EXTENDABLE /
//         이미 연장했으면 409 RESOLUTION_ALREADY_EXTENDED.

// PUT /resolutions/{id}  요청 (제목·알림 시각만 수정, 시작일 변경 미지원)
{ "title": "매일 아침 10분 스트레칭", "reminderTime": "07:30" }  // reminderTime=null이면 알림 해제
// 응답 data = ResolutionDetail (위 POST 응답과 동일 형태).
// 진행 중이 아니면 409 RESOLUTION_NOT_ACTIVE, 대상 부재/타인 소유 시 404 RESOLUTION_NOT_FOUND.

// DELETE /resolutions/{id}  응답: success=true (소프트 삭제). 대상 부재/타인 소유 시 404 RESOLUTION_NOT_FOUND.
```

**에러 코드**

| code | HTTP | 발생 상황 |
|---|---|---|
| `RESOLUTION_NOT_FOUND` | 404 | 결심 부재 또는 타인 소유(조회·완료·연장·삭제 공통) |
| `RESOLUTION_NOT_ACTIVE` | 409 | 진행 중(ONGOING)이 아닌 결심에 오늘 완료 시도 |
| `RESOLUTION_CHECK_NOT_TODAY` | 409 | 오늘 완료할 체크가 없음(미래 시작·오늘 체크 부재) |
| `RESOLUTION_NOT_EXTENDABLE` | 409 | 성공(SUCCESS)하지 않은 결심을 연장 시도 |
| `RESOLUTION_ALREADY_EXTENDED` | 409 | 같은 체인에서 이미 다음 3일로 연장함(이중 연장) |

> **상태 전이**: 생성=`ONGOING`(3일 체크 PENDING 프리생성) → 오늘 체크 `DONE` → 3일 완주 시 `SUCCESS`(조건부 1회, 커밋 후 완주 축하 푸시). 하루라도 그 날 자정을 넘겨 미완료면 `FAILED`(자정 배치가 해당 체크를 `MISSED`로, 결심을 `FAILED`로 전이). `SUCCESS`/`FAILED`는 터미널 상태다. **'예정'(미래 시작)은 별도 상태가 아니라 `start_date > 오늘`로 파생**하며, **취소는 소프트 삭제**다.

> **타임존(KST 서버 권위)**: 모든 날짜 판정(오늘·시작일·자정 실패·리마인더 도래)은 서버 기본 타임존과 무관하게 **KST(Asia/Seoul) 벽시계**로 통일한다. `POST /resolutions/{id}/checks/today`는 **날짜 인자를 받지 않고** 서버가 KST '오늘'로 대상 체크를 정한다 — 클라이언트 시계 신뢰·타임존 조작을 배제한다.

### 기기 토큰 (devices)

> FCM 서버 푸시(작심삼일 리마인더·완주 축하)를 위한 기기 등록 토큰 관리. 등록/해제 모두 **멱등**이라 항상 **200**으로 응답한다.

| 메서드 | 경로 | 설명 | 인증 |
|---|---|---|---|
| POST | `/devices/tokens` | 기기 토큰 등록/갱신(upsert, 멱등) | ○ |
| DELETE | `/devices/tokens?token=...` | 기기 토큰 해제(로그아웃 등, 멱등) | ○ |

```jsonc
// POST /devices/tokens  요청
// token: FCM 등록 토큰(비어 있을 수 없음). platform: ANDROID/IOS/WEB.
{ "token": "fcm-registration-token", "platform": "ANDROID" }
// 응답: success=true. 토큰은 전역 유일 → 재로그인/재설치 시 소유를 현재 사용자로 이전(upsert).

// DELETE /devices/tokens?token=fcm-registration-token
// 응답: success=true. 본인 소유 토큰만 삭제, 없거나 타인 소유면 무동작(멱등).
```

### 캐릭터 (character) — Phase 7

> 기록하면 **내 캐릭터가 반응하고, 쌓일수록 캐릭터가 꾸며진다.** 확정('오늘을 기억하기')과 작심삼일 완주가 코인·미션 해금의 트리거이며, 감정은 여기에 **일절 관여하지 않는다**(순수 기록 메타). (경험치/레벨 성장은 보상 재설계로 폐기 — V18.)
>
> **아이템은 `group_code` 단위로 사고·입는다.** 캐릭터마다 체형이 달라 옷 이미지(variant)는 캐릭터별로 존재하지만, API는 그 사실을 노출하지 않는다 — 응답의 `imageUrl`은 **항상 내 선택 캐릭터 기준으로 해석된 variant**다. 캐릭터를 바꿔도 소유·착용은 유지되고 이미지만 갈아끼워진다.

**구현본 (Task 027)**

| 메서드 | 경로 | 설명 | 인증 |
|---|---|---|---|
| GET | `/characters` | 선택 가능한 캐릭터 목록(2종) + 내 보유·선택 여부. 온보딩 좌우 비교용 | ○ |
| GET | `/characters/me` | 내 캐릭터 상태(선택·착용·코인·미확인 보상 수) — 캐릭터 홈 1회 조회 | ○ |
| PUT | `/characters/me/selection` | 캐릭터 선택/교체(`{characterCode}`) | ○ |
| PUT | `/characters/me/equipment` | 착용 **배치 교체**(`group_code` 단위, 전체 스냅샷 PUT) | ○ |
| GET | `/characters/items?slot=` | 아이템 그룹 목록(슬롯 필터, 보유 여부 + 내 캐릭터 기준 variant 이미지) | ○ |
| GET | `/missions` | 미션 목록(달성 여부 + 진행률) | ○ |

**구현본 (Task 028 — 코인 적립 엔진)**

| 메서드 | 경로 | 설명 | 인증 |
|---|---|---|---|
| GET | `/characters/me/wallet` | 코인 잔액 + 미확인 보상 수 | ○ |
| GET | `/characters/me/rewards?cursor=&size=` | 미확인 보상함(커서 페이징, id DESC) | ○ |
| POST | `/characters/me/rewards/ack` | 미확인 보상 전체 확인(뱃지 리셋) | ○ |
| GET | `/characters/me/reaction?diaryId=` | 확정 기록 리액션(대사·코인). 확정 즉시 생성 — 폴링 불필요(없으면 data=null) | ○ |
| POST | `/characters/me/attendance` | 출석 적립(하루 1회). 홈 진입 시 호출 | ○ |
| POST | `/characters/items/{groupCode}/purchase` | 코인으로 아이템 구매(코인 소비). 응답=갱신된 내 캐릭터. 잔액 부족 409 `COIN_INSUFFICIENT`, 게이팅 off 403 `FEATURE_DISABLED` | ○ |

**미구현 — 범위 밖**

| 메서드 | 경로 | 설명 | 인증 |
|---|---|---|---|
| GET | `/characters/me/retrospect?yearMonth=` | 월간 회고(기록·감정 분포·성장 요약) — Task 032 | ○ |

> ✅ **코인 적립 엔진 구현(Task 028, 2026-07-16)**: 출석·기록 확정·작심삼일 1·2일차·완주·연속 7/30/60 마일스톤이 실제로 적립된다(멱등 게이트 `character_events`). `/characters/me` 의 `coinBalance`·`unackedRewardCount`가 실데이터로 채워진다. 적립액·마일스톤은 `record.character.coin.*` 설정으로 조정한다(`docs/coin-rewards.md`).
>
> ✅ **상점 구매 구현(2026-07-16)**: `POST /characters/items/{groupCode}/purchase` — 경합 안전 차감(`balance>=price`, 0행이면 409 `COIN_INSUFFICIENT` + 게이트 롤백 → 재시도 가능) + `PURCHASE:{groupCode}` 멱등 게이트 + 소유 부여. `record.character.coin.coin-enabled`(**기본 on**)가 false면 403 `FEATURE_DISABLED`. V21 카탈로그 5종은 전부 COIN이라, 코인을 모아 이 API로 사면 소유·착용이 열린다.
>
> ⚠️ **아직 없는 것**: **미션 판정·아이템 해금 지급**(미션 `achieved`는 여전히 false, 미션 아이템 보상 미지급). 연속 7일 보상은 미션이 아니라 설정 마일스톤 `streak.7`로 지급된다. `progress`는 `user_progress` 스냅샷 실값을 반영한다. V21 이후 **DEFAULT 아이템이 없어** 신규 유저는 빈 옷장(전부 COIN·잠금)으로 시작한다.
>
> ⚠️ **`thumbnailUrl`·`imageUrl`은 서버 URL이 아니라 앱 로컬 에셋 경로다**(`assets/characters/monkey.png`, `assets/items/hat_party_monkey.png`). 다른 도메인의 이미지 필드(`/files/...` 상대경로 → 앱이 호스트 조립)와 **의미가 다르다.** 캐릭터·아이템 아트는 앱 번들에 동봉되고, 서버는 "어떤 에셋을 그릴지"만 알려준다.
>
> **기본 상태는 JIT 생성(멱등)**: 캐릭터 API 최초 호출 시 서버가 `user_character_state`/`user_wallets`/`user_progress` + **기본 지급 아이템 소유**를 `ON CONFLICT DO NOTHING`으로 심는다. 신규 가입자도 별도 초기화 호출 없이 곧바로 정상 응답을 받는다.

```jsonc
// ===== 구현본 (Task 027) =====

// GET /characters  응답 data
// 온보딩(좌우 2장 대형 비교)과 캐릭터 교체 화면이 함께 쓴다.
// owned 는 MVP 에서 **항상 true** 다(캐릭터 2종 전원 무료 개방). 유료·한정 캐릭터가 생기면
//   이 필드만 실제 소유 판정으로 바뀌고 앱 계약은 그대로다.
{ "selectedCharacter": null,
  "items": [
    { "code": "MONKEY",    "nameKo": "원숭이",
      "tagline": "뭐든 천천히, 오늘도 느긋하게. 여유가 특기인 친구예요.",
      "thumbnailUrl": "assets/characters/monkey.png",    "owned": true, "selected": false },
    { "code": "RED_PANDA", "nameKo": "레서판다",
      "tagline": "부지런히 곁을 지켜요. 정 많고 애착이 강한 친구예요.",
      "thumbnailUrl": "assets/characters/red_panda.png", "owned": true, "selected": false } ] }
// selectedCharacter=null → 온보딩 미완료. 앱은 캐릭터 선택 화면으로 분기한다.

// GET /characters/me  응답 data (캐릭터 홈이 한 번에 그리는 데 필요한 전부)
// ★ 캐릭터 미선택(신규 가입 직후)이어도 **200 + character: null** 이다(404 아님).
//   앱은 이 null 을 **온보딩 미완료 신호**로 읽는다. 이때 equipment=[] 이다.
// ⚠️ level/exp/expToNext 필드는 **보상 재설계(2026-07-15)로 제거**됐다(경험치/레벨 폐기 — V18).
//   현재 응답 필드는 character, coinBalance, unackedRewardCount, equipment 4종이다.
{ "character": { "code": "MONKEY", "nameKo": "원숭이", "riveArtboard": "monkey",
                 "thumbnailUrl": "assets/characters/monkey.png" },
  "coinBalance": 0,          // Task 028 전까지 항상 0(적립 주체 없음)
  "unackedRewardCount": 0,   // Task 028 전까지 항상 0(보상 이벤트 없음)
  "equipment": [
    { "slot": "OUTFIT",    "slotIndex": 0, "groupCode": "OUTFIT_BASIC_TEE", "nameKo": "기본 흰 티셔츠",
      "imageUrl": "assets/items/outfit_basic_tee_monkey.png", "riveSlot": "outfit",
      "renderMeta": { "anchorX": 0.5, "anchorY": 0.55, "scale": 0.60, "z": 30 } },
    { "slot": "ROOM_PROP", "slotIndex": 0, "groupCode": "ROOM_PROP_PLANT", "nameKo": "작은 화분",
      "imageUrl": "assets/items/room_prop_plant.png", "riveSlot": "roomProp0",
      "renderMeta": { "anchorX": 0.82, "anchorY": 0.78, "scale": 0.30, "z": 10 } } ] }
// imageUrl/riveSlot/renderMeta 는 (groupCode + 선택 캐릭터)로 **해석된 variant** 값이다.
//   캐릭터 전용 variant 우선 → 없으면 공용(character_code IS NULL) 폴백.
//   캐릭터 미선택이면 공용 variant 만 해석된다(전용 아이템은 목록·착용 조회에서 빠진다).
// renderMeta 는 Rive 미사용 시 플레이스홀더 렌더러(Task 029)가 쓰는 좌표/스케일. null 가능.

// PUT /characters/me/selection  요청
{ "characterCode": "RED_PANDA" }
// 응답 data: 갱신된 MyCharacter (GET /characters/me 와 동일 형태).
// 착용(equipment)은 group 단위라 **그대로 유지**되고, imageUrl 만 새 캐릭터의 variant 로 재해석된다.
// 에러: **없는 코드·비활성 코드·미보유 캐릭터 → 모두 409 CHARACTER_NOT_OWNED 로 수렴**(404 아님 —
//         캐릭터는 전원 무료 개방이라 '없는 코드'도 '선택할 수 없는 캐릭터'로 통일한다) /
//       착용 중인 아이템의 **새 캐릭터용 variant 가 미제작**이면 → 409 ITEM_VARIANT_MISSING(교체 거부·전체 롤백.
//         교체를 허용하면 홈이 그 아이템을 못 그린 채 조용히 사라지므로 원인을 명시적으로 알린다).

// PUT /characters/me/equipment  요청 — **배치 교체**(보낸 배열이 착용 전체 스냅샷이 된다. PATCH 아님)
// 단일 슬롯(HAT/OUTFIT/GLASSES/PROP/BACKGROUND)은 slotIndex=0 한 칸만, ROOM_PROP 만 0~5 다중 진열.
// 해제는 그 슬롯을 배열에서 빼면 되고, **빈 배열([])이면 전 슬롯 비움**이다(별도 DELETE 엔드포인트 없음).
// 항목 최대 12개(단일 슬롯 5종 + BACKGROUND + ROOM_PROP 6칸).
{ "equipment": [
    { "slot": "OUTFIT",    "slotIndex": 0, "groupCode": "OUTFIT_BASIC_TEE" },
    { "slot": "HAT",       "slotIndex": 0, "groupCode": "HAT_PARTY" },
    { "slot": "ROOM_PROP", "slotIndex": 0, "groupCode": "ROOM_PROP_PLANT" } ] }
// 응답 data: 갱신된 MyCharacter.
// ★ **원자적이다.** 요청 전체를 먼저 검증하고(슬롯 규칙 → 슬롯 일치 → 소유 → variant),
//   하나라도 실패하면 **쓰기 전에** 예외를 던진다(3번째가 미보유면 1·2번도 반영되지 않는다).
// 에러(검증 순서대로):
//   알 수 없는 slot 문자열 / slotIndex 규칙 위반(단일 슬롯에 index>0, ROOM_PROP 범위 초과) /
//     같은 칸 중복 / 같은 group 을 두 칸에 진열   → 400 VALIDATION_ERROR
//   그룹의 slot 과 요청 slot 불일치               → 400 ITEM_SLOT_MISMATCH
//   **없는 groupCode** 또는 미보유 그룹            → 409 ITEM_NOT_OWNED (없는 코드는 소유했을 리 없으므로 수렴)
//   내 캐릭터용 variant 미제작                     → 409 ITEM_VARIANT_MISSING

// GET /characters/items?slot=HAT  응답 data (slot 생략 시 전체. 정렬: slot → sort_order → code)
// 옷장이 쓰는 단일 목록(별도 상점 화면 폐기 — 옷장이 소유/해금/구매 노출의 단일 지점).
//   owned 로 보유/미보유를 가르고, 미보유는 lockedBy(미션 진행률) 또는 coinPrice(코인 가격)를 안내 시트로 노출한다.
{ "items": [
    { "groupCode": "HAT_PARTY", "slot": "HAT", "nameKo": "파티 모자",
      "thumbnailUrl": "assets/items/hat_party.png",
      "acquireType": "MISSION", "coinPrice": 0, "owned": false, "equipped": false,
      "imageUrl": "assets/items/hat_party_monkey.png",
      "renderMeta": { "anchorX": 0.5, "anchorY": 0.18, "scale": 0.42, "z": 40 },
      "lockedBy": { "missionCode": "DIARY_10", "title": "기록 10개", "progress": 6, "threshold": 10 } },
    { "groupCode": "HAT_STRAW", "slot": "HAT", "nameKo": "밀짚모자",
      "thumbnailUrl": "assets/items/hat_straw.png",
      "acquireType": "COIN", "coinPrice": 120, "owned": false, "equipped": false,
      "imageUrl": "assets/items/hat_straw_monkey.png",
      "renderMeta": { "anchorX": 0.5, "anchorY": 0.18, "scale": 0.44, "z": 40 },
      "lockedBy": null } ] }
// thumbnailUrl = 캐릭터 무관 대표 썸네일(목록 그리드용). imageUrl = **내 캐릭터 기준 해석된 variant**(렌더용).
// acquireType: DEFAULT(기본 지급) / MISSION(미션 해금) / COIN(코인 구매 — 옷장 안내 시트에서).
// lockedBy: acquireType=MISSION 이고 **미보유**일 때만 채워진다(해금 진행률 바). 그 외 null.
// ⚠️ imageUrl 이 내 캐릭터 variant 로 해석되지 않으면(미제작) 해당 항목은 **목록에서 조용히 제외**된다
//    (조회 경로라 409 를 내지 않는다 — 착용 시도 시에만 409 ITEM_VARIANT_MISSING 으로 알린다).

// GET /missions  응답 data (정렬: sort_order)
// 해금의 유일한 경로. 진행률은 user_progress 스냅샷의 컬럼 하나만 읽어 **O(1)** 산출한다.
{ "items": [
    { "code": "DIARY_10", "title": "기록 10개", "description": "기록을 10개 확정하면 파티 모자를 드려요.",
      "rule": { "type": "DIARY_COUNT", "threshold": 10 },
      "progress": 6, "threshold": 10, "achieved": false, "achievedAt": null,
      "coinReward": 50, "itemGroupReward": "HAT_PARTY" },
    { "code": "STREAK_7", "title": "7일 연속 기록", "description": "7일 연속으로 기록을 확정해 보세요.",
      "rule": { "type": "CONSECUTIVE_DAYS", "threshold": 7 },
      "progress": 7, "threshold": 7, "achieved": true, "achievedAt": "2026-07-10T12:03:11Z",
      "coinReward": 100, "itemGroupReward": "BG_COZY_ROOM" } ] }
// rule.type: DIARY_COUNT / CONSECUTIVE_DAYS / RESOLUTION_SUCCESS / RESOLUTION_STREAK
//   (★ 감정 기반 규칙은 없다 — 감정은 해금과 완전 분리. LEVEL 규칙은 보상 재설계(V18)로 제거됨)
// rule 은 DB rule(JSONB)의 타입별 상이한 임계값 키(count/days/seq)를 서버가 (type, threshold) 로
//   **정규화**한 형태다 — 앱은 타입별 키를 알 필요가 없다.
// progress 는 threshold 를 넘어도 잘라내지 않는다(예: 12/10) — 앱이 min(progress/threshold, 1) 로 클램프한다.
// achieved 는 **달성 이력(user_missions)이 있는가**로만 판정한다(임계값 도달 ≠ 달성 — 지급은 Task 028).
//   → Task 028 전까지 achieved 는 항상 false, achievedAt 은 null 이다.

// ===== 미구현 — 보상 엔진(Task 028) 이후. 아래는 설계안이다 =====

// POST /characters/items/{groupCode}/purchase  (요청 바디 없음)
// ⚠️ 보상 재설계(2026-07-15): **별도 상점 화면은 폐기**됐다. 구매 진입점은 **옷장**이 유일하다 —
//   미보유 COIN 아이템 타일을 탭하면 안내 시트에 코인 가격이 뜨고, 거기서 이 API를 호출한다.
//   엔드포인트 계약 자체는 그대로다(호출 위치만 상점→옷장).
// 응답 data
{ "groupCode": "HAT_STRAW", "coinBalance": 40, "owned": true }
// 코인 소비는 UPDATE ... WHERE balance >= price 단일 문장(경합 안전) → 0행이면 409 COIN_INSUFFICIENT.
// 에러: 잔액 부족 → 409 COIN_INSUFFICIENT / 이미 보유 → 200(멱등, 잔액 불변) /
//       미션 전용·기본 지급 아이템 구매 시도 → 400 VALIDATION_ERROR /
//       구매 비활성(record.character.coin-enabled=false) → 403 FEATURE_DISABLED.

// GET /characters/me/wallet  응답 data
{ "balance": 120 }

// GET /characters/me/rewards?cursor=&size=  응답 data (커서 페이징, id DESC, OFFSET 미사용)
// 보상 이벤트함 = character_events. acked=false 인 것이 홈 상단 알림 뱃지가 된다.
{ "items": [
    { "id": 91, "eventType": "MISSION", "coinDelta": 50, "balanceAfter": 120,
      "diaryId": null, "acked": false, "createdAt": "2026-07-12T09:00:02Z",
      "payload": { "line": "어쩌다 보니 미션도 끝났네. 축하해, 느긋하게 즐겨.", "missions": ["DIARY_10"],
                   "itemGroups": ["HAT_PARTY"], "balance": 120 } },
    { "id": 90, "eventType": "DIARY_CONFIRM", "coinDelta": 10, "balanceAfter": 90,
      "diaryId": 10, "acked": true, "createdAt": "2026-07-12T09:00:01Z",
      "payload": { "line": "오늘도 잘 마무리했네.", "missions": [], "itemGroups": [], "balance": 90 } } ],
  "nextCursor": 90, "hasNext": true }

// POST /characters/me/rewards/ack  요청 — 확인 처리(멱등). ids 생략 시 미확인 전체를 확인 처리.
{ "ids": [91] }
// 응답 data: { "unackedRewardCount": 0 }

// GET /characters/me/reaction?diaryId=10  응답 data
// 리액션 오버레이의 단일 소스(앱이 보상을 스스로 계산하지 않는다).
// 획득이 없어도 대사(line)는 항상 1줄 온다(character_lines 의 CONFIRM 맥락에서 가중 랜덤 선택,
//   캐릭터 전용 대사 → 없으면 공용 폴백). 해당 확정 이벤트가 아직 없으면 404 REACTION_NOT_READY.
{ "diaryId": 10,
  "characterCode": "MONKEY",
  "line": "오늘도 한 줄 남겼네. 천천히 해도 다 남더라.",
  "riveTrigger": "nod",                // character_lines.rive_trigger (null=기본 모션)
  "coinDelta": 10, "coinBalance": 90,
  // ⚠️ levelUp/level/exp/expToNext 필드는 **보상 재설계로 제거**(경험치/레벨 폐기 — V18).
  //    Task 028/032 구현 시 이 필드들은 없다.
  "achievedMissions": [
    { "code": "DIARY_10", "title": "기록 10개",
      "itemGroupReward": { "groupCode": "HAT_PARTY", "nameKo": "파티 모자",
                           "imageUrl": "assets/items/hat_party_monkey.png" },
      "coinReward": 50 } ],
  "eventId": 90 }
// 앱은 오버레이를 닫을 때 POST /characters/me/rewards/ack {"ids":[eventId, ...]} 를 보낸다.

// GET /characters/me/retrospect?yearMonth=2026-07  응답 data (월간 회고 = 락인)
// 감정이 실제로 쓰이는 유일한 곳(통계). 캐릭터 성장과 나란히 보여 준다.
{ "yearMonth": "2026-07",
  "confirmedCount": 18, "consecutiveDaysMax": 9,
  "resolutionSuccessCount": 2,
  "emotions": [ { "code": "JOY", "labelKo": "기쁨", "count": 7 },
                { "code": "CALM", "labelKo": "평온", "count": 5 },
                { "label": "설레는", "count": 3 } ],   // code 없는 항목 = 직접 입력 감정
  "coinEarned": 210,
  // ⚠️ levelStart/levelEnd 필드는 **보상 재설계로 제거**(경험치/레벨 폐기 — V18).
  //    회고의 성장 지표는 코인 획득(coinEarned)·획득 아이템(unlockedItems)으로만 표현한다.
  "unlockedItems": [ { "groupCode": "HAT_PARTY", "nameKo": "파티 모자",
                       "imageUrl": "assets/items/hat_party_monkey.png" } ] }
```

> **보상은 서버가 멱등하게 확정한다(Task 028 설계).** 기록 확정·작심삼일 완주는 커밋 후(`AFTER_COMMIT`) 비동기로 보상 엔진에 전달되고, 엔진은 `character_events(user_id, event_key)` **UNIQUE 게이트**를 먼저 꽂아 **1행이 들어간 경우에만** 코인 적립·미션 해금을 실행한다(경험치/레벨은 보상 재설계로 폐기 — V18). 재전달·백스톱 폴러·앱 재시도가 겹쳐도 **이중 적립은 발생하지 않는다**. 앱은 보상을 스스로 계산하지 않고 항상 서버 응답(`/reaction`, `/rewards`)을 그대로 표시한다. 게이트 테이블(`character_events`)은 **V17로 이미 만들어져 있고**, 여기에 행을 쓰는 엔진만 남았다.

**에러 코드 (Phase 7 — Task 027 구현본 4종)**

| code | HTTP | 발생 상황 |
|---|---|---|
| `ITEM_SLOT_MISMATCH` | 400 | 요청한 `slot`이 해당 아이템 그룹의 슬롯과 다름(HAT 칸에 OUTFIT 그룹) |
| `CHARACTER_NOT_OWNED` | 409 | 선택할 수 없는 캐릭터 — **없는 코드·비활성 코드·미보유를 모두 이 코드로 수렴**(404 아님) |
| `ITEM_NOT_OWNED` | 409 | 보유하지 않은 아이템 그룹을 착용 시도(**없는 `groupCode`도 여기로 수렴**) |
| `ITEM_VARIANT_MISSING` | 409 | 내 선택 캐릭터용 variant가 아직 제작되지 않은 아이템을 착용/캐릭터 교체 시도 |

> 슬롯 문자열 오류·`slotIndex` 규칙 위반(단일 슬롯에 index>0, ROOM_PROP 범위 초과)·같은 칸/같은 그룹 중복 지정은 **400 `VALIDATION_ERROR`**(공통 코드)로 응답한다 — 별도 코드를 만들지 않았다.

**에러 코드 (미구현 — 해당 기능 구현 시 추가)**

| code | HTTP | 발생 상황 | 소관 |
|---|---|---|---|
| `EMOTION_CONFLICT` | 400 | `emotion`(프리셋)과 `emotionLabel`(직접 입력)을 **동시에** 지정 | Task 024 |
| `FEATURE_DISABLED` | 403 | 비활성 기능 호출(`coin-enabled=false` 상태의 코인 구매 등) | Task 028 |
| `COIN_INSUFFICIENT` | 409 | 코인 잔액 부족(`UPDATE ... WHERE balance >= price`가 0행) | Task 028 |

## 4. 가시성(visibility) 규칙

| 값 | 조회 가능 대상 |
|---|---|
| `PRIVATE` | 본인만 |
| `FRIENDS` | 본인 + 수락된 친구 |
| `PUBLIC` | 모든 사용자 (피드 노출) |

공유 링크(`shareToken`)는 가시성과 별개의 통로지만 **PRIVATE은 링크로도 차단**된다(구현 확정). `GET /diaries/shared/{shareToken}`은 **활성·확정(DRAFT 아님)·`visibility<>'PRIVATE'`** 기록만 반환하고 그 외엔 404다. 차단(BLOCKED) 관계면 피드/전문 조회에서 상호 비노출(PUBLIC 포함).
