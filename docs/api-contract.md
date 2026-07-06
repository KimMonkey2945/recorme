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
| POST | `/diaries` | 하루 기록 저장(**upsert**: 날짜 미존재 시 생성, 존재 시 갱신). `confirm=false`→DRAFT 저장, `confirm=true`→확정(PENDING·분석 1회). 확정 기록 재저장 시 409 | ○ |
| PUT | `/diaries/{id}` | id 기반 기록 수정(**DRAFT만 수정 가능**, 확정 기록은 409 `DIARY_ALREADY_CONFIRMED`) | ○ |
| GET | `/diaries/{id}` | 기록 상세(테마/음악/감정 포함) | ○ |
| GET | `/diaries/me/summary?yearMonth=YYYY-MM` | 월별 기록 존재 요약(캘린더 dot 렌더링용) | ○ |
| GET | `/diaries/by-date/{date}` | 특정 날짜(YYYY-MM-DD) 내 기록 단건 조회 | ○ |
| GET | `/diaries/me` | 내 기록 목록(커서 페이징) | ○ |
| GET | `/diaries/shared/{shareToken}` | 공유 링크로 단건 조회 | 조건부 |
| DELETE | `/diaries/{id}` | 기록 소프트 삭제(+첨부 사진 행·디스크 파일 즉시 회수) | ○ |
| POST | `/diaries/{id}/images` | 첨부 사진 업로드(multipart, part명 `files`, 1~N장, 기록당 최대 5장·장당 5MB) | ○ |
| DELETE | `/diaries/{id}/images/{imageId}` | 첨부 사진 1장 삭제(행·디스크 파일 회수) | ○ |

```jsonc
// POST /diaries  요청 (날짜 키 기반 upsert)
// confirm: 생략/false → '등록'(DRAFT 저장, 수정 가능·미분석) / true → '오늘을 기억하기'(확정·감정분석 1회)
{ "content": "오늘은...", "writtenDate": "2026-06-15", "visibility": "FRIENDS", "confirm": false }
// 응답 data (분석 전) — 신규 생성은 201 Created, 기존 갱신은 200 OK
// content는 1~500자(앱 maxLength·백엔드 @Size(500)·DB CHECK 동일 상수). 초과 시 400 VALIDATION_ERROR.
// 이미 확정된(DRAFT 아닌) 날짜에 재저장 시 409 DIARY_ALREADY_CONFIRMED (삭제 후 재작성만 허용).
// ⚠️ MVP: theme/track/emotion 필드는 Phase 4. 현재 DiaryResponse는 images 포함, theme/track 미포함.
// 등록(confirm=false) 응답: analysisStatus="DRAFT"
{ "id": 10, "shareToken": "...", "content": "오늘은...", "writtenDate": "2026-06-15",
  "visibility": "FRIENDS", "analysisStatus": "DRAFT", "images": [] }
// 확정(confirm=true) 응답: analysisStatus="PENDING" → 이후 분석 완료 시 DONE
{ "id": 10, "shareToken": "...", "content": "오늘은...", "writtenDate": "2026-06-15",
  "visibility": "FRIENDS", "analysisStatus": "PENDING", "images": [] }

// GET /diaries/{id}  응답 data (MVP) — analysisStatus: DRAFT/PENDING/DONE/FAILED
{ "id": 10, "shareToken": "...", "content": "...", "writtenDate": "2026-06-15", "visibility": "FRIENDS",
  "analysisStatus": "PENDING",
  "images": [ { "id": 1, "url": "/files/diaries/2026/06/{uuid}.jpg" },
              { "id": 2, "url": "/files/diaries/2026/06/{uuid}.jpg" } ] }
//    (Phase 4에서 emotion/theme/track 필드가 추가될 예정 — analysisStatus=DONE 시 채워짐)

// POST /diaries/{id}/images  요청: multipart/form-data, part명 "files"(여러 장 가능)
//    응답 data: 갱신된 전체 이미지 목록 [{ id, url }]. 기록당 5장 초과 시 409 IMAGE_LIMIT_EXCEEDED,
//    비이미지/손상 파일 413·400(INVALID_FILE), 장당 5MB 초과 413(FILE_TOO_LARGE).
// DELETE /diaries/{id}/images/{imageId}  응답: success=true (행·디스크 파일 회수)
```

```jsonc
// GET /diaries/me/summary?yearMonth=2026-06  응답 data
// 해당 월에 (소프트 삭제되지 않은) 기록이 존재하는 날짜 목록 → 캘린더 dot 표시에 사용
{ "yearMonth": "2026-06", "dates": ["2026-06-01", "2026-06-03", "2026-06-15"] }

// GET /diaries/by-date/2026-06-15  응답 data
// 해당 날짜 기록이 없으면 404 + error.code = "DIARY_NOT_FOUND"
{ "id": 10, "shareToken": "...", "content": "...", "writtenDate": "2026-06-15", "visibility": "FRIENDS",
  "analysisStatus": "DONE", "images": [ /* { id, url } ... */ ] }

// GET /diaries/me?cursor=&size=  응답 data (커서 페이징, id DESC, OFFSET 미사용)
// 목록 항목은 N+1 회피를 위해 이미지 전체 대신 대표 1장(thumbnailUrl)·총 개수(imageCount)만 포함.
{ "items": [ { "id": 12, "content": "...", "writtenDate": "2026-06-16", "analysisStatus": "DONE",
               "thumbnailUrl": "/files/diaries/2026/06/{uuid}.jpg", "imageCount": 2 } ],
  "nextCursor": 12, "hasNext": true }
```

> **캘린더 진입 흐름**: 메인(캘린더) 화면은 `GET /diaries/me/summary`로 점(dot)을 그린다. 사용자가 날짜를 탭하면 `GET /diaries/by-date/{date}`로 단건을 조회해, **있으면 상세 화면, 404면 신규 작성 화면**으로 분기한다. 두 엔드포인트 모두 `(user_id, written_date)` 인덱스로 처리되어 `/diaries/me` 전체 페이징보다 효율적이다.

> `analysisStatus`가 `PENDING`이면(확정 직후) 클라이언트는 상세를 재조회(폴링)해 분석 결과(테마/음악)를 갱신한다. 상세 화면은 "분석 중(약 1분)"을 표시하고 `DONE`이 되면 자동 갱신한다.

> **하루 1기록 + draft→확정 정책**: `POST /diaries`는 `(user_id, written_date)` 부분 유니크(`deleted_at IS NULL`)를 충돌 키로 한 upsert다. 같은 날짜로 다시 저장하면 INSERT 대신 기존 행을 UPDATE한다. 덕분에 클라이언트는 기록 `id`를 몰라도 항상 `POST /diaries`(날짜+내용)만 호출하면 되고(신규/수정 분기 불필요), 다중 기기·오프라인 동기화로 인한 **중복 날짜 경쟁 조건(409)도 발생하지 않는다**. `confirm=false`는 `DRAFT`(미분석·수정가능)로 저장하고, `confirm=true`는 `PENDING`으로 **확정해 감정 분석을 1회** 수행한다. **`DRAFT` 상태인 기록만 수정 가능**하며, 확정된 기록에 재저장하면 409 `DIARY_ALREADY_CONFIRMED`다(삭제 후 같은 날짜 재작성은 허용). `PUT /diaries/{id}`는 상세 화면에서 id를 이미 아는 경우의 명시적 수정 경로이며, 동일하게 DRAFT만 수정 가능하고 확정 기록은 409다.

### 피드 (feed) — Phase 6 구현본
| 메서드 | 경로 | 설명 | 인증 |
|---|---|---|---|
| GET | `/feed?cursor=&size=` | 본인 + PUBLIC + 수락친구 FRIENDS의 **DONE** 기록 감정 카드(id DESC 커서, 차단 상대 제외) | ○ |
| GET | `/feed/{id}` | 피드 카드 전문(viewer-aware; 볼 수 없으면 404). 기존 owner-only `GET /diaries/{id}`는 유지 | ○ |

> **피드 카드 DTO**: `{ id, authorUuid, authorNickname, authorProfileImageUrl, moodEmoji, aiTitle, preview(content_text 발췌), writtenDate, visibility, primaryEmotion, backgroundColor, accentColor, reactionCount, reactedByMe }` — 전문(content)은 싣지 않고 탭 시 `/feed/{id}`로 조회.

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

## 4. 가시성(visibility) 규칙

| 값 | 조회 가능 대상 |
|---|---|
| `PRIVATE` | 본인만 |
| `FRIENDS` | 본인 + 수락된 친구 |
| `PUBLIC` | 모든 사용자 (피드 노출) |

공유 링크(`shareToken`)는 가시성과 별개의 통로지만 **PRIVATE은 링크로도 차단**된다(구현 확정). `GET /diaries/shared/{shareToken}`은 **활성·확정(DRAFT 아님)·`visibility<>'PRIVATE'`** 기록만 반환하고 그 외엔 404다. 차단(BLOCKED) 관계면 피드/전문 조회에서 상호 비노출(PUBLIC 포함).
